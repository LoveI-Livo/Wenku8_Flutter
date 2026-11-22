import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'package:crypto/crypto.dart';
import 'book_import_limits.dart';
part 'cloud_s3.dart';
part 'cloud_lanzou.dart';

enum CloudSourceKind {
  webdav('OpenList / WebDAV'),
  quark('夸克网盘'),
  lanzou('蓝奏云 · 普通版'),
  lanzouPro('蓝奏云 · 优享版'),
  xunlei('迅雷云盘'),
  aliyun('阿里云盘'),
  baidu('百度网盘'),
  pan123('123 云盘'),
  uc('UC 网盘'),
  direct('其他网盘直链'),
  rss('其他书源 · RSS/Atom'),
  s3('S3 / 兼容对象存储');

  const CloudSourceKind(this.label);
  final String label;

  /// 这些来源都通过「文件下载直链」流式读取，不保存账号 Cookie。
  bool get isDirectLink => switch (this) {
    lanzouPro ||
    xunlei ||
    aliyun ||
    baidu ||
    pan123 ||
    uc ||
    direct ||
    rss => true,
    _ => false,
  };

  /// Sources that expose a logged-in folder tree instead of a pasted link.
  bool get isAccount => switch (this) {
    quark || lanzou || webdav || s3 => true,
    _ => false,
  };

  /// Sources whose login is performed on the provider's own website.
  bool get isWebLogin => switch (this) {
    quark || lanzou => true,
    _ => false,
  };
}

/// Only this device's encrypted vault contains connection secrets. This record
/// is deliberately separate from SharedPreferences and LibraryBackup.
class CloudSourceConfig {
  const CloudSourceConfig({
    required this.kind,
    this.address = '',
    this.username = '',
    this.password = '',
    this.cookie = '',
    this.allowHttp = false,
    this.bucket = '',
    this.region = 'us-east-1',
    this.prefix = '',
    this.sessionToken = '',
    this.pathStyle = true,
  });
  final CloudSourceKind kind;
  final String address, username, password, cookie;
  final bool allowHttp;
  final String bucket, region, prefix, sessionToken;
  final bool pathStyle;
  String get label => kind.label;
  Uri get endpoint {
    final uri = Uri.parse(address.trim());
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  void validate() {
    if (kind.isDirectLink) {
      final uri = Uri.tryParse(address.trim());
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp)) ||
          address.length > 4096) {
        throw CloudSourceFailure('请填写${kind.label}的 HTTPS 文件下载直链');
      }
      return;
    }
    if (kind == CloudSourceKind.lanzou) {
      final legacy = cookie.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (cookie.trim().isEmpty ||
              cookie.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(cookie) ||
              !RegExp(r'(?:^|;\s*)phpdisk_info=[^;]+').hasMatch(cookie))) {
        throw const CloudSourceFailure('请先登录蓝奏云账号，Cookie 需要包含 phpdisk_info');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('蓝奏云登录已失效，请重新登录账号');
        }
      }
      return;
    }
    if (kind == CloudSourceKind.webdav || kind == CloudSourceKind.s3) {
      final uri = Uri.tryParse(address.trim());
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp)) ||
          address.length > 2048) {
        throw CloudSourceFailure(
          kind == CloudSourceKind.s3
              ? '请填写完整的 HTTPS S3 Endpoint，不要包含桶名、查询参数或登录信息'
              : '请填写完整的 HTTPS WebDAV 地址，例如 https://你的域名/dav/',
        );
      }
      if (kind == CloudSourceKind.s3 &&
          (!RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$').hasMatch(bucket) ||
              !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(region) ||
              username.trim().isEmpty ||
              password.isEmpty ||
              RegExp(r'[\r\n\x00]').hasMatch(sessionToken + prefix) ||
              sessionToken.length > 16384 ||
              prefix.length > 1024)) {
        throw const CloudSourceFailure(
          '请检查存储桶、区域、Access Key ID 和 Secret Access Key',
        );
      }
      if (username.contains(':') ||
          RegExp(r'[\r\n\x00]').hasMatch(username + password) ||
          password.length > 8192) {
        throw CloudSourceFailure(
          kind == CloudSourceKind.s3
              ? '请检查 Access Key ID 和 Secret Access Key'
              : '请检查 WebDAV 用户名和密码',
        );
      }
    } else if (cookie.trim().isEmpty ||
        cookie.length > 16384 ||
        RegExp(r'[\r\n\x00]').hasMatch(cookie) ||
        !RegExp(r'(?:^|;\s*)__puus=[^;]+').hasMatch(cookie)) {
      throw const CloudSourceFailure('请粘贴本人夸克网页的完整 Cookie，需要包含 __puus');
    }
  }

  Map<String, Object> toRecord() => {
    'kind': kind.name,
    'address': address.trim(),
    'username': username,
    'password': password,
    'cookie': cookie,
    'allowHttp': allowHttp,
    if (kind == CloudSourceKind.s3) ...{
      'bucket': bucket,
      'region': region,
      'prefix': prefix,
      'sessionToken': sessionToken,
      'pathStyle': pathStyle,
    },
  };
  factory CloudSourceConfig.fromRecord(Map<String, dynamic> record) {
    final value = CloudSourceConfig(
      kind: CloudSourceKind.values.byName(record['kind']),
      address: record['address'] ?? '',
      username: record['username'] ?? '',
      password: record['password'] ?? '',
      cookie: record['cookie'] ?? '',
      allowHttp: record['allowHttp'] == true,
      bucket: record['bucket'] ?? '',
      region: record['region'] ?? 'us-east-1',
      prefix: record['prefix'] ?? '',
      sessionToken: record['sessionToken'] ?? '',
      pathStyle: record['pathStyle'] != false,
    );
    value.validate();
    return value;
  }
  CloudSourceConfig withCookie(String value) =>
      CloudSourceConfig(kind: kind, cookie: value);
}

abstract interface class CloudConfigStorage {
  Future<String?> read();
  Future<void> write(String? value);
}

class AndroidCloudConfigStorage implements CloudConfigStorage {
  static const channel = MethodChannel('org.mewx.wenku8/cloud_sources');
  @override
  Future<String?> read() => channel.invokeMethod<String>('read');
  @override
  Future<void> write(String? value) =>
      channel.invokeMethod<void>('write', value);
}

class CloudSourceSettings extends ChangeNotifier {
  CloudSourceSettings({CloudConfigStorage? storage})
    : storage = storage ?? AndroidCloudConfigStorage();
  final CloudConfigStorage storage;
  final Map<CloudSourceKind, CloudSourceConfig> _configs = {};
  S3SyncConnection? _s3Sync;
  S3SyncConnection? get s3Sync => _s3Sync;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  String? error;
  CloudSourceConfig? operator [](CloudSourceKind kind) => _configs[kind];
  Iterable<CloudSourceConfig> get configs => List.unmodifiable(_configs.values);
  Future<void> load() async {
    try {
      final text = await storage.read();
      final values = text == null ? <dynamic>[] : jsonDecode(text);
      if (values is! List ||
          values.length > CloudSourceKind.values.length + 1) {
        throw const FormatException();
      }
      final loaded = <CloudSourceKind, CloudSourceConfig>{};
      S3SyncConnection? sync;
      for (final value in values) {
        if (value is Map && value['purpose'] == 'book-sync') {
          if (sync != null) throw const FormatException();
          sync = S3SyncConnection.fromRecord(Map<String, dynamic>.from(value));
          continue;
        }
        final config = CloudSourceConfig.fromRecord(
          Map<String, dynamic>.from(value),
        );
        loaded[config.kind] = config;
      }
      _configs
        ..clear()
        ..addAll(loaded);
      _s3Sync = sync;
      error = null;
    } catch (_) {
      error = '无法读取本机网盘连接，请重新保存连接';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> save(CloudSourceKind kind, CloudSourceConfig? value) =>
      _save(kind, value);
  Future<void> _save(
    CloudSourceKind kind,
    CloudSourceConfig? value, {
    String? expectedCookie,
  }) {
    value?.validate();
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (expectedCookie != null && _configs[kind]?.cookie != expectedCookie) {
        return;
      }
      final next = {..._configs};
      if (value == null) {
        next.remove(kind);
      } else {
        next[kind] = value;
      }
      await _writeRecords(next, _s3Sync);
      _configs
        ..clear()
        ..addAll(next);
      error = null;
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    return work;
  }

  Future<void> _writeRecords(
    Map<CloudSourceKind, CloudSourceConfig> configs,
    S3SyncConnection? sync,
  ) => storage.write(
    configs.isEmpty && sync == null
        ? null
        : jsonEncode([
            ...configs.values.map((c) => c.toRecord()),
            if (sync != null) sync.toRecord(),
          ]),
  );

  /// Sync is a separate, explicitly saved connection. Editing or removing an
  /// import source never silently changes the destination receiving books.
  Future<void> saveS3Sync(S3SyncConnection? value) {
    value?.validate();
    final work = _writes.catchError((Object _) {}).then((_) async {
      await _writeRecords(_configs, value);
      _s3Sync = value;
      error = null;
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    return work;
  }

  /// A late response from an old client must not restore a removed account.
  Future<void> rotate(CloudSourceConfig previous, String cookie) => _save(
    previous.kind,
    previous.withCookie(cookie),
    expectedCookie: previous.cookie,
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CloudSourceFailure implements Exception {
  const CloudSourceFailure(this.message, {this.authentication = false});
  final String message;
  final bool authentication;
  @override
  String toString() => message;
}

class CloudTransferCancelled implements Exception {
  const CloudTransferCancelled();
}

String cloudFailureMessage(Object failure) => switch (failure) {
  CloudSourceFailure e => e.message,
  CloudTransferCancelled _ => '已取消，已导入的书籍仍保留',
  TimeoutException _ => '连接超时，请检查网络后重试',
  HandshakeException _ => '证书验证失败，请检查服务端 HTTPS 配置',
  SocketException _ => '无法连接网盘，请检查地址和网络',
  FormatException e => e.message.isEmpty ? '网盘返回的数据格式有误' : e.message,
  PlatformException e
      when e.code == 'document' || e.code == 'picker' || e.code == 'busy' =>
    e.message ?? '文件操作失败，请重新选择原书',
  FileSystemException e =>
    e.osError?.errorCode == 28 ? '存储空间不足，请清理空间后重新导入' : '无法读取或保存原书，请检查文件与存储空间',
  _ => '操作未完成，请重试；本地书籍已保留',
};

class CloudBookEntry {
  const CloudBookEntry({
    required this.id,
    required this.name,
    required this.folder,
    this.size = 0,
    this.author = '',
  });
  final String id, name;
  final bool folder;
  final int size;
  final String author;
  bool get isBook => !folder && supportsBookImport(name);
}

class CloudBookListing {
  const CloudBookListing(this.entries, {this.nextPage});
  final List<CloudBookEntry> entries;
  final int? nextPage;
}

abstract class CloudBookClient {
  factory CloudBookClient(
    CloudSourceConfig config, {
    CloudSourceSettings? settings,
  }) => switch (config.kind) {
    CloudSourceKind.webdav => WebDavBookClient(config),
    CloudSourceKind.quark => QuarkBookClient(config, settings: settings),
    CloudSourceKind.lanzou =>
      config.cookie.trim().isEmpty
          ? DirectLinkBookClient(config)
          : LanzouBookClient(config, settings: settings),
    CloudSourceKind.lanzouPro ||
    CloudSourceKind.xunlei ||
    CloudSourceKind.aliyun ||
    CloudSourceKind.baidu ||
    CloudSourceKind.pan123 ||
    CloudSourceKind.uc ||
    CloudSourceKind.rss => RssBookClient(config),
    CloudSourceKind.direct => DirectLinkBookClient(config),
    CloudSourceKind.s3 => S3BookClient(config),
  };
  String get root;
  Future<CloudBookListing> list(String folder, {int page = 1});

  /// A URL that the in-memory reader can fetch. Most clients store the URL
  /// itself as the entry id; account clients resolve a fresh signed URL.
  Future<String?> directLink(CloudBookEntry entry) async => entry.id;
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int received, int? total)? onProgress,
  });
  void cancel();
  void close();
}

/// A bounded, cancellable request. Redirects are followed explicitly so DAV
/// Basic authentication and Quark sessions never leak to unrelated origins.
class CloudHttp {
  CloudHttp({HttpClient Function()? clientFactory})
    : _factory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _factory;
  HttpClient? _client;
  bool _closed = false;
  static const maxBookBytes = maxLocalEpubBytes;
  static bool sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
  static void validateUrl(Uri uri, {bool allowHttp = false}) {
    if ((uri.scheme != 'https' && !(allowHttp && uri.scheme == 'http')) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const CloudSourceFailure('网盘返回了不安全的文件地址');
    }
  }

  Future<HttpClientResponse> request(
    String method,
    Uri uri, {
    required Map<String, String> Function(Uri) headers,
    List<int>? body,
    File? bodyFile,
    bool redirects = false,
    bool allowHttp = false,
    String? redirectMessage,
    Set<int> allowedStatuses = const {},
    String? authenticationMessage,
  }) async {
    if (_closed) throw const CloudTransferCancelled();
    validateUrl(uri, allowHttp: allowHttp);
    _client ??= _factory()..connectionTimeout = const Duration(seconds: 20);
    final client = _client!;
    try {
      for (var hop = 0; hop < 6; hop++) {
        final req = await client
            .openUrl(method, uri)
            .timeout(const Duration(seconds: 20));
        req.followRedirects = false;
        headers(uri).forEach(req.headers.set);
        if (bodyFile != null) {
          req.contentLength = await bodyFile.length();
          await req
              .addStream(bodyFile.openRead())
              .timeout(const Duration(minutes: 10));
        } else if (body != null) {
          req.contentLength = body.length;
          req.add(body);
        }
        final res = await req.close().timeout(const Duration(seconds: 25));
        if ({301, 302, 303, 307, 308}.contains(res.statusCode)) {
          final location = res.headers.value(HttpHeaders.locationHeader);
          await res.listen((_) {}).cancel();
          if (!redirects || location == null) {
            throw CloudSourceFailure(
              redirectMessage ?? '网盘地址发生跳转，请填写最终 WebDAV 地址或启用 OpenList 代理',
            );
          }
          final next = uri.resolve(location);
          // HTTPS may never be downgraded, even when a LAN HTTP endpoint was allowed.
          validateUrl(next, allowHttp: allowHttp && uri.scheme == 'http');
          uri = next;
          continue;
        }
        if ((res.statusCode < 200 || res.statusCode >= 300) &&
            !allowedStatuses.contains(res.statusCode)) {
          await res.listen((_) {}).cancel();
          if (res.statusCode == 401 || res.statusCode == 403) {
            throw CloudSourceFailure(
              authenticationMessage ?? '连接凭据已失效或没有读取权限，请重新配置连接',
              authentication: true,
            );
          }
          if (res.statusCode == 404) {
            throw const CloudSourceFailure('文件或目录不存在，请刷新后重试');
          }
          if (res.statusCode == 429) {
            throw const CloudSourceFailure('请求过于频繁，请稍后重试');
          }
          throw CloudSourceFailure('网盘请求失败（HTTP ${res.statusCode}）');
        }
        return res;
      }
      throw const CloudSourceFailure('文件跳转次数过多，请检查服务端代理设置');
    } catch (_) {
      if (_closed) throw const CloudTransferCancelled();
      rethrow;
    }
  }

  Future<Uint8List> bytes(
    HttpClientResponse res, {
    int limit = 4 * 1024 * 1024,
  }) async {
    if (res.contentLength > limit) {
      await res.listen((_) {}).cancel();
      throw const CloudSourceFailure('网盘返回的数据过大');
    }
    final result = BytesBuilder(copy: false);
    try {
      await for (final part in res.timeout(const Duration(seconds: 25))) {
        if (_closed) throw const CloudTransferCancelled();
        if (result.length + part.length > limit) {
          throw const CloudSourceFailure('网盘返回的数据过大');
        }
        result.add(part);
      }
    } catch (_) {
      if (_closed) throw const CloudTransferCancelled();
      rethrow;
    }
    return result.takeBytes();
  }

  Future<void> save(
    HttpClientResponse res,
    File target, {
    String? bookName,
    int? limitBytes,
    String? limitMessage,
    void Function(int, int?)? onProgress,
  }) async {
    final importingHtml =
        bookName != null &&
        RegExp(r'\.(html?|xhtml)$', caseSensitive: false).hasMatch(bookName);
    if (!importingHtml &&
        (res.headers.contentType?.mimeType == 'text/html' ||
            res.headers.contentType?.mimeType == 'application/xhtml+xml')) {
      await res.listen((_) {}).cancel();
      throw const CloudSourceFailure('网盘返回了登录网页，请更新连接或开启 OpenList 下载代理');
    }
    final total = res.contentLength < 0 ? null : res.contentLength;
    final limit =
        limitBytes ??
        (bookName == null ? maxBookBytes : localBookByteLimit(bookName));
    final sizeMessage =
        limitMessage ??
        (bookName == null
            ? '单本书籍不能超过 256 MiB'
            : localBookSizeMessage(bookName));
    if ((total ?? 0) > limit) {
      await res.listen((_) {}).cancel();
      throw CloudSourceFailure(sizeMessage);
    }
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final part in res.timeout(const Duration(seconds: 25))) {
        if (_closed) throw const CloudTransferCancelled();
        received += part.length;
        if (received > limit) {
          throw CloudSourceFailure(sizeMessage);
        }
        sink.add(part);
        await sink.flush();
        onProgress?.call(received, total);
      }
      if (received == 0 || (total != null && received != total)) {
        throw const CloudSourceFailure('书籍下载不完整，请重试');
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      if (_closed) throw const CloudTransferCancelled();
      rethrow;
    }
  }

  void close() {
    _closed = true;
    _client?.close(force: true);
  }
}

class WebDavBookClient implements CloudBookClient {
  WebDavBookClient(this.config, {CloudHttp? http})
    : http = http ?? CloudHttp() {
    config.validate();
  }
  final CloudSourceConfig config;
  final CloudHttp http;
  @override
  String get root => config.endpoint.toString();
  @override
  Future<String?> directLink(CloudBookEntry entry) async => entry.id;
  Uri _resource(String id) {
    final uri = Uri.parse(id).normalizePath(),
        base = config.endpoint.normalizePath();
    final segments = uri.pathSegments,
        prefix = base.pathSegments.where((e) => e.isNotEmpty).toList();
    if (!CloudHttp.sameOrigin(uri, base) ||
        uri.hasQuery ||
        uri.hasFragment ||
        segments.any(
          (s) => s == '..' || s == '.' || s.contains('/') || s.contains('\\'),
        ) ||
        segments.length < prefix.length ||
        !listEquals(segments.take(prefix.length).toList(), prefix)) {
      throw const CloudSourceFailure('文件地址不在已配置的 WebDAV 目录内');
    }
    return uri;
  }

  Map<String, String> _headers(Uri uri) => {
    'User-Agent': 'Wenku8/0.3 WebDAV',
    if (CloudHttp.sameOrigin(uri, config.endpoint) &&
        (config.username.isNotEmpty || config.password.isNotEmpty))
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
  };
  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final uri = _resource(folder);
    final res = await http.request(
      'PROPFIND',
      uri,
      allowHttp: config.allowHttp,
      headers: (u) => {
        ..._headers(u),
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>',
      ),
    );
    final document = XmlDocument.parse(utf8.decode(await http.bytes(res)));
    if (document.rootElement.name.local != 'multistatus') {
      throw const CloudSourceFailure('该地址不是 WebDAV 服务，请检查 /dav/ 路径');
    }
    final entries = <CloudBookEntry>[];
    final seen = <String>{};
    for (final node in document.rootElement.childElements.where(
      (e) => e.name.local == 'response',
    )) {
      final href = node.childElements
          .where((e) => e.name.local == 'href')
          .firstOrNull
          ?.innerText;
      if (href == null) continue;
      Uri candidate;
      try {
        candidate = _resource(uri.resolve(href).toString());
      } on CloudSourceFailure {
        continue;
      }
      final parent = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final parts = candidate.pathSegments.where((s) => s.isNotEmpty).toList();
      if (parts.length != parent.length + 1 ||
          !listEquals(parent, parts.take(parent.length).toList()) ||
          !seen.add(candidate.toString())) {
        continue;
      }
      XmlElement? props;
      for (final stat in node.childElements.where(
        (e) => e.name.local == 'propstat',
      )) {
        if (stat.childElements.any(
          (e) =>
              e.name.local == 'status' &&
              RegExp(r'\s200\s').hasMatch(e.innerText),
        )) {
          props = stat.childElements
              .where((e) => e.name.local == 'prop')
              .firstOrNull;
          break;
        }
      }
      if (props == null) continue;
      String? prop(String name) => props!.childElements
          .where((e) => e.name.local == name)
          .firstOrNull
          ?.innerText;
      final directory = props.descendants.whereType<XmlElement>().any(
        (e) => e.name.local == 'collection',
      );
      final entry = CloudBookEntry(
        id: candidate.toString(),
        name: prop('displayname')?.trim().isNotEmpty == true
            ? prop('displayname')!
            : parts.last,
        folder: directory,
        size: int.tryParse(prop('getcontentlength') ?? '') ?? 0,
      );
      if (entry.folder || entry.isBook) entries.add(entry);
    }
    entries.sort(
      (a, b) =>
          a.folder != b.folder ? (a.folder ? -1 : 1) : a.name.compareTo(b.name),
    );
    return CloudBookListing(entries);
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int, int?)? onProgress,
  }) async {
    if (!entry.isBook) {
      throw const CloudSourceFailure('请选择支持的电子书或文档');
    }
    final res = await http.request(
      'GET',
      _resource(entry.id),
      headers: _headers,
      redirects: true,
      allowHttp: config.allowHttp,
    );
    await http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  void cancel() => http.close();
  @override
  void close() => http.close();
}

/// An independently implemented read-only client of the web wire protocol
/// documented by OpenList. No upstream Go driver is bundled or translated.
class QuarkBookClient implements CloudBookClient {
  QuarkBookClient(this.config, {this.settings, CloudHttp? http, Uri? api})
    : http = http ?? CloudHttp(),
      api = api ?? Uri.parse('https://drive.quark.cn/1/clouddrive') {
    config.validate();
  }
  CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  final Uri api;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 Safari/537.36 Channel/pckk_other_ch';
  @override
  String get root => '0';
  Map<String, String> _headers(Uri uri) => {
    'User-Agent': userAgent,
    'Referer': 'https://pan.quark.cn/',
    if (CloudHttp.sameOrigin(uri, api) ||
        (uri.scheme == 'https' &&
            (uri.host == 'quark.cn' || uri.host.endsWith('.quark.cn'))))
      'Cookie': config.cookie,
  };
  Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, String> query = const {},
    Object? body,
  }) async {
    final uri = api.replace(
      path: '${api.path}$path',
      queryParameters: {'pr': 'ucpro', 'fr': 'pc', ...query},
    );
    final res = await http.request(
      body == null ? 'GET' : 'POST',
      uri,
      headers: (u) => {
        ..._headers(u),
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      },
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      allowHttp: api.scheme == 'http',
    );
    final bytes = await http.bytes(res);
    var cookie = config.cookie;
    for (final value in res.cookies.where(
      (c) => c.name == '__puus' || c.name == '__pus',
    )) {
      final pattern = RegExp('(^|;\\s*)${value.name}=[^;]*');
      cookie = cookie.contains(pattern)
          ? cookie.replaceFirstMapped(
              pattern,
              (m) => '${m[1]}${value.name}=${value.value}',
            )
          : '$cookie; ${value.name}=${value.value}';
    }
    if (cookie != config.cookie) {
      await settings?.rotate(config, cookie);
      config = config.withCookie(cookie);
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) {
      throw const CloudSourceFailure('夸克返回的数据格式有误');
    }
    if (data['code'] != 0 || (data['status'] is num && data['status'] >= 400)) {
      if (data['status'] == 401 ||
          data['status'] == 403 ||
          data['code'] == 401) {
        throw const CloudSourceFailure(
          '夸克登录已失效，请更新 Cookie',
          authentication: true,
        );
      }
      throw const CloudSourceFailure('夸克暂时无法完成请求，请稍后重试或更新 Cookie');
    }
    return data;
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    final data = await _call(
      '/file/sort',
      query: {
        'pdir_fid': folder,
        '_size': '100',
        '_page': '$page',
        '_fetch_total': '1',
        'fetch_all_file': '1',
        'fetch_risk_file_name': '1',
        '_sort': 'file_type:asc,file_name:asc',
      },
    );
    final rows = data['data']?['list'];
    if (rows is! List) throw const CloudSourceFailure('夸克目录数据有误');
    final entries = <CloudBookEntry>[];
    for (final row in rows) {
      if (row is! Map ||
          row['fid'] is! String ||
          row['file_name'] is! String ||
          row['file'] is! bool) {
        continue;
      }
      final entry = CloudBookEntry(
        id: row['fid'],
        name: row['file_name'],
        folder: row['file'] != true,
        size: row['size'] is int ? row['size'] : 0,
      );
      if (entry.folder || entry.isBook) entries.add(entry);
    }
    final total = data['metadata']?['_total'];
    return CloudBookListing(
      entries,
      nextPage: (total is num ? page * 100 < total : rows.length == 100)
          ? page + 1
          : null,
    );
  }

  @override
  Future<String?> directLink(CloudBookEntry entry) async {
    final value = await _call(
      '/file/download',
      body: {
        'fids': [entry.id],
      },
    );
    final rows = value['data'];
    if (rows is! List ||
        rows.isEmpty ||
        rows.first is! Map ||
        rows.first['download_url'] is! String) {
      return null;
    }
    return rows.first['download_url'] as String;
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int, int?)? onProgress,
  }) async {
    if (!entry.isBook) {
      throw const CloudSourceFailure('请选择支持的电子书或文档');
    }
    final url = await directLink(entry);
    if (url == null) {
      throw const CloudSourceFailure('夸克没有返回可用的下载地址');
    }
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
  void cancel() => http.close();
  @override
  void close() => http.close();
}

/// 蓝奏云 / 迅雷等网盘的直链客户端。
///
/// 用户从网盘网页复制文件的下载直链（带 sign 的临时地址）粘贴进来，
/// 客户端只做一次 GET，跟随跳转后流式读取，不保留账号 Cookie，
/// 也不会把文件长期写入应用目录。适合蓝奏云、迅雷以及任意 HTTPS 直链。
class DirectLinkBookClient implements CloudBookClient {
  DirectLinkBookClient(this.config) : _http = CloudHttp();

  final CloudSourceConfig config;
  final CloudHttp _http;

  Map<String, String> get authHeaders {
    final headers = <String, String>{};
    if (config.cookie.trim().isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = config.cookie.trim();
    }
    if (config.username.trim().isNotEmpty && config.password.isNotEmpty) {
      final token = base64Encode(
        utf8.encode('${config.username.trim()}:${config.password}'),
      );
      headers[HttpHeaders.authorizationHeader] = 'Basic $token';
    }
    return headers;
  }

  @override
  String get root => config.address.trim();
  @override
  Future<String?> directLink(CloudBookEntry entry) async => entry.id;

  Uri get _uri {
    final uri = Uri.tryParse(root);
    if (uri == null) throw const CloudSourceFailure('直链地址无效');
    CloudHttp.validateUrl(uri, allowHttp: config.allowHttp);
    return uri;
  }

  String get _name {
    final segments = _uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final segment = segments.isEmpty ? null : segments.last;
    final decoded = segment == null ? '' : Uri.decodeComponent(segment);
    return supportsBookImport(decoded) ? decoded : '云端书籍.epub';
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    if (page > 1) return const CloudBookListing([]);
    return CloudBookListing([
      CloudBookEntry(id: root, name: _name, folder: false, size: 0),
    ]);
  }

  @override
  Future<void> download(
    CloudBookEntry entry,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final res = await _http.request(
      'GET',
      Uri.parse(entry.id),
      headers: (_) => {'Accept': '*/*', ...authHeaders},
      redirects: true,
      allowHttp: config.allowHttp,
      redirectMessage: '直链发生跳转，请重新复制最新的下载地址',
    );
    await _http.save(res, target, bookName: entry.name, onProgress: onProgress);
  }

  @override
  void cancel() => _http.close();

  @override
  void close() => _http.close();
}

/// RSS / Atom 书源：一个订阅地址就是一套书源，条目里的链接就是书页。
///
/// 只读取公开订阅，不登录站点，不抓取需要 Cookie 的私有内容。
class RssBookClient extends DirectLinkBookClient {
  RssBookClient(super.config);

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    if (page > 1) return const CloudBookListing([]);
    final uri = Uri.parse(root);
    final res = await CloudHttp().request(
      'GET',
      uri,
      headers: (_) => {
        'Accept':
            'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
        ...authHeaders,
      },
      redirects: true,
      allowHttp: config.allowHttp,
      redirectMessage: '书源地址发生跳转，请填写最终 RSS/Atom 地址',
    );
    final bytes = await CloudHttp().bytes(res, limit: 4 * 1024 * 1024);
    final document = XmlDocument.parse(
      utf8.decode(bytes, allowMalformed: true),
    );
    final items = document.findAllElements('item');
    final entries = document.findAllElements('entry');
    final result = <CloudBookEntry>[];
    void add(String title, String? link, String summary, [String author = '']) {
      if (title.trim().isEmpty || link == null || link.trim().isEmpty) return;
      final resolved = Uri.parse(root).resolve(link.trim()).toString();
      result.add(
        CloudBookEntry(
          id: resolved,
          name: title.trim(),
          folder: false,
          size: 0,
          author: author.trim(),
        ),
      );
    }

    for (final item in items) {
      final title = _child(item, 'title');
      var link = _child(item, 'link');
      if (link.isEmpty) link = _child(item, 'guid');
      final author = _child(item, 'author').isNotEmpty
          ? _child(item, 'author')
          : _child(item, 'dc:creator');
      add(title, link, _child(item, 'description'), author);
    }
    for (final item in entries) {
      final title = _child(item, 'title');
      String link = '';
      for (final node in item.findElements('link')) {
        final href = node.getAttribute('href');
        if (href != null) {
          link = href;
          break;
        }
      }
      final author = _child(item, 'author').isNotEmpty
          ? _child(item, 'author')
          : _child(item, 'dc:creator');
      add(title, link, _child(item, 'summary'), author);
    }
    if (result.isEmpty) throw const CloudSourceFailure('这个订阅里没有可阅读的条目');
    return CloudBookListing(result);
  }

  String _child(XmlElement item, String name) {
    for (final node in item.findElements(name)) {
      return node.innerText.trim();
    }
    return '';
  }
}
