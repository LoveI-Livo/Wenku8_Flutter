part of 'cloud_sources.dart';

/// 阿里云盘账号客户端。
///
/// 官网登录页把 access_token / refresh_token 存在 localStorage 的 `token`
/// 对象里；登录页读出后保存到本机。这里按网页版接口浏览账号目录，并在
/// token 过期时用 refresh_token 自动续期。
class AliyunBookClient implements CloudBookClient {
  AliyunBookClient(this.config, {this.settings, CloudHttp? http})
    : http = http ?? CloudHttp() {
    config.validate();
  }

  CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  static const _api = 'https://api.aliyundrive.com';
  String? _access;
  String? _refresh;
  String? _drive;
  final Map<String, String> _markers = {};

  @override
  String get root => 'root';

  void _loadToken() {
    if (_access != null) return;
    var raw = config.accessToken.trim();
    if (raw.startsWith('{')) {
      try {
        final map = jsonDecode(raw);
        if (map is Map) {
          raw = '${map['access_token'] ?? map['accessToken'] ?? ''}';
          _refresh =
              '${map['refresh_token'] ?? map['refreshToken'] ?? config.refreshToken}';
          _drive =
              '${map['default_drive_id'] ?? map['drive_id'] ?? config.driveId}';
        }
      } catch (_) {}
    }
    _access = raw;
    _refresh ??= config.refreshToken.trim();
    _drive ??= config.driveId.trim();
    if (_access!.isEmpty) {
      throw const CloudSourceFailure(
        '阿里云盘登录已失效，请重新登录官网账号',
        authentication: true,
      );
    }
  }

  Map<String, String> _headers() => {
    'authorization': 'Bearer ${_access ?? ''}',
    'content-type': 'application/json',
    'origin': 'https://www.alipan.com',
    'referer': 'https://www.alipan.com/',
    'x-canary': 'client=web,app=adrive,version=v6.8.12',
    if (config.deviceId.trim().isNotEmpty)
      'x-device-id': config.deviceId.trim(),
  };

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, Object?> body = const {},
    bool retry = true,
  }) async {
    _loadToken();
    final uri = Uri.parse('$_api$path');
    final res = await http.request(
      'POST',
      uri,
      headers: (_) => {..._headers(), 'accept': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
    );
    final bytes = await http.bytes(res);
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) {
        throw const CloudSourceFailure('阿里云盘返回的数据格式有误');
      }
      data = decoded;
    } catch (error) {
      if (error is CloudSourceFailure) rethrow;
      throw const CloudSourceFailure('阿里云盘返回的数据格式有误');
    }
    final code = '${data['code'] ?? ''}'.trim();
    if (res.statusCode == 401 ||
        code == 'AccessTokenInvalid' ||
        code == 'InvalidParameter.RefreshToken') {
      if (!retry || !await _refreshToken()) {
        throw const CloudSourceFailure(
          '阿里云盘登录已失效，请重新登录官网账号',
          authentication: true,
        );
      }
      return _post(path, body: body, retry: false);
    }
    if (res.statusCode >= 400 || (code.isNotEmpty && code != '200')) {
      throw CloudSourceFailure(
        '${data['message'] ?? data['error_description'] ?? '阿里云盘暂时无法完成请求'}',
        authentication: code.contains('Token'),
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
        Uri.parse('$_api/token/refresh'),
        headers: (_) => {
          'content-type': 'application/json',
          'origin': 'https://www.alipan.com',
          'referer': 'https://www.alipan.com/',
        },
        body: utf8.encode(jsonEncode({'refresh_token': token})),
      );
      final data = jsonDecode(utf8.decode(await http.bytes(res)));
      if (data is! Map) return false;
      final access = '${data['access_token'] ?? ''}';
      final refresh = '${data['refresh_token'] ?? ''}';
      if (access.isEmpty) return false;
      _access = access;
      if (refresh.isNotEmpty) _refresh = refresh;
      final drive = '${data['default_drive_id'] ?? _drive ?? ''}';
      if (drive.isNotEmpty) _drive = drive;
      await settings?.rotateTokens(
        config,
        accessToken: access,
        refreshToken: refresh.isEmpty ? null : refresh,
        driveId: drive.isEmpty ? null : drive,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _driveId() async {
    _loadToken();
    if (_drive != null && _drive!.isNotEmpty) return _drive!;
    final data = await _post('/v2/user/get', body: const {});
    final drive =
        '${data['default_drive_id'] ?? data['resource_drive_id'] ?? ''}';
    if (drive.isEmpty) {
      throw const CloudSourceFailure('阿里云盘没有返回默认空间，请重新登录');
    }
    _drive = drive;
    await settings?.rotateTokens(config, driveId: drive);
    return drive;
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final marker = page <= 1 ? '' : (_markers[folder] ?? '');
    if (page > 1 && marker.isEmpty) {
      return const CloudBookListing([], nextPage: null);
    }
    final drive = await _driveId();
    final data = await _post(
      '/adrive/v3/file/list',
      body: {
        'drive_id': drive,
        'parent_file_id': folder,
        'limit': 100,
        'order_by': 'name',
        'order_direction': 'ASC',
        'fields': '*',
        if (marker.isNotEmpty) 'marker': marker,
      },
    );
    final rows = data['items'];
    if (rows is! List) throw const CloudSourceFailure('阿里云盘目录数据有误');
    final entries = <CloudBookEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = '${row['file_id'] ?? ''}';
      final name = _cleanAliyunName('${row['name'] ?? ''}');
      if (id.isEmpty || name.isEmpty) continue;
      final isFolder = '${row['type'] ?? ''}' == 'folder';
      final entry = CloudBookEntry(
        id: id,
        name: name,
        folder: isFolder,
        size: _aliyunInt(row['size']),
        extra: {'category': '${row['category'] ?? ''}'},
      );
      if (entry.folder || entry.isBook) entries.add(entry);
    }
    final nextMarker = '${data['next_marker'] ?? ''}';
    if (nextMarker.isNotEmpty) {
      _markers[folder] = nextMarker;
    } else {
      _markers.remove(folder);
    }
    return CloudBookListing(
      entries,
      nextPage: nextMarker.isNotEmpty ? page + 1 : null,
    );
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    final drive = await _driveId();
    final data = await _post(
      '/v2/file/get_download_url',
      body: {'drive_id': drive, 'file_id': entry.id, 'expire_sec': 14400},
    );
    final url = '${data['url'] ?? ''}'.trim();
    if (url.isEmpty) {
      throw const CloudSourceFailure('阿里云盘没有返回下载地址，请重新登录后再试');
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
    if (url == null) throw const CloudSourceFailure('阿里云盘没有返回下载地址');
    final uri = Uri.parse(url);
    CloudHttp.validateUrl(uri);
    final res = await http.request(
      'GET',
      uri,
      headers: (_) => {
        'referer': 'https://www.alipan.com/',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36',
      },
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  Future<void> delete(CloudBookEntry entry) async {
    final drive = await _driveId();
    await _post(
      '/v2/recyclebin/trash',
      body: {'drive_id': drive, 'file_id': entry.id},
    );
  }

  @override
  void cancel() => http.close();

  @override
  void close() => http.close();
}

String _cleanAliyunName(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

int _aliyunInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
