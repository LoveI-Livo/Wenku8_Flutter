part of 'cloud_sources.dart';

/// 123 云盘账号客户端。
///
/// 用户在 www.123pan.com 官网登录后，网页会把 token 放进 localStorage；
/// 登录页读出后由本客户端解密，直接请求账号目录，不再要求用户粘贴直链。
class Pan123BookClient implements CloudBookClient {
  Pan123BookClient(this.config, {this.settings, CloudHttp? http})
    : http = http ?? CloudHttp() {
    config.validate();
  }

  CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  static const _api = 'https://www.123pan.com/b/api';
  static const _origin = 'https://www.123pan.com';
  String? _token;
  final Map<String, String> _nextTokens = {};

  @override
  String get root => '0';

  String get _accessToken {
    _token ??= _decodePan123Token(config.accessToken);
    if (_token!.isEmpty) {
      throw const CloudSourceFailure(
        '123 云盘登录已失效，请重新登录官网账号',
        authentication: true,
      );
    }
    return _token!;
  }

  Map<String, String> _headers() => {
    'origin': _origin,
    'referer': '$_origin/',
    'authorization': 'Bearer $_accessToken',
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36',
    'platform': 'web',
    'app-version': '3',
    if (config.deviceId.trim().isNotEmpty) 'loginUuid': config.deviceId.trim(),
  };

  Future<Map<String, dynamic>> _json(
    String path, {
    Map<String, String> query = const {},
    Object? body,
  }) async {
    final uri = Uri.parse(
      '$_api$path',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await http.request(
      body == null ? 'GET' : 'POST',
      uri,
      headers: (_) => {
        ..._headers(),
        'accept': 'application/json',
        if (body != null) 'content-type': 'application/json',
      },
      body: body == null ? null : utf8.encode(jsonEncode(body)),
    );
    final bytes = await http.bytes(res);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map<String, dynamic>) {
      throw const CloudSourceFailure('123 云盘返回的数据格式有误');
    }
    final code = _int(decoded['code']);
    if (code != 0 && code != 200) {
      final message = '${decoded['message'] ?? decoded['msg'] ?? ''}'.trim();
      if (code == 401 || code == 403 || message.contains('登录')) {
        throw const CloudSourceFailure(
          '123 云盘登录已失效，请重新登录官网账号',
          authentication: true,
        );
      }
      throw CloudSourceFailure(message.isEmpty ? '123 云盘暂时无法完成请求' : message);
    }
    return decoded;
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final nextToken = page <= 1 ? '0' : (_nextTokens[folder] ?? '');
    if (page > 1 && nextToken.isEmpty) {
      return const CloudBookListing([], nextPage: null);
    }
    final data = await _json(
      '/file/list/new',
      query: {
        'driveId': '0',
        'limit': '100',
        'next': nextToken,
        'orderBy': 'file_id',
        'orderDirection': 'desc',
        'parentFileId': folder,
        'trashed': 'false',
        'SearchData': '',
        'Page': '$page',
        'OnlyLookAbnormalFile': '0',
        'event': 'homeListFile',
        'operateType': '4',
        'inDirectSpace': 'false',
      },
    );
    final rows = data['data']?['InfoList'];
    if (rows is! List) throw const CloudSourceFailure('123 云盘目录数据有误');
    final entries = <CloudBookEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = '${row['FileId'] ?? ''}';
      final name = _clean123Name('${row['FileName'] ?? ''}');
      if (id.isEmpty || name.isEmpty) continue;
      final folderEntry = _int(row['Type']) == 1;
      final entry = CloudBookEntry(
        id: id,
        name: name,
        folder: folderEntry,
        size: _int(row['Size']),
        extra: {
          'etag': '${row['Etag'] ?? ''}',
          's3keyFlag': '${row['S3KeyFlag'] ?? ''}',
          'type': _int(row['Type']),
        },
      );
      if (entry.folder || entry.isBook) entries.add(entry);
    }
    final next = '${data['data']?['Next'] ?? '-1'}';
    if (next != '-1' && next.isNotEmpty) {
      _nextTokens[folder] = next;
    } else {
      _nextTokens.remove(folder);
    }
    return CloudBookListing(
      entries,
      nextPage: next != '-1' && next.isNotEmpty ? page + 1 : null,
    );
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    final data = await _json(
      '/file/download_info',
      body: {
        'driveId': 0,
        'etag': entry.extra['etag'] ?? '',
        'fileId': _int(entry.id),
        'fileName': entry.name,
        's3keyFlag': entry.extra['s3keyFlag'] ?? '',
        'size': entry.size,
        'type': entry.extra['type'] ?? 0,
      },
    );
    var url = '${data['data']?['DownloadUrl'] ?? ''}'.trim();
    if (url.isEmpty) {
      throw const CloudSourceFailure('123 云盘没有返回下载地址，请重新登录后再试');
    }
    CloudHttp.validateUrl(Uri.parse(url));
    // 123 的下载地址有时把真实地址放在 params 的 Base64 里。
    final params = Uri.parse(url).queryParameters['params'];
    if (params != null && params.isNotEmpty) {
      try {
        final decoded = utf8.decode(base64.decode(params));
        if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
          url = decoded;
          CloudHttp.validateUrl(Uri.parse(url));
        }
      } catch (_) {}
    }
    return url;
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int, int?)? onProgress,
  }) async {
    final url = await directLink(entry);
    if (url == null) throw const CloudSourceFailure('123 云盘没有返回下载地址');
    final uri = Uri.parse(url);
    CloudHttp.validateUrl(uri);
    final res = await http.request(
      'GET',
      uri,
      headers: (_) => {..._headers(), 'accept': '*/*'},
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  Future<void> delete(CloudBookEntry entry) async {
    await _json(
      '/file/trash',
      body: {
        'driveId': 0,
        'fileIds': [_int(entry.id)],
      },
    );
  }

  @override
  void cancel() => http.close();

  @override
  void close() => http.close();
}

String _clean123Name(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

int _int(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;

String _decodePan123Token(String raw) {
  var value = raw.trim();
  if (value.startsWith('{')) {
    try {
      final map = jsonDecode(value);
      if (map is Map) {
        value =
            '${map['token'] ?? map['accessToken'] ?? map['authorToken'] ?? ''}';
      }
    } catch (_) {}
  }
  if (value.startsWith('Bearer ')) value = value.substring(7);
  if (value.isEmpty || value.startsWith('eyJ')) return value;
  if (!RegExp(r'^[0-9a-fA-F]{32,}$').hasMatch(value)) return value;
  try {
    final key = utf8.encode('1234567890000000');
    final iv = utf8.encode('1234567890000000');
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final input = _hexBytes(value);
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += 16) {
      cipher.processBlock(input, offset, output, offset);
    }
    final end = output.length;
    final pad = output[end - 1];
    if (pad < 1 || pad > 16) return value;
    return utf8.decode(output.sublist(0, end - pad), allowMalformed: true);
  } catch (_) {
    return value;
  }
}

Uint8List _hexBytes(String value) {
  final out = Uint8List(value.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
