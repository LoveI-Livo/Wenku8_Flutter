import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

/// 用户自行部署的云端解析服务。App 只把网盘直链和登录凭证发送到该地址，
/// 服务器拉取并解析后返回章节；失败时仍回退到本机解析。
class CloudParseSettings extends ChangeNotifier {
  CloudParseSettings._();
  static final instance = CloudParseSettings._();
  static const _endpointKey = 'wenku8-cloud-parse-endpoint-v1';
  static const _tokenKey = 'wenku8-cloud-parse-token-v1';

  String _endpoint = '';
  String _token = '';
  String? _error;

  String get endpoint => _endpoint;
  String get token => _token;
  String? get error => _error;
  bool get enabled => _endpoint.trim().isNotEmpty;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _endpoint = preferences.getString(_endpointKey) ?? '';
      _token = preferences.getString(_tokenKey) ?? '';
      _error = null;
    } catch (_) {
      _error = '无法读取云端解析设置';
    }
    notifyListeners();
  }

  Future<void> save(String endpoint, String token) async {
    final value = endpoint.trim();
    final secret = token.trim();
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !(uri.scheme == 'https' || uri.scheme == 'http')) {
        throw const FormatException('请填写完整的解析接口地址');
      }
    }
    if (secret.length > 4096 || RegExp(r'[\r\n\x00]').hasMatch(secret)) {
      throw const FormatException('解析密钥格式不正确');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_endpointKey, value);
    await preferences.setString(_tokenKey, secret);
    _endpoint = value;
    _token = secret;
    _error = null;
    notifyListeners();
  }
}

class CloudRemoteChapter {
  const CloudRemoteChapter(this.title, this.content);
  final String title;
  final String content;
}

class CloudRemoteDocument {
  const CloudRemoteDocument({
    this.title,
    this.author,
    this.summary,
    this.coverBytes,
    this.chapters = const [],
    this.media = const {},
  });
  final String? title;
  final String? author;
  final String? summary;
  final Uint8List? coverBytes;
  final List<CloudRemoteChapter> chapters;
  final Map<String, Uint8List> media;

  bool get hasMetadata =>
      (title?.trim().isNotEmpty ?? false) ||
      (author?.trim().isNotEmpty ?? false) ||
      (summary?.trim().isNotEmpty ?? false) ||
      coverBytes != null;
}

class CloudParseService {
  CloudParseService._();
  static final instance = CloudParseService._();
  static const _maxResponseBytes = 64 * 1024 * 1024;
  static const _maxImageBytes = 4 * 1024 * 1024;
  static const _maxMediaBytes = 16 * 1024 * 1024;

  /// 发一个不拉取文件的最小请求，验证地址、token、PHP 和 JSON 返回都正常。
  /// 主机端 `index.php` 收到 `test: true` 会直接返回 `{ok: true, test: true}`。
  Future<String> probe(String endpoint, String token) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const FormatException('请填写完整的解析接口地址');
    }
    final value = token.trim();
    if (value.isEmpty || value.length > 4096) {
      throw const FormatException('请填写解析密钥');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Wenku8Mod/0.7.7');
      request.write(jsonEncode({'token': value, 'test': true}));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final data = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        data.addAll(chunk);
        if (data.length > 256 * 1024) break;
      }
      Map<String, dynamic>? map;
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {
        map = null;
      }
      if (response.statusCode == 200 && map?['ok'] == true && map?['test'] == true) {
        return '接口连接正常';
      }
      final error = map?['error'];
      if (error is String && error.trim().isNotEmpty) {
        throw FormatException(error.trim());
      }
      throw FormatException('接口返回 HTTP ${response.statusCode}，请检查地址和部署文件');
    } on FormatException {
      rethrow;
    } on SocketException catch (failure) {
      throw FormatException('无法连接接口：${failure.message}');
    } on TimeoutException {
      throw const FormatException('接口连接超时，请检查主机状态');
    } finally {
      client.close(force: true);
    }
  }

  Future<CloudRemoteDocument?> parse(
    Novel novel, {
    required String resolvedUrl,
    bool metaOnly = false,
  }) async {
    final settings = CloudParseSettings.instance;
    await settings.load();
    if (!settings.enabled) return null;
    final endpoint = Uri.tryParse(settings.endpoint.trim());
    if (endpoint == null) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Wenku8Mod/0.7.7');
      final uri = Uri.tryParse(resolvedUrl);
      final rawName = uri == null || uri.pathSegments.isEmpty
          ? ''
          : Uri.decodeComponent(uri.pathSegments.last);
      final sourceName = rawName.contains('.') && rawName.length <= 512
          ? rawName
          : novel.title;
      request.write(
        jsonEncode({
          'token': settings.token,
          'url': resolvedUrl,
          'name': sourceName,
          'bookId': novel.id,
          'cookie': novel.remoteCookie ?? '',
          'authorization': novel.remoteAuthorization ?? '',
          'metaOnly': metaOnly,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > _maxResponseBytes) {
          await response.drain<void>();
          return null;
        }
      }
      final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['ok'] != true) return null;
      final cover = _image(map['cover']);
      final media = <String, Uint8List>{};
      var mediaBytes = 0;
      if (map['media'] is List) {
        for (final item in map['media'] as List) {
          if (item is! Map) continue;
          final key = item['key'];
          final bytes = _image(item['data']);
          if (key is! String || key.isEmpty || bytes == null) continue;
          if (!RegExp(r'^[a-zA-Z0-9._-]{1,100}$').hasMatch(key)) continue;
          mediaBytes += bytes.length;
          if (mediaBytes > _maxMediaBytes) break;
          media[key] = bytes;
        }
      }
      final chapters = <CloudRemoteChapter>[];
      if (!metaOnly && map['chapters'] is List) {
        for (final item in map['chapters'] as List) {
          if (item is! Map) continue;
          final title = item['title'];
          final content = item['content'];
          if (content is! String || content.trim().isEmpty) continue;
          chapters.add(
            CloudRemoteChapter(
              title is String && title.trim().isNotEmpty
                  ? _limit(title.trim(), 100)
                  : '第 ${chapters.length + 1} 章',
              content,
            ),
          );
        }
      }
      final document = CloudRemoteDocument(
        title: _text(map['title']),
        author: _text(map['author']),
        summary: _text(map['summary']),
        coverBytes: cover,
        chapters: chapters,
        media: media,
      );
      if (metaOnly) return document.hasMetadata ? document : null;
      return chapters.isEmpty ? null : document;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Uint8List? _image(Object? value) {
    if (value is! String || value.isEmpty) return null;
    var data = value;
    final comma = data.indexOf(',');
    if (data.startsWith('data:') && comma > 0) {
      data = data.substring(comma + 1);
    }
    try {
      final bytes = base64Decode(data);
      if (bytes.isEmpty || bytes.length > _maxImageBytes) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : _limit(text, 4000);
  }

  String _limit(String value, int length) =>
      value.length <= length ? value : '${value.substring(0, length)}…';
}
