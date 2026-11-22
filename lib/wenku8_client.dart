import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Minimal client for the public Wenku8 app endpoints plus the web login form.
/// The API request body is a base64-encoded action string, as used by the
/// original Android client and the current third-party clients.
class Wenku8Client {
  Wenku8Client();

  static const apiUrl = 'http://app.wenku8.com/android.php';
  static const webUrl = 'http://www.wenku8.net';
  static const _cookieKey = 'wenku8_session_cookie_v1';
  static const _appVer = '1.13';
  static const _ua =
      'Dalvik/2.1.0 (Linux; U; Android 11; IN2010 Build/RP1A.201005.001)';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 18);
  final Map<String, String> _cookies = {};
  SharedPreferences? _prefs;
  bool _ready = false;

  bool get hasSession => _cookies.isNotEmpty;
  String? get cookieHeader => _cookies.isEmpty
      ? null
      : _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> ensureReady() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString(_cookieKey);
    if (stored != null && stored.isNotEmpty) {
      for (final part in stored.split(';')) {
        final index = part.indexOf('=');
        if (index > 0) {
          _cookies[part.substring(0, index).trim()] = part.substring(index + 1).trim();
        }
      }
    }
    _ready = true;
  }

  Future<void> _saveCookies() async {
    await ensureReady();
    await _prefs!.setString(
      _cookieKey,
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    );
  }

  void _absorbCookies(HttpClientResponse response) {
    for (final header in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final pair = header.split(';').first;
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      _cookies[name] = value;
    }
  }

  String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Future<({int status, String body, String? location})> _postForm(
    Uri uri,
    Map<String, String> fields, {
    bool followRedirects = true,
  }) async {
    await ensureReady();
    final request = await _http.postUrl(uri);
    request.headers
      ..set(HttpHeaders.userAgentHeader, _ua)
      ..set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    if (_cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader!);
    }
    request.followRedirects = followRedirects;
    request.add(utf8.encode(Uri(queryParameters: fields).query));
    final response = await request.close();
    _absorbCookies(response);
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    await _saveCookies();
    return (
      status: response.statusCode,
      body: _decode(bytes),
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  /// Login through the website first; if the old form is unavailable, fall back
  /// to the app API login action.
  Future<void> login(String username, String password) async {
    await ensureReady();
    _cookies.clear();
    if (username.trim().isEmpty || password.isEmpty) {
      throw const FormatException('请输入用户名和密码');
    }
    var webSuccess = false;
    try {
      final result = await _postForm(
        Uri.parse('$webUrl/login.php'),
        {
          'username': username.trim(),
          'password': password,
          'usecookie': '315360000',
          'action': 'login',
          'submit': '登 录',
        },
        followRedirects: false,
      );
      webSuccess = result.status == 302 ||
          result.status == 303 ||
          (result.location != null &&
              !result.location!.contains('login.php') &&
              _cookies.isNotEmpty);
    } catch (_) {}
    if (!webSuccess) {
      final body = await apiRaw(
        'action=login&username=${Uri.encodeQueryComponent(username.trim())}'
        '&password=${Uri.encodeQueryComponent(password)}',
        allowNumeric: true,
      );
      if (body.trim() != '1') {
        final code = body.trim();
        throw FormatException(
          code == '2' ? '用户名不存在' : code == '3' ? '密码错误' : '登录失败，请检查账号密码或站点状态',
        );
      }
    }
  }

  Future<String> apiRaw(
    String action, {
    bool allowNumeric = false,
    bool binary = false,
    bool allowHtml = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    await ensureReady();
    final request = await _http.postUrl(Uri.parse(apiUrl));
    request.headers
      ..set(HttpHeaders.userAgentHeader, _ua)
      ..set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    if (_cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader!);
    }
    final payload = <String, String>{
      'appver': _appVer,
      'request': base64Encode(utf8.encode(action)),
      'timetoken': '${DateTime.now().millisecondsSinceEpoch}',
    };
    request.add(utf8.encode(Uri(queryParameters: payload).query));
    final response = await request.close().timeout(timeout);
    _absorbCookies(response);
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    await _saveCookies();
    if (binary) {
      if (bytes.isEmpty) throw const FormatException('服务器未返回图片');
      return base64Encode(bytes);
    }
    final body = _decode(bytes).trim();
    if (body.isEmpty) throw const FormatException('服务器返回为空');
    final lower = body.toLowerCase();
    if ((!allowHtml && lower.startsWith('<html')) ||
        lower.contains('welcome</h1>') ||
        lower.contains('cloudflare') ||
        lower.contains('access denied')) {
      throw const FormatException('在线组件接口暂时不可用，请检查网络或稍后重试');
    }
    if (!allowNumeric && !allowHtml && !body.startsWith('<') && !body.startsWith('<?xml')) {
      throw FormatException('在线组件返回异常：${body.length > 24 ? body.substring(0, 24) : body}');
    }
    return body;
  }

  Future<Uint8List?> avatarBytes() async {
    try {
      final body = await apiRaw('action=avatar', binary: true);
      return base64Decode(body);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await ensureReady();
    try {
      await apiRaw('action=logout', allowNumeric: true);
    } catch (_) {}
    _cookies.clear();
    await _saveCookies();
  }
}
