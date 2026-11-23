part of 'cloud_sources.dart';

/// 百度网盘账号客户端：官网扫码/验证码登录后读取 BDUSS Cookie，
/// 直接用网页版的 /api/list 与 /api/download 接口浏览账号目录。
class BaiduBookClient implements CloudBookClient {
  BaiduBookClient(this.config, {CloudHttp? http}) : http = http ?? CloudHttp() {
    config.validate();
  }

  final CloudSourceConfig config;
  final CloudHttp http;
  static const _base = 'https://pan.baidu.com';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  @override
  String get root => '/';

  Map<String, String> _headers(Uri uri) => {
    'User-Agent': _ua,
    'Referer': 'https://pan.baidu.com/',
    'Accept': 'application/json, text/plain, */*',
    if (uri.host == 'pan.baidu.com' || uri.host.endsWith('.baidu.com'))
      'Cookie': config.cookie,
  };

  Future<Map<String, dynamic>> _json(
    String path, {
    Map<String, String> query = const {},
    String method = 'GET',
  }) async {
    final uri = Uri.parse(
      '$_base$path',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await http.request(method, uri, headers: _headers);
    final bytes = await http.bytes(res);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map<String, dynamic>) {
      throw const CloudSourceFailure('百度网盘返回的数据格式有误');
    }
    final errno = _baiduInt(decoded['errno']);
    if (errno != 0) {
      final message = '${decoded['errmsg'] ?? decoded['show_msg'] ?? ''}'
          .trim();
      if (errno == -6 || errno == 2 || errno == 110 || errno == 111) {
        throw const CloudSourceFailure(
          '百度网盘登录已失效，请重新登录官网账号',
          authentication: true,
        );
      }
      throw CloudSourceFailure(
        message.isEmpty ? '百度网盘暂时无法完成请求（$errno）' : message,
      );
    }
    return decoded;
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final data = await _json(
      '/api/list',
      query: {
        'dir': folder,
        'num': '100',
        'page': '$page',
        'order': 'name',
        'desc': '0',
        'clienttype': '0',
        'web': '1',
        'showempty': '0',
      },
    );
    final rows = data['list'];
    if (rows is! List) throw const CloudSourceFailure('百度网盘目录数据有误');
    final entries = <CloudBookEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _cleanBaiduName('${row['server_filename'] ?? ''}');
      final path = '${row['path'] ?? ''}'.trim();
      if (name.isEmpty || path.isEmpty) continue;
      final isFolder = _baiduInt(row['isdir']) == 1;
      final entry = CloudBookEntry(
        id: isFolder ? path : '${row['fs_id'] ?? ''}',
        name: name,
        folder: isFolder,
        size: _baiduInt(row['size']),
      );
      if (entry.folder || entry.isBook) entries.add(entry);
    }
    return CloudBookListing(
      entries,
      nextPage: rows.length >= 100 ? page + 1 : null,
    );
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

  Future<Map<String, String>> _downloadSignature() async {
    final data = await _json(
      '/api/gettemplatevariable',
      query: {
        'fields': '["sign1","sign3","timestamp"]',
        'clienttype': '0',
        'web': '1',
      },
    );
    final result = data['result'];
    if (result is! Map) {
      throw const CloudSourceFailure('百度网盘没有返回下载签名，请重新登录后再试');
    }
    final sign1 = '${result['sign1'] ?? ''}'.codeUnits;
    final sign3 = '${result['sign3'] ?? ''}'.codeUnits;
    final timestamp = '${result['timestamp'] ?? ''}';
    if (sign1.isEmpty || sign3.isEmpty || timestamp.isEmpty) {
      throw const CloudSourceFailure('百度网盘下载签名无效，请重新登录后再试');
    }
    final a = <int>[];
    for (var i = 0; i < 256; i++) {
      a.add(sign3[i % sign3.length]);
    }
    final p = List<int>.generate(256, (i) => i);
    var u = 0;
    for (var q = 0; q < 256; q++) {
      u = (u + p[q] + a[q]) & 255;
      final swap = p[q];
      p[q] = p[u];
      p[u] = swap;
    }
    final sign = Uint8List(sign1.length);
    u = 0;
    for (var q = 0; q < sign1.length; q++) {
      final i = (q + 1) & 255;
      final pi = p[i];
      u = (u + p[i]) & 255;
      final pu = p[u];
      p[i] = pu;
      p[u] = pi;
      sign[q] = sign1[q] ^ p[(pi + pu) & 255];
    }
    return {'sign': base64Encode(sign), 'timestamp': timestamp};
  }

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    final signature = await _downloadSignature();
    final data = await _json(
      '/api/download',
      query: {
        'fidlist': '[${entry.id}]',
        'type': 'dlink',
        'clienttype': '0',
        'web': '1',
        ...signature,
      },
    );
    final rows = data['dlink'];
    if (rows is! List ||
        rows.isEmpty ||
        rows.first is! Map ||
        '${rows.first['dlink'] ?? ''}'.trim().isEmpty) {
      throw const CloudSourceFailure('百度网盘没有返回下载地址，请重新登录后再试');
    }
    final url = '${rows.first['dlink']}'.trim();
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
    if (url == null) throw const CloudSourceFailure('百度网盘没有返回下载地址');
    final uri = Uri.parse(url);
    CloudHttp.validateUrl(uri);
    final res = await http.request(
      'GET',
      uri,
      headers: _headers,
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  Future<void> delete(CloudBookEntry entry) async {
    throw const CloudSourceFailure('百度网盘账号模式暂不支持删除文件，请到官网操作');
  }

  @override
  void cancel() => http.close();

  @override
  void close() => http.close();
}

String _cleanBaiduName(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

int _baiduInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
