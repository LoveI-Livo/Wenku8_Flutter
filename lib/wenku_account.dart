import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as web;
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
  WenkuAccount({Wenku8Client? client}) : client = client ?? Wenku8Client() {
    this.client.onAuthenticationLost = _sessionLost;
  }

  final Wenku8Client client;
  Uint8List? avatar;
  bool authenticated = false, busy = false, signedToday = false;
  String? operation, error;
  WenkuProfile? profile;
  List<CloudBook>? cloudBooks;
  int? syncedAt;
  bool _initialized = false;
  int _revision = 0;
  int get sessionRevision => _revision;
  int get publicationRevision => _revision;
  bool get keepSession => client.keepSession;

  Future<void> setKeepSession(bool value) async {
    await client.setKeepSession(value);
    notifyListeners();
  }

  void _sessionLost() {
    if (!authenticated) return;
    authenticated = false;
    profile = null;
    avatar = null;
    cloudBooks = null;
    error = '登录状态已过期，请重新登录';
    _revision++;
    notifyListeners();
  }

  static String describeError(Object error) {
    if (error is FormatException) return error.message;
    if (error is SocketException) return '网络连接失败，请检查网络';
    if (error is HttpException) return '文库接口连接被中断，请检查网络后重试';
    return '$error';
  }

  Future<void> initialize() async {
    if (authenticated || busy || _initialized) return;
    _initialized = true;
    try {
      await client.ensureReady();
      if (!client.hasSession) return;
      busy = true;
      notifyListeners();
      await refreshProfile();
      error = null;
    } on OnlineAuthenticationRequired {
      await client.clearSession();
      authenticated = false;
      profile = null;
      error = null;
    } catch (failure) {
      // 以前这里把异常吞掉，主页面只会一直显示“登录失败”而没有原因。
      // 保留会话并允许下一次重试，同时把真实原因交给账号页展示。
      authenticated = false;
      profile = null;
      error = '账号资料加载失败：${describeError(failure)}';
      _initialized = false;
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
      if (!client.hasSession) {
        throw const FormatException('登录接口没有返回会话，请用网页登录');
      }
      await _acceptSession('登录成功，但账号资料暂时读取失败：');
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

  /// Accepts a Cookie header captured from the site's own web login. The
  /// account is only shown as signed in after the API confirms the session,
  /// so a stale or incomplete web login cannot leave the catalogue stuck.
  Future<void> loginWithCookie(String cookieHeader) async {
    if (busy) return;
    busy = true;
    error = null;
    operation = '正在验证网页登录';
    notifyListeners();
    try {
      await client.importCookieHeader(cookieHeader);
      await _acceptSession('网页登录已读取 Cookie，但账号资料暂时读取失败：');
    } catch (failure) {
      if (failure is OnlineAuthenticationRequired) {
        await client.clearSession();
      }
      authenticated = false;
      profile = null;
      error = failure is OnlineAuthenticationRequired
          ? '网页登录未被文库确认，请重新登录'
          : describeError(failure);
      rethrow;
    } finally {
      busy = false;
      operation = null;
      notifyListeners();
    }
  }

  Future<void> _acceptSession(String profileFailurePrefix) async {
    try {
      await refreshProfile(notify: false);
      error = null;
    } on OnlineAuthenticationRequired {
      await client.clearSession();
      authenticated = false;
      profile = null;
      error = '登录未被文库确认，请重新登录';
      rethrow;
    } catch (failure) {
      // A transient profile failure must not discard a session the site
      // already accepted. The catalogue can still load with that Cookie.
      if (!authenticated) {
        authenticated = true;
        _revision++;
      }
      error = '$profileFailurePrefix${describeError(failure)}';
    }
  }

  Future<WenkuProfile> _apiProfile() async {
    final body = await client.apiRaw('action=userinfo');
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
    return WenkuProfile(
      id: uid,
      username: name,
      nickname: nickname ?? '',
      score: score,
      experience: experience,
      rank: rank ?? '',
    );
  }

  /// Reads the official user panel. This is the fallback when a Cookie
  /// imported from the website is accepted by the site but not by the app
  /// API, so web login still produces a real signed-in account.
  Future<WenkuProfile> _webProfile() async {
    final html = await client.webGet('/userdetail.php');
    final doc = web.parse(html);
    final fields = <String, String>{};
    for (final table in doc.querySelectorAll('table')) {
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 2) continue;
        final key = cells.first.text
            .replaceAll(RegExp(r'\s+'), '')
            .replaceAll(RegExp(r'[：:]$'), '');
        if (key.isEmpty) continue;
        var value = '';
        for (final cell in cells.skip(1)) {
          final input = cell.querySelector('input');
          final candidate = (input?.attributes['value'] ?? cell.text).trim();
          if (candidate.isNotEmpty) {
            value = candidate;
            break;
          }
        }
        fields.putIfAbsent(key, () => value);
      }
    }
    int readInt(Iterable<String> keys) {
      for (final key in keys) {
        final digits = (fields[key] ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.isNotEmpty) return int.tryParse(digits) ?? 0;
      }
      return 0;
    }

    final uid = readInt(const ['用户ID', 'UID', '用户id']);
    final username = fields['用户名'] ?? '';
    final nickname = fields['昵称'] ?? '';
    if (uid == 0 && username.isEmpty) {
      throw const OnlineAuthenticationRequired();
    }
    return WenkuProfile(
      id: uid,
      username: username,
      nickname: nickname,
      score: readInt(const ['现有积分', '积分']),
      experience: readInt(const ['经验值', '经验']),
      rank: fields['等级'] ?? fields['头衔'] ?? '',
    );
  }

  void _applyProfile(WenkuProfile value, bool notify) {
    final wasAuthenticated = authenticated;
    final previousId = profile?.id;
    profile = value;
    authenticated = true;
    // Profile refreshes for the same account must not invalidate shelf syncs
    // or make the account page think a new session was created.
    if (!wasAuthenticated || previousId != value.id) _revision++;
    unawaited(_loadAvatar());
    if (notify) notifyListeners();
  }

  Future<void> refreshProfile({bool notify = true}) async {
    WenkuProfile value;
    try {
      value = await _apiProfile();
    } on OnlineAuthenticationRequired {
      value = await _webProfile();
    }
    _applyProfile(value, notify);
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
    final body = await client.apiRaw(
      'action=block&do=sign',
      allowNumeric: true,
    );
    if (body.trim() == '9') {
      signedToday = true;
      notifyListeners();
      throw const FormatException('今天已经签到过了');
    }
    signedToday = true;
    await refreshProfile();
  }

  Future<List<CloudBook>> _apiCloud() async {
    final body = await client.apiRaw('action=bookcase&t=SC');
    if (!body.trim().startsWith('<')) {
      throw const OnlineAuthenticationRequired();
    }
    final doc = XmlDocument.parse(body);
    final books = <CloudBook>[];
    for (final book in doc.findAllElements('book')) {
      final id = int.tryParse(book.getAttribute('aid') ?? '');
      if (id == null) continue;
      final title =
          book.findAllElements('name').firstOrNull?.innerText.trim() ?? '';
      final chapter = book.findAllElements('chapter').firstOrNull;
      books.add(
        CloudBook(
          id: id,
          title: title,
          updated: book.getAttribute('date') ?? '',
          latestChapterId:
              int.tryParse(chapter?.getAttribute('cid') ?? '') ?? 0,
          latestChapter: chapter?.innerText.trim() ?? '',
        ),
      );
    }
    return books;
  }

  /// Reads the browser bookcase when the app API does not accept the web
  /// session. The HTML table is the same one the official website renders.
  Future<List<CloudBook>> _webCloud() async {
    final html = await client.webGet('/modules/article/bookcase.php?classid=0');
    final doc = web.parse(html);
    final books = <CloudBook>[];
    for (final row in doc.querySelectorAll('#checkform table tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;
      final links = row.querySelectorAll('a');
      final titleLinks = links.where((link) {
        final href = link.attributes['href'] ?? '';
        final text = link.text.trim();
        return href.contains('aid=') &&
            text.isNotEmpty &&
            text != '新' &&
            !text.startsWith('[');
      });
      final titleLink = titleLinks.firstOrNull;
      if (titleLink == null) continue;
      final href = titleLink.attributes['href'] ?? '';
      final match = RegExp(r'aid=(\d+)').firstMatch(href);
      final id = int.tryParse(match?.group(1) ?? '');
      if (id == null) continue;
      var latestChapter = '';
      var latestChapterId = 0;
      if (cells.length > 3) {
        final latest = cells[3].querySelector('a');
        latestChapter = latest?.text.trim() ?? cells[3].text.trim();
        final cid = RegExp(
          r'cid=(\d+)',
        ).firstMatch(latest?.attributes['href'] ?? '');
        latestChapterId = int.tryParse(cid?.group(1) ?? '') ?? 0;
      }
      books.add(
        CloudBook(
          id: id,
          title: titleLink.text.trim(),
          updated: cells.length > 5 ? cells[5].text.trim() : '',
          latestChapterId: latestChapterId,
          latestChapter: latestChapter,
        ),
      );
    }
    if (books.isEmpty && !html.contains('bookcase')) {
      throw const OnlineAuthenticationRequired();
    }
    return books;
  }

  Future<List<CloudBook>> refreshCloud() async {
    List<CloudBook> books;
    try {
      books = await _apiCloud();
    } on OnlineAuthenticationRequired {
      books = await _webCloud();
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
    final body = await client.apiRaw(
      'action=bookcase&do=add&aid=$id',
      allowNumeric: true,
    );
    if (body.trim() == '0') throw const FormatException('加入云端书架失败');
    if (cloudBooks != null && !cloudBooks!.any((book) => book.id == id)) {
      cloudBooks = [...cloudBooks!, CloudBook(id: id)];
      notifyListeners();
    }
  }

  Future<void> removeCloud(int id) async {
    final body = await client.apiRaw(
      'action=bookcase&do=del&aid=$id',
      allowNumeric: true,
    );
    if (body.trim() == '0') throw const FormatException('移出云端书架失败');
    cloudBooks?.removeWhere((book) => book.id == id);
    notifyListeners();
  }

  Future<void> recommend(int id) async {
    final body = await client.apiRaw(
      'action=book&do=vote&aid=$id',
      allowNumeric: true,
    );
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

  Future<void> replyReview({
    required int threadId,
    required String content,
  }) async {
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
    _initialized = true;
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
