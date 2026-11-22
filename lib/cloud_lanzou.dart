part of 'cloud_sources.dart';

/// Blue Cloud (蓝奏云) account client.
///
/// The app never asks for a pasted file link: the browser login page stores
/// `phpdisk_info`, then this client reads the account folder tree with
/// `doupload.php` and resolves each file's short-lived download URL on demand.
class LanzouBookClient implements CloudBookClient {
  LanzouBookClient(this.config, {this.settings, CloudHttp? http})
    : http = http ?? CloudHttp() {
    config.validate();
  }
  final CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  static const _base = 'https://pc.woozooo.com';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
  String? _uid;
  String? _vei;

  @override
  String get root => '-1';
  @override
  Future<void> delete(CloudBookEntry entry) async {
    await _ready();
    final result = await _post('/doupload.php', {
      'task': '6',
      'file_id': entry.id,
    });
    if (result['zt'] == 1) return;
    final info = '${result['inf'] ?? result['info'] ?? ''}'.trim();
    throw CloudSourceFailure(info.isEmpty ? '蓝奏云没有确认删除结果，请到网页端核对' : info);
  }

  Map<String, String> _headers(Uri uri) => {
    'User-Agent': _ua,
    'Referer': '$_base/mydisk.php?item=files&action=index',
    'Accept': 'application/json, text/plain, */*',
    if (uri.host.endsWith('woozooo.com')) 'Cookie': config.cookie,
  };

  Future<String> _getText(Uri uri, {String? referer}) async {
    final res = await http.request(
      'GET',
      uri,
      headers: (u) => {..._headers(u), if (referer != null) 'Referer': referer},
      redirects: true,
    );
    final bytes = await http.bytes(res, limit: 8 * 1024 * 1024);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> form, {
    String? referer,
  }) async {
    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        if (_uid != null) 'uid': _uid!,
        if (_vei != null) 'vei': _vei!,
      },
    );
    final body = utf8.encode(Uri(queryParameters: form).query);
    final res = await http.request(
      'POST',
      uri,
      headers: (u) => {
        ..._headers(u),
        'Content-Type': 'application/x-www-form-urlencoded',
        if (referer != null) 'Referer': referer,
      },
      body: body,
      redirects: false,
    );
    final bytes = await http.bytes(res, limit: 8 * 1024 * 1024);
    final text = utf8.decode(bytes, allowMalformed: true);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const CloudSourceFailure('蓝奏云返回的数据格式有误');
    }
    final zt = decoded['zt'];
    if (zt is num && zt != 1 && zt != 2 && zt != 4) {
      final info = '${decoded['inf'] ?? decoded['info'] ?? ''}'.trim();
      if (info.contains('登录') || zt == 9) {
        throw const CloudSourceFailure(
          '蓝奏云登录已失效，请点账号重新登录',
          authentication: true,
        );
      }
      throw CloudSourceFailure(info.isEmpty ? '蓝奏云暂时无法完成请求' : info);
    }
    return decoded;
  }

  Future<void> _ready() async {
    if (_uid != null && _vei != null) return;
    final page = await _getText(
      Uri.parse('$_base/mydisk.php?item=files&action=index'),
    );
    final uid = RegExp(r"""uid=([^'"&;<>\s]+)""").firstMatch(page)?.group(1);
    var vei = RegExp(
      r"""vei\s*[:=]\s*['"]?([A-Za-z0-9]+)""",
    ).firstMatch(page)?.group(1);
    vei ??= RegExp(r"'vei'\s*:\s*'([^']+)'").firstMatch(page)?.group(1);
    if (uid == null || uid.isEmpty || vei == null || vei.isEmpty) {
      if (page.contains('acw_sc__v2') || page.contains('Just a moment')) {
        throw const CloudSourceFailure('蓝奏云触发了网页验证，请重新登录后再试');
      }
      throw const CloudSourceFailure('蓝奏云登录已失效，请重新登录账号', authentication: true);
    }
    _uid = uid;
    _vei = vei;
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    if (page > 1) return const CloudBookListing([]);
    await _ready();
    final folders = await _post('/doupload.php', {
      'task': '47',
      'folder_id': folder,
    });
    final folderRows = folders['text'];
    final entries = <CloudBookEntry>[];
    if (folderRows is List) {
      for (final row in folderRows) {
        if (row is! Map) continue;
        final id = '${row['fol_id'] ?? ''}';
        final name = _cleanName('${row['name'] ?? ''}');
        if (id.isEmpty || name.isEmpty) continue;
        entries.add(CloudBookEntry(id: id, name: name, folder: true));
      }
    }
    var total = 0;
    for (var pg = 1; pg <= 20 && total < 400; pg++) {
      final files = await _post('/doupload.php', {
        'task': '5',
        'folder_id': folder,
        'pg': '$pg',
      });
      final rows = files['text'];
      if (rows is! List || rows.isEmpty) break;
      for (final row in rows) {
        if (row is! Map) continue;
        final id = '${row['id'] ?? ''}';
        final name = _cleanName('${row['name_all'] ?? row['name'] ?? ''}');
        if (id.isEmpty || name.isEmpty || !supportsBookImport(name)) continue;
        final size = _size('${row['size'] ?? ''}');
        entries.add(
          CloudBookEntry(id: id, name: name, folder: false, size: size),
        );
        total++;
      }
      if (rows.length < 20) break;
    }
    entries.sort((a, b) {
      if (a.folder != b.folder) return a.folder ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return CloudBookListing(entries);
  }

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    await _ready();
    final shareInfo = await _post('/doupload.php', {
      'task': '22',
      'file_id': entry.id,
    });
    final info = shareInfo['info'];
    if (info is! Map) throw const CloudSourceFailure('蓝奏云没有返回文件信息');
    final fid = '${info['f_id'] ?? ''}';
    final host = '${info['is_newd'] ?? ''}';
    final pwd = '${info['pwd'] ?? ''}';
    if (fid.isEmpty || host.isEmpty) {
      throw const CloudSourceFailure('蓝奏云文件分享信息不完整');
    }
    if (pwd.isNotEmpty && '${info['onof'] ?? ''}' == '1') {
      throw const CloudSourceFailure('这个蓝奏文件带提取码，暂不支持在线读取');
    }
    final share = _shareUri(host, fid);
    final page = await _getText(share);
    if (page.contains('文件不存在') || page.contains('取消分享')) {
      throw const CloudSourceFailure('蓝奏云文件已失效，请刷新目录');
    }
    if (page.contains('pwdload') || page.contains('passwddiv')) {
      throw const CloudSourceFailure('这个蓝奏文件带提取码，暂不支持在线读取');
    }
    final iframe = RegExp(
      r'<iframe[^>]+src="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(page)?.group(1);
    final next = iframe == null
        ? share
        : share.resolve(iframe.replaceAll('&amp;', '&'));
    final nextPage = identical(next, share) ? page : await _getText(next);
    final fileId = RegExp(
      r"'/ajaxm\.php\?file=(\d+)'",
    ).firstMatch(nextPage)?.group(1);
    final form = _formParams(nextPage);
    if (fileId == null || form.isEmpty) {
      throw const CloudSourceFailure('蓝奏云下载参数解析失败，请刷新后重试');
    }
    final ajax = Uri.parse(
      '${next.origin}/ajaxm.php',
    ).replace(queryParameters: {'file': fileId});
    final body = utf8.encode(Uri(queryParameters: form).query);
    final res = await http.request(
      'POST',
      ajax,
      headers: (u) => {
        ..._headers(u),
        'Referer': next.toString(),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
      redirects: true,
    );
    final bytes = await http.bytes(res, limit: 2 * 1024 * 1024);
    final data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (data is! Map) throw const CloudSourceFailure('蓝奏云下载地址解析失败');
    final dom = '${data['dom'] ?? ''}';
    final url = '${data['url'] ?? ''}';
    if (dom.isEmpty || url.isEmpty) {
      throw const CloudSourceFailure('蓝奏云没有返回可用的下载地址');
    }
    final base = dom.startsWith('http') ? dom : 'https://$dom';
    return '$base/file/$url';
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int, int?)? onProgress,
  }) async {
    if (!entry.isBook) throw const CloudSourceFailure('请选择支持的电子书或文档');
    final link = await directLink(entry);
    if (link == null) throw const CloudSourceFailure('蓝奏云没有返回下载地址');
    final uri = Uri.parse(link);
    CloudHttp.validateUrl(uri);
    final res = await http.request(
      'GET',
      uri,
      headers: (u) => {..._headers(u), 'Accept': '*/*'},
      redirects: true,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  void cancel() => http.close();
  @override
  void close() => http.close();

  Uri _shareUri(String host, String fid) {
    final value = host.startsWith('http') ? host : 'https://$host';
    return Uri.parse('$value/$fid');
  }

  Map<String, String> _formParams(String html) {
    final match = RegExp(
      r'data\s*:\s*({[^}]+})',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    if (match == null) return {};
    final values = <String, String>{};
    for (final item in RegExp(
      r"'([^']+)'\s*:\s*(?:'([^']*)'|([^,}\s]+))",
    ).allMatches(match)) {
      var value = item.group(2) ?? item.group(3) ?? '';
      if (value.isNotEmpty && !RegExp(r'^\d+$').hasMatch(value)) {
        final variable = RegExp(
          "var\\s+${RegExp.escape(value)}\\s*=\\s*['\"]([^'\"]*)",
        ).firstMatch(html)?.group(1);
        if (variable != null) value = variable;
      }
      values[item.group(1)!] = value;
    }
    return values;
  }

  String _cleanName(String value) =>
      value.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&').trim();

  int _size(String value) {
    final match = RegExp(
      r'([0-9.]+)\s*([kmgt]?)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return 0;
    final number = double.tryParse(match.group(1)!) ?? 0;
    final unit = match.group(2)!.toUpperCase();
    final factor = switch (unit) {
      'T' => 1024 * 1024 * 1024 * 1024,
      'G' => 1024 * 1024 * 1024,
      'M' => 1024 * 1024,
      'K' => 1024,
      _ => 1,
    };
    return (number * factor).round();
  }
}
