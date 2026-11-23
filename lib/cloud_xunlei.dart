part of 'cloud_sources.dart';

/// 迅雷云盘账号客户端。
///
/// 官网登录后 localStorage 里会写入 `credentials_<clientId>`，其中包含
/// access_token / refresh_token。这里直接按网页版 drive v1 接口列出账号
/// 目录，并在 token 过期时自动刷新。
class XunleiBookClient implements CloudBookClient {
  XunleiBookClient(this.config, {this.settings, CloudHttp? http})
    : http = http ?? CloudHttp() {
    config.validate();
  }

  CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  static const _api = 'https://api-pan.xunlei.com/drive/v1';
  static const _authApi = 'https://xluser-ssl.xunlei.com/v1';
  static const _webClientId = 'Xqp0kJBXWhwaTpB6';
  static const _webClientVersion = '1.0.0';
  String? _access;
  String? _refresh;
  String? _clientId;
  String? _clientSecret;
  String? _deviceId;
  String? _clientVersion;
  final Map<String, String> _pageTokens = {};

  @override
  String get root => '';

  void _loadCredential() {
    if (_access != null) return;
    var raw = config.accessToken.trim();
    if (raw.startsWith('{')) {
      try {
        final map = jsonDecode(raw);
        if (map is Map) {
          _access =
              '${map['access_token'] ?? map['accessToken'] ?? map['token'] ?? ''}';
          _refresh =
              '${map['refresh_token'] ?? map['refreshToken'] ?? config.refreshToken}';
          _clientId = '${map['client_id'] ?? map['clientId'] ?? _webClientId}';
          _clientSecret =
              '${map['client_secret'] ?? map['clientSecret'] ?? ''}';
          _deviceId =
              '${map['device_id'] ?? map['deviceId'] ?? config.deviceId}';
          _clientVersion =
              '${map['client_version'] ?? map['clientVersion'] ?? ''}';
        }
      } catch (_) {}
    }
    _access ??= raw;
    _refresh ??= config.refreshToken.trim();
    _clientId ??= _webClientId;
    _clientSecret ??= '';
    _deviceId ??= config.deviceId.trim();
    _clientVersion ??= '';
    if (_access!.isEmpty) {
      throw const CloudSourceFailure(
        '迅雷云盘登录已失效，请重新登录官网账号',
        authentication: true,
      );
    }
  }

  String get _client =>
      (_clientId == null || _clientId!.isEmpty) ? _webClientId : _clientId!;

  Map<String, String> _headers() => {
    'authorization': 'Bearer ${_access ?? ''}',
    'accept': 'application/json;charset=UTF-8',
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36',
    'x-client-id': _client,
    'x-client-version': (_clientVersion == null || _clientVersion!.isEmpty)
        ? _webClientVersion
        : _clientVersion!,
    'x-device-id': (_deviceId != null && _deviceId!.isNotEmpty)
        ? _deviceId!
        : md5.convert(utf8.encode(_access ?? '')).toString(),
  };

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, String> query = const {},
    Object? body,
    bool retry = true,
  }) async {
    _loadCredential();
    final uri = Uri.parse(
      '$_api$path',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await http.request(
      method,
      uri,
      headers: (_) => {
        ..._headers(),
        if (body != null) 'content-type': 'application/json',
      },
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      allowedStatuses: const {400},
    );
    final bytes = await http.bytes(res);
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      throw const CloudSourceFailure('迅雷云盘返回的数据格式有误');
    }
    final code = _xunleiInt(data['error_code'] ?? data['errorCode']);
    final message = '${data['error'] ?? data['error_description'] ?? ''}'
        .trim();
    if (res.statusCode == 401 ||
        res.statusCode == 403 ||
        {4122, 4121, 10, 16}.contains(code)) {
      if (!retry || !await _refreshToken()) {
        throw const CloudSourceFailure(
          '迅雷云盘登录已失效，请重新登录官网账号',
          authentication: true,
        );
      }
      return _request(
        path,
        method: method,
        query: query,
        body: body,
        retry: false,
      );
    }
    if (res.statusCode >= 400 || code != 0) {
      throw CloudSourceFailure(
        message.isEmpty ? '迅雷云盘暂时无法完成请求（$code）' : message,
        authentication: message.contains('token') || message.contains('登录'),
      );
    }
    return data;
  }

  Future<bool> _refreshToken() async {
    final token = _refresh?.trim() ?? '';
    if (token.isEmpty) return false;
    try {
      final res = await http.request(
        'POST',
        Uri.parse('$_authApi/auth/token'),
        headers: (_) => {
          'content-type': 'application/json',
          'user-agent': 'Mozilla/5.0',
        },
        body: utf8.encode(
          jsonEncode({
            'grant_type': 'refresh_token',
            'refresh_token': token,
            'client_id': _client,
            if ((_clientSecret ?? '').isNotEmpty)
              'client_secret': _clientSecret,
          }),
        ),
      );
      final decoded = jsonDecode(utf8.decode(await http.bytes(res)));
      if (decoded is! Map) return false;
      final access = '${decoded['access_token'] ?? ''}';
      final refresh = '${decoded['refresh_token'] ?? ''}';
      if (access.isEmpty) return false;
      _access = access;
      if (refresh.isNotEmpty) _refresh = refresh;
      await settings?.rotateTokens(
        config,
        accessToken: access,
        refreshToken: refresh.isEmpty ? null : refresh,
        driveId: config.driveId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final token = page <= 1 ? '' : (_pageTokens[folder] ?? '');
    final data = await _request(
      '/files',
      query: {
        if (config.driveId.trim().isNotEmpty) 'space': config.driveId.trim(),
        '__type': 'drive',
        'parent_id': folder,
        'page_token': token,
        'limit': '100',
        'filters':
            '{"phase":{"eq":"PHASE_TYPE_COMPLETE"},"trashed":{"eq":false}}',
      },
    );
    final rows = data['files'];
    if (rows is! List) throw const CloudSourceFailure('迅雷云盘目录数据有误');
    final entries = <CloudBookEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = '${row['id'] ?? ''}';
      final name = _cleanXunleiName('${row['name'] ?? ''}');
      if (id.isEmpty || name.isEmpty) continue;
      final folderEntry = '${row['kind'] ?? ''}' == 'drive#folder';
      final entry = CloudBookEntry(
        id: id,
        name: name,
        folder: folderEntry,
        size: _xunleiInt(row['size']),
        extra: {'kind': '${row['kind'] ?? ''}'},
      );
      if (entry.folder || entry.isBook) entries.add(entry);
    }
    final next = '${data['next_page_token'] ?? ''}';
    if (next.isNotEmpty) _pageTokens[folder] = next;
    return CloudBookListing(entries, nextPage: next.isEmpty ? null : page + 1);
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    final data = await _request(
      '/files/${Uri.encodeComponent(entry.id)}',
      query: {
        if (config.driveId.trim().isNotEmpty) 'space': config.driveId.trim(),
      },
    );
    var url = '${data['web_content_link'] ?? ''}'.trim();
    if (url.isEmpty) {
      final medias = data['medias'];
      if (medias is List) {
        for (final media in medias) {
          if (media is Map && media['link'] is Map) {
            final candidate = '${media['link']['url'] ?? ''}'.trim();
            if (candidate.isNotEmpty) {
              url = candidate;
              break;
            }
          }
        }
      }
    }
    if (url.isEmpty) {
      throw const CloudSourceFailure('迅雷云盘没有返回下载地址，请重新登录后再试');
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
    if (url == null) throw const CloudSourceFailure('迅雷云盘没有返回下载地址');
    final uri = Uri.parse(url);
    CloudHttp.validateUrl(uri);
    final res = await http.request(
      'GET',
      uri,
      headers: (_) => {
        'referer': 'https://pan.xunlei.com/',
        'user-agent':
            'Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC Build/SP1A.210812.016)',
      },
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  Future<void> delete(CloudBookEntry entry) async {
    await _request(
      '/files/${Uri.encodeComponent(entry.id)}/trash',
      method: 'PATCH',
      query: {
        if (config.driveId.trim().isNotEmpty) 'space': config.driveId.trim(),
      },
      body: const <String, Object?>{},
    );
  }

  @override
  void cancel() => http.close();

  @override
  void close() => http.close();
}

String _cleanXunleiName(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

int _xunleiInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
