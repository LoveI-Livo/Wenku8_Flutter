import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'cloud_sources.dart';

/// 光鸭云盘（迅雷旗下）账号接口。网页登录令牌和 App 短信登录共用同一套
/// access_token/refresh_token，云盘读取只需要 Bearer 令牌。
class GuangyaBookClient implements CloudBookClient {
  GuangyaBookClient(this.config, {this.settings, CloudHttp? http})
    : http = http ?? CloudHttp() {
    config.validate();
  }

  CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  static const apiBase = 'https://api.guangyapan.com';
  static const accountBase = 'https://account.guangyapan.com';
  static const clientId = 'aMe-8VSlkrbQXpUR';
  static const ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

  String? _access;
  String? _refresh;
  String? _device;

  @override
  String get root => '';

  void _loadCredential() {
    if (_access != null) return;
    final raw = config.accessToken.trim();
    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _access =
              '${decoded['access_token'] ?? decoded['accessToken'] ?? decoded['token'] ?? ''}';
          _refresh =
              '${decoded['refresh_token'] ?? decoded['refreshToken'] ?? config.refreshToken}';
          _device =
              '${decoded['device_id'] ?? decoded['deviceId'] ?? config.deviceId}';
        }
      } catch (_) {}
    }
    _access ??= raw;
    _refresh ??= config.refreshToken.trim();
    _device ??= config.deviceId.trim();
    if (_access!.trim().isEmpty) {
      throw const CloudSourceFailure(
        '光鸭云盘登录已失效，请重新登录光鸭账号',
        authentication: true,
      );
    }
    if (_device!.trim().isEmpty) _device = GuangyaAuth.deviceId();
  }

  Map<String, String> _headers() => {
    'accept': 'application/json, text/plain, */*',
    'authorization': 'Bearer ${_access ?? ''}',
    'did': _device!,
    'dt': '4',
    'origin': 'https://www.guangyapan.com',
    'referer': 'https://www.guangyapan.com/',
    'user-agent': ua,
  };

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, Object?> body, {
    bool retry = true,
  }) async {
    _loadCredential();
    final uri = Uri.parse('$apiBase$path');
    final res = await http.request(
      'POST',
      uri,
      headers: (_) => {..._headers(), 'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
      allowedStatuses: const {400, 401, 403},
    );
    final text = utf8.decode(await http.bytes(res), allowMalformed: true);
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(text);
      data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    } catch (_) {
      throw const CloudSourceFailure('光鸭云盘返回的数据格式有误');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      if (!retry || !await _refreshToken()) {
        throw const CloudSourceFailure(
          '光鸭云盘登录已失效，请重新登录光鸭账号',
          authentication: true,
        );
      }
      return _request(path, body, retry: false);
    }
    final code = _asInt(data['code'] ?? data['error_code']);
    if (res.statusCode >= 400 || (code != 0 && code != 200)) {
      final message =
          '${data['message'] ?? data['error_description'] ?? data['error'] ?? ''}'
              .trim();
      throw CloudSourceFailure(
        message.isEmpty ? '光鸭云盘请求失败（HTTP ${res.statusCode}）' : message,
        authentication: res.statusCode == 401 || res.statusCode == 403,
      );
    }
    return data;
  }

  Future<bool> _refreshToken() async {
    final token = _refresh?.trim() ?? '';
    if (token.isEmpty) return false;
    try {
      final headers = GuangyaAuth.accountHeaders(_device!);
      final res = await http.request(
        'POST',
        Uri.parse('$accountBase/v1/auth/token'),
        headers: (_) => {
          ...headers,
          'content-type': 'application/json',
          'x-action': '401',
        },
        body: utf8.encode(
          jsonEncode({
            'client_id': clientId,
            'grant_type': 'refresh_token',
            'refresh_token': token,
          }),
        ),
        allowedStatuses: const {400, 401, 403},
      );
      final decoded = jsonDecode(utf8.decode(await http.bytes(res)));
      final data = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final access = '${data['access_token'] ?? data['accessToken'] ?? ''}';
      final refresh = '${data['refresh_token'] ?? data['refreshToken'] ?? ''}';
      if (access.isEmpty) return false;
      _access = access;
      if (refresh.isNotEmpty) _refresh = refresh;
      await settings?.rotateTokens(
        config,
        accessToken: jsonEncode({
          'access_token': access,
          'refresh_token': refresh.isEmpty ? token : refresh,
          'device_id': _device,
        }),
        refreshToken: refresh.isEmpty ? token : refresh,
        deviceId: _device,
        driveId: config.driveId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final data = await _request('/userres/v1/file/get_file_list', {
      'parentId': folder,
      'page': page - 1,
      'pageSize': 100,
      'orderBy': 0,
      'sortType': 0,
    });
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final rows = payload['list'] ?? payload['files'] ?? payload['records'];
    final entries = <CloudBookEntry>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final id =
            '${map['fileId'] ?? map['file_id'] ?? map['id'] ?? map['resId'] ?? ''}';
        final name =
            '${map['fileName'] ?? map['file_name'] ?? map['name'] ?? ''}'
                .trim();
        if (id.isEmpty || name.isEmpty) continue;
        final type = _asInt(
          map['resType'] ?? map['res_type'] ?? map['fileType'],
        );
        final folderEntry =
            type == 2 ||
            type == 3 ||
            map['isDir'] == true ||
            map['dir'] == true ||
            '${map['dirType'] ?? ''}' == '2';
        final entry = CloudBookEntry(
          id: id,
          name: name,
          folder: folderEntry,
          size: _asInt(map['fileSize'] ?? map['file_size'] ?? map['size']),
          extra: {
            'resType': type,
            'parentId': '${map['parentId'] ?? map['parent_id'] ?? folder}',
          },
        );
        if (entry.folder || entry.isBook) entries.add(entry);
      }
    }
    final total = _asInt(payload['total'] ?? payload['totalCount']);
    final next = entries.isEmpty || (total > 0 && page * 100 >= total)
        ? null
        : page + 1;
    return CloudBookListing(entries, nextPage: next);
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list('*', page: page);

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    final data = await _request('/nd.bizuserres.s/v1/get_res_download_url', {
      'fileId': entry.id,
    });
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    var url =
        '${payload['url'] ?? payload['downloadUrl'] ?? payload['download_url'] ?? payload['resUrl'] ?? ''}'
            .trim();
    if (url.isEmpty && data['data'] is String) url = '${data['data']}'.trim();
    if (url.isEmpty) {
      throw const CloudSourceFailure('光鸭云盘没有返回下载地址，请重新登录后再试');
    }
    CloudHttp.validateUrl(Uri.parse(url));
    return url;
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int, int?)? onProgress,
  }) async {
    final url = await directLink(entry);
    if (url == null) throw const CloudSourceFailure('光鸭云盘没有返回下载地址');
    final res = await http.request(
      'GET',
      Uri.parse(url),
      headers: (_) => {
        'referer': 'https://www.guangyapan.com/',
        'user-agent': ua,
      },
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  Future<void> delete(CloudBookEntry entry) async {
    await _request('/nd.bizuserres.s/v1/file/recycle_file', {
      'fileIds': [entry.id],
    });
  }

  @override
  void cancel() => http.close();

  @override
  void close() => http.close();
}

class GuangyaSession {
  const GuangyaSession({
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
  });
  final String accessToken, refreshToken, deviceId;
  String get encoded => jsonEncode({
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'device_id': deviceId,
  });
}

/// 光鸭官网短信登录。网页端同样使用这套接口，登录后得到 access_token。
class GuangyaAuth {
  GuangyaAuth({CloudHttp? http}) : http = http ?? CloudHttp();
  final CloudHttp http;
  String _device = deviceId();
  static const ua = GuangyaBookClient.ua;

  static String deviceId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  static Map<String, String> accountHeaders(String device) => {
    'accept': '*/*',
    'origin': 'https://www.guangyapan.com',
    'referer': 'https://www.guangyapan.com/',
    'user-agent': ua,
    'x-client-id': GuangyaBookClient.clientId,
    'x-client-version': '0.0.1',
    'x-device-id': device,
    'x-device-model': 'chrome%2F147.0.0.0',
    'x-device-name': 'PC-Chrome',
    'x-device-sign': 'wdi10.$device${device.substring(0, 16)}',
    'x-net-work-type': 'NONE',
    'x-os-version': 'MacIntel',
    'x-platform-version': '1',
    'x-protocol-version': '301',
    'x-provider-name': 'NONE',
    'x-sdk-version': '9.0.2',
  };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    Map<String, String> extra = const {},
  }) async {
    final res = await http.request(
      'POST',
      Uri.parse('${GuangyaBookClient.accountBase}$path'),
      headers: (_) => {
        ...accountHeaders(_device),
        ...extra,
        'content-type': 'application/json',
      },
      body: utf8.encode(jsonEncode(body)),
      allowedStatuses: const {400, 401, 403, 409, 429},
    );
    final text = utf8.decode(await http.bytes(res), allowMalformed: true);
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const CloudSourceFailure('光鸭登录接口返回异常');
    return Map<String, dynamic>.from(decoded);
  }

  Future<({String captcha, String verificationId, String device})> requestCode(
    String phone,
  ) async {
    final device = deviceId();
    _device = device;
    final init = await _post('/v1/shield/captcha/init', {
      'client_id': GuangyaBookClient.clientId,
      'action': 'POST:/v1/auth/verification',
      'device_id': device,
      'meta': {'phone_number': phone},
    });
    final payload = init['data'] is Map
        ? Map<String, dynamic>.from(init['data'] as Map)
        : init;
    final captcha =
        '${payload['captcha_token'] ?? payload['captchaToken'] ?? ''}';
    if (captcha.isEmpty) {
      final message = '${init['error_description'] ?? init['message'] ?? ''}'
          .trim();
      throw CloudSourceFailure(message.isEmpty ? '光鸭云盘验证码初始化失败' : message);
    }
    final sent = await _post(
      '/v1/auth/verification',
      {
        'phone_number': phone,
        'target': 'ANY',
        'client_id': GuangyaBookClient.clientId,
      },
      extra: {'x-captcha-token': captcha},
    );
    final sentPayload = sent['data'] is Map
        ? Map<String, dynamic>.from(sent['data'] as Map)
        : sent;
    final verificationId =
        '${sentPayload['verification_id'] ?? sentPayload['verificationId'] ?? ''}';
    if (verificationId.isEmpty) {
      final message = '${sent['error_description'] ?? sent['message'] ?? ''}'
          .trim();
      throw CloudSourceFailure(message.isEmpty ? '光鸭云盘验证码发送失败' : message);
    }
    return (captcha: captcha, verificationId: verificationId, device: device);
  }

  Future<GuangyaSession> verifyCode({
    required String phone,
    required String code,
    required String verificationId,
    required String captcha,
    required String device,
  }) async {
    final verified = await _post('/v1/auth/verification/verify', {
      'verification_id': verificationId,
      'verification_code': code,
      'client_id': GuangyaBookClient.clientId,
    });
    final verifiedPayload = verified['data'] is Map
        ? Map<String, dynamic>.from(verified['data'] as Map)
        : verified;
    final verificationToken =
        '${verifiedPayload['verification_token'] ?? verifiedPayload['verificationToken'] ?? ''}';
    if (verificationToken.isEmpty) {
      final message =
          '${verified['error_description'] ?? verified['message'] ?? ''}'
              .trim();
      throw CloudSourceFailure(message.isEmpty ? '光鸭云盘验证码错误' : message);
    }
    final signed = await _post(
      '/v1/auth/signin',
      {
        'verification_code': code,
        'verification_token': verificationToken,
        'username': phone,
        'client_id': GuangyaBookClient.clientId,
      },
      extra: {'x-captcha-token': captcha},
    );
    final data = signed['data'] is Map
        ? Map<String, dynamic>.from(signed['data'] as Map)
        : signed;
    final access = '${data['access_token'] ?? data['accessToken'] ?? ''}';
    final refresh = '${data['refresh_token'] ?? data['refreshToken'] ?? ''}';
    if (access.isEmpty) {
      final message =
          '${signed['error_description'] ?? signed['message'] ?? ''}'.trim();
      throw CloudSourceFailure(message.isEmpty ? '光鸭云盘登录失败' : message);
    }
    return GuangyaSession(
      accessToken: access,
      refreshToken: refresh,
      deviceId: device,
    );
  }
}

int _asInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
