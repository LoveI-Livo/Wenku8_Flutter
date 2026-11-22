import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'library_state.dart';
import 'online_component.dart';
import 'wenku8_client.dart';
import 'wenku_shelf_sync.dart' show CloudShelfPlan;

class WenkuProfile {
  const WenkuProfile({
    required this.id,
    required this.username,
    required this.nickname,
    required this.score,
    required this.experience,
    required this.rank,
  });
  final int id, score, experience;
  final String username, nickname, rank;
  String get displayName => nickname.isEmpty ? username : nickname;
}

class CloudBook {
  const CloudBook({
    required this.id,
    this.title = '',
    this.updated = '',
    this.latestChapterId = 0,
    this.latestChapter = '',
  });
  final int id, latestChapterId;
  final String title, updated, latestChapter;
}

class CloudUploadResult {
  const CloudUploadResult(this.uploaded, this.remaining, this.error);
  final List<int> uploaded, remaining;
  final Object? error;
}

/// Account state backed by the same [Wenku8Client] as the online catalogue.
/// Session material lives in the client; this class only exposes domain state.
class WenkuAccount extends ChangeNotifier {
  WenkuAccount({Wenku8Client? client}) : client = client ?? Wenku8Client();

  final Wenku8Client client;
  Uint8List? avatar;
  bool authenticated = false, busy = false, signedToday = false;
  String? operation, error;
  WenkuProfile? profile;
  List<CloudBook>? cloudBooks;
  int? syncedAt;
  int _revision = 0;
  int get sessionRevision => _revision;
  int get publicationRevision => _revision;

  static String describeError(Object error) {
    if (error is FormatException) return error.message;
    if (error is SocketException) return '网络连接失败，请检查网络';
    return '$error';
  }

  Future<void> initialize() async {
    if (authenticated || busy) return;
    try {
      await client.ensureReady();
      if (!client.hasSession) return;
      busy = true;
      notifyListeners();
      await refreshProfile();
    } catch (_) {
      authenticated = false;
      profile = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    if (busy) return;
    busy = true;
    error = null;
    operation = '正在登录';
    notifyListeners();
    try {
      await client.login(username, password);
      // 登录票据已经由站点确认。资料接口偶发失败不应把已登录状态退回。
      authenticated = true;
      _revision++;
      try {
        await refreshProfile(notify: false);
        error = null;
      } catch (profileFailure) {
        error = '登录成功，但账号资料暂时读取失败：${describeError(profileFailure)}';
      }
    } catch (failure) {
      authenticated = false;
      profile = null;
      error = describeError(failure);
      rethrow;
    } finally {
      busy = false;
      operation = null;
      notifyListeners();
    }
  }

  Future<void> refreshProfile({bool notify = true}) async {
    final body = await client.apiRaw('action=userinfo', allowNumeric: true);
    if (!body.trim().startsWith('<')) {
      throw const OnlineAuthenticationRequired();
    }
    final doc = XmlDocument.parse(body);
    String? name, nickname, rank;
    int uid = 0, score = 0, experience = 0;
    for (final item in doc.findAllElements('item')) {
      final key = item.getAttribute('name') ?? '';
      final value = item.innerText.trim();
      switch (key) {
        case 'uname':
          name = value;
        case 'nickname':
          nickname = value;
        case 'uid':
          uid = int.tryParse(value) ?? 0;
        case 'score':
          score = int.tryParse(value) ?? 0;
        case 'experience':
          experience = int.tryParse(value) ?? 0;
        case 'rank':
          rank = value;
      }
    }
    if (name == null || name.isEmpty) {
      throw const FormatException('账号资料解析失败，请重新登录');
    }
    profile = WenkuProfile(
      id: uid,
      username: name,
      nickname: nickname ?? '',
      score: score,
      experience: experience,
      rank: rank ?? '',
    );
    authenticated = true;
    _revision++;
    unawaited(_loadAvatar());
    if (notify) notifyListeners();
  }

  Future<void> _loadAvatar() async {
    final bytes = await client.avatarBytes();
    if (bytes != null) {
      avatar = bytes;
      notifyListeners();
    }
  }

  Future<void> connectPublications(String password) async {
    if (profile == null) throw const OnlineAuthenticationRequired();
    await login(profile!.username, password);
  }

  Future<void> signIn() async {
    final body = await client.apiRaw('action=block&do=sign', allowNumeric: true);
    if (body.trim() == '9') {
      signedToday = true;
      notifyListeners();
      throw const FormatException('今天已经签到过了');
    }
    signedToday = true;
    await refreshProfile();
  }

  Future<List<CloudBook>> refreshCloud() async {
    final body = await client.apiRaw('action=bookcase&t=SC');
    if (body.trim().startsWith('<') == false) {
      throw const OnlineAuthenticationRequired();
    }
    final doc = XmlDocument.parse(body);
    final books = <CloudBook>[];
    for (final book in doc.findAllElements('book')) {
      final id = int.tryParse(book.getAttribute('aid') ?? '');
      if (id == null) continue;
      final title = book.findAllElements('name').firstOrNull?.innerText.trim() ?? '';
      final chapter = book.findAllElements('chapter').firstOrNull;
      books.add(CloudBook(
        id: id,
        title: title,
        updated: book.getAttribute('date') ?? '',
        latestChapterId: int.tryParse(chapter?.getAttribute('cid') ?? '') ?? 0,
        latestChapter: chapter?.innerText.trim() ?? '',
      ));
    }
    cloudBooks = books;
    notifyListeners();
    return books;
  }

  Future<CloudShelfPlan> exchangeShelf({
    required Set<int> local,
    Set<int>? lastLocal,
    Set<int>? lastCloud,
  }) async {
    final cloud = await refreshCloud();
    return CloudShelfPlan(
      local: local,
      remote: cloud.map((book) => book.id).toSet(),
      lastLocal: lastLocal,
      lastCloud: lastCloud,
    );
  }

  Future<CloudUploadResult> uploadMissing(Set<int> localIds) async {
    final cloud = await refreshCloud();
    final current = cloud.map((book) => book.id).toSet();
    final uploaded = <int>[];
    Object? failure;
    for (final id in localIds.difference(current)) {
      try {
        await addCloud(id);
        uploaded.add(id);
      } catch (error) {
        failure ??= error;
      }
    }
    final after = await refreshCloud().catchError((_) => cloud);
    return CloudUploadResult(
      uploaded,
      localIds.difference(after.map((book) => book.id).toSet()).toList(),
      failure,
    );
  }

  Future<void> addCloud(int id) async {
    final body = await client.apiRaw('action=bookcase&do=add&aid=$id', allowNumeric: true);
    if (body.trim() == '0') throw const FormatException('加入云端书架失败');
    if (cloudBooks != null && !cloudBooks!.any((book) => book.id == id)) {
      cloudBooks = [...cloudBooks!, CloudBook(id: id)];
      notifyListeners();
    }
  }

  Future<void> removeCloud(int id) async {
    final body = await client.apiRaw('action=bookcase&do=del&aid=$id', allowNumeric: true);
    if (body.trim() == '0') throw const FormatException('移出云端书架失败');
    cloudBooks?.removeWhere((book) => book.id == id);
    notifyListeners();
  }

  Future<void> recommend(int id) async {
    final body = await client.apiRaw('action=book&do=vote&aid=$id', allowNumeric: true);
    if (body.trim() != '1' && body.trim() != '0') {
      throw const FormatException('推荐失败');
    }
  }

  Future<void> postReview({
    required int bookId,
    required String title,
    required String content,
  }) async {
    throw const FormatException('当前在线组件暂未开放书评发送');
  }

  Future<void> replyReview({required int threadId, required String content}) async {
    throw const FormatException('当前在线组件暂未开放书评回复');
  }

  Future<int> mergeCloudToLocal(LibraryState state) async {
    final cloud = cloudBooks ?? await refreshCloud();
    var added = 0;
    for (final book in cloud) {
      if (!state.shelf.contains(book.id)) {
        await state.toggleShelf(book.id);
        added++;
      }
    }
    return added;
  }

  Future<void> logout() async {
    await client.logout();
    authenticated = false;
    profile = null;
    avatar = null;
    cloudBooks = null;
    signedToday = false;
    error = null;
    _revision++;
    notifyListeners();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
