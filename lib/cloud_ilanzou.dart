part of 'cloud_sources.dart';

/// 蓝奏云优享版账号客户端。
///
/// 官网登录后浏览器会写入 `appToken` Cookie；客户端把 Cookie 原样带上，
/// 再按官方 App 的 AES-ECB 时间戳签名访问 api.ilanzou.com，直接列出账号
/// 根目录与子目录，不需要用户粘贴任何文件直链。
class LanzouProBookClient implements CloudBookClient {
  LanzouProBookClient(this.config, {this.settings, CloudHttp? http})
    : http = http ?? CloudHttp();

  final CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  static const _base = 'https://api.ilanzou.com';
  static const _secret = 'lanZouY-disk-app';
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0';
  String? _deviceId;
  String? _userId;

  @override
  String get root => '0';

  String get _token {
    for (final part in config.cookie.split(';')) {
      final value = part.trim();
      if (value.startsWith('appToken=')) {
        return Uri.decodeComponent(value.substring('appToken='.length));
      }
    }
    return '';
  }

  String _stamp() => _hex(_aes('${DateTime.now().millisecondsSinceEpoch}'));

  Map<String, String> _common({bool proved = true}) => {
    'uuid': _deviceId ?? '',
    'devType': '6',
    'devCode': _deviceId ?? '',
    'devModel': 'chrome',
    'devVersion': '125',
    'appVersion': '',
    'timestamp': _stamp(),
    if (proved) 'appToken': _token,
    'extra': '2',
  };

  Future<void> _ready() async {
    final token = _token;
    if (token.isEmpty) {
      throw const CloudSourceFailure(
        '蓝奏云优享版登录已失效，请重新登录官网账号',
        authentication: true,
      );
    }
    if (_deviceId != null && _userId != null) return;
    _deviceId = config.deviceId.trim();
    if (_deviceId == null || _deviceId!.isEmpty) {
      try {
        final json = await _json('/unproved/getUuid', const {}, proved: false);
        final data = json['data'];
        final uuid =
            '${json['uuid'] ?? (data is Map ? data['uuid'] : '') ?? ''}'.trim();
        _deviceId = uuid.isNotEmpty ? uuid : _uuid();
      } catch (_) {
        _deviceId = _uuid();
      }
      if (settings != null && _deviceId!.isNotEmpty) {
        await settings!.save(
          CloudSourceKind.lanzouPro,
          config.copyWith(deviceId: _deviceId),
        );
      }
    }
    final account = await _json('/proved/user/account/map', const {});
    final map = account['map'];
    if (map is! Map) {
      throw const CloudSourceFailure(
        '蓝奏云优享版登录已失效，请重新登录官网账号',
        authentication: true,
      );
    }
    _userId = '${map['userId'] ?? ''}'.trim();
    if (_userId!.isEmpty) {
      throw const CloudSourceFailure('蓝奏云优享版没有返回账号信息，请重新登录');
    }
  }

  Future<Map<String, dynamic>> _json(
    String path,
    Map<String, String> query, {
    bool proved = true,
    String method = 'GET',
    Object? body,
  }) async {
    final params = <String, String>{..._common(proved: proved), ...query};
    final uri = Uri.parse('$_base$path').replace(queryParameters: params);
    final res = await http.request(
      method,
      uri,
      headers: (_) => {
        'User-Agent': _ua,
        'Referer': 'https://www.ilanzou.com/',
        'Origin': 'https://www.ilanzou.com',
        'Accept': 'application/json, text/plain, */*',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      },
      body: body == null ? null : utf8.encode(jsonEncode(body)),
    );
    final bytes = await http.bytes(res);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map<String, dynamic>) {
      throw const CloudSourceFailure('蓝奏云优享版返回的数据格式有误');
    }
    final code = decoded['code'];
    if (code != 200) {
      final message = '${decoded['msg'] ?? ''}'.trim();
      if (code == -1 || code == -2 || code == 401 || code == 403) {
        throw CloudSourceFailure(
          message.isEmpty ? '蓝奏云优享版登录已失效，请重新登录官网账号' : message,
          authentication: true,
        );
      }
      throw CloudSourceFailure(message.isEmpty ? '蓝奏云优享版暂时无法完成请求' : message);
    }
    return decoded;
  }

  @override
  Future<void> delete(CloudBookEntry entry) async {
    await _ready();
    await _json(
      '/proved/file/delete',
      const {},
      method: 'POST',
      body: {
        'folderIds': entry.folder ? entry.id : '',
        'fileIds': entry.folder ? '' : entry.id,
        'status': 0,
      },
    );
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    await _ready();
    final data = await _json('/proved/record/file/list', {
      'offset': '$page',
      'limit': '60',
      'folderId': folder,
      'type': '0',
    });
    final rows = data['list'];
    if (rows is! List) throw const CloudSourceFailure('蓝奏云优享版目录数据有误');
    final entries = <CloudBookEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      if ('${row['fileType'] ?? ''}' == '2') {
        final id = '${row['folderId'] ?? ''}';
        final name = _cleanCloudName('${row['folderName'] ?? ''}');
        if (id.isNotEmpty && name.isNotEmpty) {
          entries.add(CloudBookEntry(id: id, name: name, folder: true));
        }
      } else {
        final id = '${row['fileId'] ?? ''}';
        final name = _cleanCloudName('${row['fileName'] ?? ''}');
        if (id.isEmpty || name.isEmpty) continue;
        final size = _toInt(row['fileSize']) * 1024;
        final entry = CloudBookEntry(
          id: id,
          name: name,
          folder: false,
          size: size,
        );
        if (entry.isBook) entries.add(entry);
      }
    }
    entries.sort((a, b) {
      if (a.folder != b.folder) return a.folder ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    final totalPage = _toInt(data['totalPage']);
    return CloudBookListing(
      entries,
      nextPage: totalPage > page ? page + 1 : null,
    );
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    await _ready();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tsText = '$ts';
    final downloadId = _hex(_aes('${entry.id}|$_userId'));
    final auth = _hex(_aes('${entry.id}|$tsText'));
    final uri = Uri.parse('$_base/unproved/file/redirect').replace(
      queryParameters: {
        ..._common(proved: false),
        'timestamp': _hex(_aes(tsText)),
        'appToken': _token,
        'enable': '0',
        'downloadId': downloadId,
        'auth': auth,
      },
    );
    final res = await http.request(
      'GET',
      uri,
      headers: (_) => {
        'User-Agent': _ua,
        'Referer': 'https://www.ilanzou.com/',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      allowedStatuses: const {302},
    );
    final location = res.headers.value(HttpHeaders.locationHeader);
    await res.listen((_) {}).cancel();
    if (location == null || location.isEmpty) {
      throw const CloudSourceFailure('蓝奏云优享版没有返回下载地址，请重新登录后再试');
    }
    return uri.resolve(location).toString();
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = await directLink(entry);
    if (url == null) throw const CloudSourceFailure('蓝奏云优享版没有返回下载地址');
    final uri = Uri.parse(url);
    CloudHttp.validateUrl(uri);
    final res = await http.request(
      'GET',
      uri,
      headers: (_) => {'User-Agent': _ua},
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  void cancel() => http.close();

  @override
  void close() => http.close();
}

String _cleanCloudName(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

int _toInt(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> _aes(String plain) {
  final cipher = ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(utf8.encode(LanzouProBookClient._secret)));
  final input = utf8.encode(plain);
  final length = ((input.length + 16) ~/ 16) * 16;
  final padded = Uint8List(length);
  padded.setRange(0, input.length, input);
  final pad = length - input.length;
  for (var i = input.length; i < length; i++) {
    padded[i] = pad;
  }
  final output = Uint8List(length);
  for (var i = 0; i < length; i += 16) {
    cipher.processBlock(padded, i, output, i);
  }
  return output;
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
