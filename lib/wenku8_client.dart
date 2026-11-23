import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_component.dart';

/// Minimal client for the public Wenku8 app endpoints plus the web login form.
/// The API request body is a base64-encoded action string, as used by the
/// original Android client and the current third-party clients.
class Wenku8Client {
  Wenku8Client();

  static const apiUrl = 'http://app.wenku8.com/android.php/';
  static const webUrl = 'https://www.wenku8.net';
  static const webLoginPageUrl = '$webUrl/login.php';
  static const webLoginUrl = '$webUrl/login.php?do=submit';
  static const _cookieKey = 'wenku8_session_cookie_v1';
  static const _keepSessionKey = 'wenku8_keep_session_v1';
  static const _appVer = '1.30';
  // 原版 1.30 客户端使用的接口版本；旧版 1.13 只作为兼容回退。
  static const _legacyAppVer = '1.13';
  static const _ua =
      'Dalvik/2.1.0 (Linux; U; Android 11; IN2010 Build/RP1A.201005.001)';
  static const _browserUa =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final Map<String, String> _cookies = {};
  SharedPreferences? _prefs;
  bool _ready = false;
  bool _keepSession = true;

  /// Whether the session cookie may be written to this device. Turning this
  /// off keeps the current web/API login alive in memory only.
  bool get keepSession => _keepSession;

  Future<void> setKeepSession(bool value) async {
    await ensureReady();
    if (_keepSession == value) return;
    _keepSession = value;
    await _prefs!.setBool(_keepSessionKey, value);
    if (value) {
      await _saveCookies();
    } else {
      await _prefs!.remove(_cookieKey);
    }
  }

  /// Called when a request proves the saved session is no longer accepted.
  /// UI can then show the login form without repeatedly polling the account.
  void Function()? onAuthenticationLost;

  bool get hasSession => _cookies.isNotEmpty;
  bool get hasWebSession =>
      _cookies.keys.any((name) => name.toLowerCase() == 'jieqiuserinfo');
  String? get cookieHeader => _cookies.isEmpty
      ? null
      : _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> ensureReady() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    _keepSession = _prefs!.getBool(_keepSessionKey) ?? true;
    final stored = _prefs!.getString(_cookieKey);
    if (stored != null && stored.isNotEmpty) {
      for (final part in stored.split(';')) {
        final index = part.indexOf('=');
        if (index > 0) {
          _cookies[part.substring(0, index).trim()] = part
              .substring(index + 1)
              .trim();
        }
      }
    }
    _ready = true;
  }

  Future<void> _saveCookies() async {
    await ensureReady();
    if (!_keepSession) {
      await _prefs!.remove(_cookieKey);
      return;
    }
    await _prefs!.setString(
      _cookieKey,
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    );
  }

  /// Imports the Cookie header captured from the official site's web login.
  /// The web page and the app API share the same account backend, so the
  /// session is sent to the API instead of asking the user to log in again.
  Future<void> importCookieHeader(String header) async {
    await ensureReady();
    final incoming = <String, String>{};
    for (final part in header.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) incoming[name] = value;
    }
    if (incoming.isEmpty) {
      throw const FormatException('没有读取到登录 Cookie，请重新登录');
    }
    _cookies
      ..clear()
      ..addAll(incoming);
    await _saveCookies();
  }

  Future<void> clearSession() async {
    await ensureReady();
    if (_cookies.isEmpty && _prefs!.getString(_cookieKey) == null) return;
    _cookies.clear();
    await _prefs!.remove(_cookieKey);
  }

  bool _absorbCookies(HttpClientResponse response) {
    var changed = false;
    for (final header
        in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final pair = header.split(';').first;
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty) {
        changed = _cookies.remove(name) != null || changed;
      } else if (_cookies[name] != value) {
        _cookies[name] = value;
        changed = true;
      }
    }
    return changed;
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
    Map<String, String> extraHeaders = const {},
  }) async {
    await ensureReady();
    final request = await _http.postUrl(uri);
    request.headers
      ..set(HttpHeaders.userAgentHeader, _browserUa)
      ..set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    extraHeaders.forEach((name, value) => request.headers.set(name, value));
    if (_cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader!);
    }
    request.followRedirects = followRedirects;
    final body = utf8.encode(Uri(queryParameters: fields).query);
    // PHP endpoints on app.wenku8.com close a chunked request without sending
    // headers. Always send an explicit Content-Length.
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final changed = _absorbCookies(response);
    final bytes = await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 20));
    if (changed) await _saveCookies();
    return (
      status: response.statusCode,
      body: _decode(bytes),
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  /// Loads the login form first, as the site expects, so the session Cookie
  /// exists before the credential POST. Some CDN/WAF setups reject a bare POST.
  Future<void> _warmWebLogin() async {
    final request = await _http.getUrl(Uri.parse(webLoginPageUrl));
    request.headers.set(HttpHeaders.userAgentHeader, _browserUa);
    final response = await request.close().timeout(const Duration(seconds: 10));
    final changed = _absorbCookies(response);
    await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 10));
    if (changed) await _saveCookies();
  }

  /// App API 登录优先；API 返回成功但没有留下会话时，退回官网网页登录。
  /// 网页登录会把 Cookie 保存到同一份本地会话，后续目录请求直接复用。
  Future<void> login(String username, String password) async {
    await ensureReady();
    await clearSession();
    if (username.trim().isEmpty || password.isEmpty) {
      throw const FormatException('请输入用户名和密码');
    }
    FormatException? credentialFailure;
    try {
      final emailLogin = username.contains('@');
      final action =
          'action=${emailLogin ? 'loginemail' : 'login'}&username=${Uri.encodeQueryComponent(username.trim())}'
          '&password=${Uri.encodeQueryComponent(password)}';
      var body = await apiRaw(
        action,
        allowNumeric: true,
        timeout: const Duration(seconds: 12),
      );
      var code = body.trim();
      // 1.30 是原版客户端的接口版本。极少数旧接口仍只接受 1.13，
      // 遇到非标准返回时再用旧版本重试一次。
      if (code != '1' && code != '2' && code != '3' && code != '4') {
        body = await apiRaw(
          action,
          allowNumeric: true,
          appVer: _legacyAppVer,
          timeout: const Duration(seconds: 12),
        );
        code = body.trim();
      }
      if (code == '1' && hasSession) return;
      if (code == '2') {
        credentialFailure = FormatException(emailLogin ? '邮箱不存在' : '用户名不存在');
      } else if (code == '3') {
        credentialFailure = const FormatException('密码错误');
      }
      // 1 但没有 Cookie、4 或其它状态都继续尝试网页登录。
    } catch (_) {
      // API 不可达时继续尝试网页登录，但不要掩盖明确的账号/密码错误。
    }
    if (credentialFailure != null) throw credentialFailure;
    var webSuccess = false;
    try {
      await _warmWebLogin();
      final result = await _postForm(
        Uri.parse(webLoginUrl),
        {
          'username': username.trim(),
          'password': password,
          'usecookie': '315360000',
          'action': 'login',
          'submit': '登 录',
        },
        followRedirects: false,
        extraHeaders: {'Referer': webLoginUrl},
      );
      final redirected =
          result.status == 301 || result.status == 302 || result.status == 303;
      final leftLogin =
          result.location != null &&
          !result.location!.toLowerCase().contains('login');
      webSuccess = hasWebSession || (hasSession && (redirected || leftLogin));
    } catch (_) {}
    if (!webSuccess || !hasSession) {
      throw const FormatException('账号密码登录失败，可点“网页登录并自动获取 Cookie”登录');
    }
  }

  Future<String> apiRaw(
    String action, {
    bool allowNumeric = false,
    bool binary = false,
    bool allowHtml = false,
    String? appVer,
    Duration timeout = const Duration(seconds: 15),
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
      'appver': appVer ?? _appVer,
      'request': base64Encode(utf8.encode(action)),
      'timetoken': '${DateTime.now().millisecondsSinceEpoch}',
    };
    final payloadBytes = utf8.encode(Uri(queryParameters: payload).query);
    // app.wenku8.com rejects Dart's default chunked POST with a dropped
    // connection ("Connection closed before full header was received").
    request.contentLength = payloadBytes.length;
    request.add(payloadBytes);
    final response = await request.close().timeout(timeout);
    final changed = _absorbCookies(response);
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (changed) await _saveCookies();
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
    if (!allowNumeric && body.trim() == '4') {
      // 单次接口返回 4 只表示这一次请求没有通过 API 会话校验，不能据此
      // 清掉 Cookie。首页刷新、头像与云书架请求经常与资料页并发，先前
      // 这里直接 clearSession 会让刚登录成功的账号瞬间“自动退出”。
      // 真正的失效交给 WenkuAccount.refreshProfile：先尝试网页资料页，
      // 网页会话也失败时才清会话。
      throw const OnlineAuthenticationRequired();
    }
    if (!allowNumeric &&
        !allowHtml &&
        !body.startsWith('<') &&
        !body.startsWith('<?xml')) {
      throw FormatException(
        '在线组件返回异常：${body.length > 24 ? body.substring(0, 24) : body}',
      );
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

  /// Fetches a page from the official website with the saved web session.
  /// Returns GBK-decoded HTML; callers parse it when the app API cannot
  /// confirm a session imported from the browser.
  Future<String> webGet(String path) async {
    await ensureReady();
    final uri = Uri.parse(path.startsWith('http') ? path : '$webUrl$path');
    final request = await _http.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _browserUa);
    final cookie = cookieHeader;
    if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
    final response = await request.close().timeout(const Duration(seconds: 15));
    final bytes = await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw FormatException('网页请求失败（HTTP ${response.statusCode}）');
    }
    return gbk.decode(bytes, allowMalformed: true);
  }

  Future<({int status, Duration elapsed})> probeApi() async {
    final watch = Stopwatch()..start();
    await apiRaw(
      'action=book&do=list&aid=1&t=0',
      timeout: const Duration(seconds: 10),
    );
    watch.stop();
    return (status: 200, elapsed: watch.elapsed);
  }

  Future<({int status, Duration elapsed})> probeWeb() async {
    final watch = Stopwatch()..start();
    final request = await _http.getUrl(Uri.parse(webUrl));
    request.headers.set(HttpHeaders.userAgentHeader, _browserUa);
    final response = await request.close().timeout(const Duration(seconds: 10));
    await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 15));
    watch.stop();
    return (status: response.statusCode, elapsed: watch.elapsed);
  }

  Future<void> logout() async {
    await ensureReady();
    try {
      await apiRaw('action=logout', allowNumeric: true);
    } catch (_) {}
    await clearSession();
  }
}
