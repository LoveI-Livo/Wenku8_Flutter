import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:charset/charset.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import 'book_import_limits.dart';
import 'book_search.dart';
import 'cloud_guangya.dart';
part 'cloud_s3.dart';
part 'cloud_lanzou.dart';
part 'cloud_ilanzou.dart';
part 'cloud_baidu.dart';
part 'cloud_123.dart';
part 'cloud_aliyun.dart';
part 'cloud_xunlei.dart';
part 'cloud_web.dart';
part 'legado_reader.dart';

enum CloudSourceKind {
  webdav('WebDAV'),
  quark('夸克网盘'),
  lanzou('蓝奏云 · 普通版'),
  lanzouPro('蓝奏云 · 优享版'),
  xunlei('迅雷云盘'),
  guangya('光鸭云盘'),
  aliyun('阿里云盘'),
  baidu('百度网盘'),
  pan123('123 云盘'),
  uc('UC 网盘'),
  direct('其他网盘直链'),
  rss('小说书源 · RSS / Atom / JSON / 网页'),
  s3('S3 / 兼容对象存储');

  const CloudSourceKind(this.label);
  final String label;

  /// 0.8.3 起只维护 WebDAV、蓝奏云、蓝奏云优享版、迅雷云盘和小说书源。
  /// 其余枚举保留用于读取旧记录，但不再出现在添加页、连接页和搜索里。
  static const active = [webdav, lanzou, lanzouPro, xunlei, guangya, rss];

  bool get isActive => active.contains(this);

  /// 这些来源都通过「文件下载直链」流式读取，不保存账号 Cookie。
  bool get isDirectLink => switch (this) {
    direct || rss => true,
    _ => false,
  };

  /// Sources that expose a logged-in folder tree instead of a pasted link.
  bool get isAccount => switch (this) {
    quark ||
    lanzou ||
    lanzouPro ||
    xunlei ||
    guangya ||
    baidu ||
    pan123 ||
    aliyun ||
    uc ||
    webdav ||
    s3 => true,
    _ => false,
  };

  /// Sources whose login is performed on the provider's own website.
  bool get isWebLogin => switch (this) {
    quark ||
    lanzou ||
    lanzouPro ||
    xunlei ||
    guangya ||
    baidu ||
    pan123 ||
    aliyun ||
    uc => true,
    _ => false,
  };
}

/// 一个独立的小说书源。地址可以是 RSS / Atom / JSON / 网页，也可以是
/// 带 `{query}`、`{page}` 的搜索地址；多个书源保存在同一条 rss 配置中。
/// 书源列表上限：不少 Legado 合集动辄几千条，按 10000 条留出余量。
const int maxBookSources = 10000;

class CloudBookSourceProbe {
  const CloudBookSourceProbe({
    required this.valid,
    this.message = '',
    this.books = 0,
  });
  final bool valid;
  final String message;
  final int books;
}

class CloudBookSource {
  const CloudBookSource({
    required this.url,
    this.name = '',
    this.group = '',
    this.enabled = true,
    this.status = '',
    this.message = '',
    this.checkedAt,
    this.rules = const {},
  });
  final String url, name, group, status, message;
  final bool enabled;
  final DateTime? checkedAt;

  /// Legado/阅读书源的规则。为空时按普通网页/RSS/JSON 书源处理。
  final Map<String, dynamic> rules;
  bool get isLegado => rules.isNotEmpty;
  String get key => isLegado ? '$url|$name|${jsonEncode(rules)}' : url;
  String get label =>
      name.trim().isNotEmpty ? name.trim() : Uri.tryParse(url)?.host ?? url;
  bool get valid => status == 'valid';
  bool get invalid => status == 'invalid';
  Map<String, Object> toRecord() => {
    'url': url,
    'name': name,
    if (group.isNotEmpty) 'group': group,
    if (rules.isNotEmpty) 'rules': rules,
    if (!enabled) 'enabled': false,
    if (status.isNotEmpty) 'status': status,
    if (message.isNotEmpty) 'message': message,
    if (checkedAt != null) 'checkedAt': checkedAt!.millisecondsSinceEpoch,
  };
  factory CloudBookSource.fromRecord(Object? value) {
    if (value is String) return CloudBookSource(url: value.trim());
    if (value is! Map) throw const FormatException('书源记录格式有误');
    final map = Map<String, dynamic>.from(value);
    final url = (map['url'] ?? '').toString().trim();
    if (url.isEmpty) throw const FormatException('书源地址为空');
    return CloudBookSource(
      url: url,
      name: (map['name'] ?? '').toString(),
      group: (map['group'] ?? '').toString(),
      enabled: map['enabled'] != false,
      rules: map['rules'] is Map
          ? Map<String, dynamic>.from(map['rules'] as Map)
          : const {},
      status: (map['status'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      checkedAt: map['checkedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['checkedAt'] as int)
          : null,
    );
  }
  CloudBookSource copyWith({
    String? url,
    String? name,
    String? group,
    bool? enabled,
    String? status,
    String? message,
    DateTime? checkedAt,
    Map<String, dynamic>? rules,
  }) => CloudBookSource(
    url: url ?? this.url,
    name: name ?? this.name,
    group: group ?? this.group,
    enabled: enabled ?? this.enabled,
    rules: rules ?? this.rules,
    status: status ?? this.status,
    message: message ?? this.message,
    checkedAt: checkedAt ?? this.checkedAt,
  );
}

/// Only this device's encrypted vault contains connection secrets. This record
/// is deliberately separate from SharedPreferences and LibraryBackup.
class CloudSourceConfig {
  const CloudSourceConfig({
    required this.kind,
    this.connectionId = '',
    this.address = '',
    this.username = '',
    this.password = '',
    this.cookie = '',
    this.allowHttp = false,
    this.bucket = '',
    this.region = 'us-east-1',
    this.prefix = '',
    this.sessionToken = '',
    this.deviceId = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.driveId = '',
    this.pathStyle = true,
    this.sources = const [],
  });
  final CloudSourceKind kind;

  /// 同一个网盘类型可以连接多个账号/地址；空值只用于旧记录。
  final String connectionId;
  final String address, username, password, cookie;
  final bool allowHttp;
  final String bucket, region, prefix, sessionToken;

  /// 优享版等网盘需要稳定设备号；网页登录只给 appToken Cookie 时由本机生成并保存。
  final String deviceId;

  /// 123 / 阿里云盘官网登录后保存在本机的 Bearer token；不会写入阅读备份。
  final String accessToken, refreshToken, driveId;
  final bool pathStyle;

  /// rss 类型下逐个书源的状态；旧记录为空时从 [address] 逐行解析。
  final List<CloudBookSource> sources;

  List<CloudBookSource> get effectiveSources {
    if (kind != CloudSourceKind.rss) return const [];
    if (sources.isNotEmpty)
      return sources.where((source) => source.enabled).toList(growable: false);
    return address
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => CloudBookSource(url: value))
        .toList(growable: false);
  }

  CloudSourceConfig withAllowHttp(bool value) => CloudSourceConfig(
    kind: kind,
    connectionId: connectionId,
    address: address,
    username: username,
    password: password,
    cookie: cookie,
    allowHttp: value,
    bucket: bucket,
    region: region,
    prefix: prefix,
    sessionToken: sessionToken,
    deviceId: deviceId,
    accessToken: accessToken,
    refreshToken: refreshToken,
    driveId: driveId,
    pathStyle: pathStyle,
    sources: sources,
  );

  CloudSourceConfig withSources(List<CloudBookSource> value) =>
      CloudSourceConfig(
        kind: kind,
        connectionId: connectionId,
        address: value
            .where((source) => source.enabled)
            .map((source) => source.url)
            .join('\n'),
        username: username,
        password: password,
        cookie: cookie,
        allowHttp: allowHttp,
        bucket: bucket,
        region: region,
        prefix: prefix,
        sessionToken: sessionToken,
        deviceId: deviceId,
        accessToken: accessToken,
        refreshToken: refreshToken,
        driveId: driveId,
        pathStyle: pathStyle,
        sources: value,
      );
  String get label => kind.label;
  Uri get endpoint {
    final uri = Uri.parse(address.trim());
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  void validate() {
    if (kind == CloudSourceKind.rss) {
      final entries = effectiveSources;
      // 允许保存全部停用的书源；地址与状态保留，重新启用后立即恢复。
      if ((entries.isEmpty && sources.isEmpty) ||
          entries.length > maxBookSources ||
          sources.length > maxBookSources) {
        throw const CloudSourceFailure(
          '小说书源最多 $maxBookSources 个；请检查地址是否为空或格式是否异常',
        );
      }
      for (final entry in entries) {
        final source = entry.url;
        final probe = source
            .replaceAll('{query}', 'keyword')
            .replaceAll('{page}', '1');
        final uri = Uri.tryParse(probe);
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp)) ||
            source.length > 4096) {
          throw const CloudSourceFailure(
            '小说书源地址需要是 HTTPS 网页或订阅地址；HTTP 需先允许明文连接',
          );
        }
      }
      if (cookie.length > 16384 ||
          RegExp(r'[\r\n\x00]').hasMatch(cookie) ||
          RegExp(r'[\r\n\x00]').hasMatch(username + password) ||
          username.contains(':') ||
          password.length > 8192) {
        throw const CloudSourceFailure('请检查书源 Cookie、用户名或密码');
      }
      return;
    }
    if (kind == CloudSourceKind.lanzouPro) {
      final legacy = cookie.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (!RegExp(r'(?:^|;\s*)appToken=[^;]+').hasMatch(cookie) ||
              cookie.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(cookie))) {
        throw const CloudSourceFailure('请先在蓝奏云优享版官网登录，自动获取 appToken Cookie');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('蓝奏云优享版登录已失效，请重新登录账号');
        }
      }
      if (deviceId.length > 128 || RegExp(r'[\r\n\x00]').hasMatch(deviceId)) {
        throw const CloudSourceFailure('蓝奏云优享版设备标识异常，请重新登录');
      }
      return;
    }
    if (kind == CloudSourceKind.xunlei) {
      final legacy = accessToken.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (accessToken.trim().isEmpty ||
              accessToken.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(accessToken + refreshToken))) {
        throw const CloudSourceFailure('请先在迅雷云盘官网登录，自动获取账号令牌');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('迅雷云盘登录已失效，请重新登录账号');
        }
      }
      return;
    }
    if (kind == CloudSourceKind.guangya) {
      if (accessToken.trim().isEmpty ||
          accessToken.length > 32768 ||
          RegExp(r'[\r\n\x00]').hasMatch(accessToken + refreshToken)) {
        throw const CloudSourceFailure('请先登录光鸭云盘账号');
      }
      if (deviceId.length > 128 || RegExp(r'[\r\n\x00]').hasMatch(deviceId)) {
        throw const CloudSourceFailure('光鸭云盘设备标识异常，请重新登录');
      }
      return;
    }
    if (kind == CloudSourceKind.baidu) {
      final legacy = cookie.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (!RegExp(r'(?:^|;\s*)BDUSS=[^;]+').hasMatch(cookie) ||
              cookie.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(cookie))) {
        throw const CloudSourceFailure('请先在百度网盘官网登录，自动获取 BDUSS Cookie');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('百度网盘登录已失效，请重新登录账号');
        }
      }
      return;
    }
    if (kind == CloudSourceKind.pan123) {
      final legacy = accessToken.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (accessToken.trim().isEmpty ||
              accessToken.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(accessToken))) {
        throw const CloudSourceFailure('请先在 123 云盘官网登录，自动获取账号令牌');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('123 云盘登录已失效，请重新登录账号');
        }
      }
      return;
    }
    if (kind == CloudSourceKind.aliyun) {
      final legacy = accessToken.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (accessToken.trim().isEmpty ||
              accessToken.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(accessToken + refreshToken))) {
        throw const CloudSourceFailure('请先在阿里云盘官网登录，自动获取账号令牌');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('阿里云盘登录已失效，请重新登录账号');
        }
      }
      return;
    }
    if (kind == CloudSourceKind.uc) {
      final legacy = cookie.trim().isEmpty && address.trim().isNotEmpty;
      if (!legacy &&
          (cookie.trim().isEmpty ||
              cookie.length > 16384 ||
              RegExp(r'[\r\n\x00]').hasMatch(cookie) ||
              !RegExp(r'(?:^|;\s*)(?:__puus|__pus)=[^;]+').hasMatch(cookie))) {
        throw const CloudSourceFailure('请先在 UC 网盘官网登录，自动获取 __puus Cookie');
      }
      if (legacy) {
        final uri = Uri.tryParse(address.trim());
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            (uri.scheme != 'https' && !(uri.scheme == 'http' && allowHttp))) {
          throw const CloudSourceFailure('UC 网盘登录已失效，请重新登录账号');
        }
      }
      return;
    }
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
    if (connectionId.isNotEmpty) 'connectionId': connectionId,
    'address': address.trim(),
    'username': username,
    'password': password,
    'cookie': cookie,
    'allowHttp': allowHttp,
    if (deviceId.isNotEmpty) 'deviceId': deviceId,
    if (accessToken.isNotEmpty) 'accessToken': accessToken,
    if (refreshToken.isNotEmpty) 'refreshToken': refreshToken,
    if (driveId.isNotEmpty) 'driveId': driveId,
    if (kind == CloudSourceKind.s3) ...{
      'bucket': bucket,
      'region': region,
      'prefix': prefix,
      'sessionToken': sessionToken,
      'pathStyle': pathStyle,
    },
    if (kind == CloudSourceKind.rss && sources.isNotEmpty)
      'sources': sources
          .map((source) => source.toRecord())
          .toList(growable: false),
  };
  factory CloudSourceConfig.fromRecord(Map<String, dynamic> record) {
    final value = CloudSourceConfig(
      kind: CloudSourceKind.values.byName(record['kind']),
      connectionId: (record['connectionId'] ?? '').toString(),
      address: record['address'] ?? '',
      username: record['username'] ?? '',
      password: record['password'] ?? '',
      cookie: record['cookie'] ?? '',
      allowHttp: record['allowHttp'] == true,
      bucket: record['bucket'] ?? '',
      region: record['region'] ?? 'us-east-1',
      prefix: record['prefix'] ?? '',
      sessionToken: record['sessionToken'] ?? '',
      deviceId: record['deviceId'] ?? '',
      accessToken: record['accessToken'] ?? '',
      refreshToken: record['refreshToken'] ?? '',
      driveId: record['driveId'] ?? '',
      pathStyle: record['pathStyle'] != false,
      sources: record['sources'] is List
          ? [
              for (final source in record['sources'] as List)
                CloudBookSource.fromRecord(source),
            ]
          : const [],
    );
    value.validate();
    return value;
  }
  CloudSourceConfig withCookie(String value) => copyWith(cookie: value);

  CloudSourceConfig copyWith({
    CloudSourceKind? kind,
    String? connectionId,
    String? address,
    String? username,
    String? password,
    String? cookie,
    bool? allowHttp,
    String? bucket,
    String? region,
    String? prefix,
    String? sessionToken,
    String? deviceId,
    String? accessToken,
    String? refreshToken,
    String? driveId,
    bool? pathStyle,
    List<CloudBookSource>? sources,
  }) => CloudSourceConfig(
    kind: kind ?? this.kind,
    connectionId: connectionId ?? this.connectionId,
    address: address ?? this.address,
    username: username ?? this.username,
    password: password ?? this.password,
    cookie: cookie ?? this.cookie,
    allowHttp: allowHttp ?? this.allowHttp,
    bucket: bucket ?? this.bucket,
    region: region ?? this.region,
    prefix: prefix ?? this.prefix,
    sessionToken: sessionToken ?? this.sessionToken,
    deviceId: deviceId ?? this.deviceId,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    driveId: driveId ?? this.driveId,
    pathStyle: pathStyle ?? this.pathStyle,
    sources: sources ?? this.sources,
  );
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

  /// 每个类型保留一个“主连接”供旧代码兼容；同类型的其它连接放在 extras。
  final Map<CloudSourceKind, CloudSourceConfig> _configs = {};
  final List<CloudSourceConfig> _extras = [];
  S3SyncConnection? _s3Sync;
  S3SyncConnection? get s3Sync => _s3Sync;
  Future<void> _writes = Future.value();
  Future<void>? _loading;
  bool _loaded = false;
  bool _disposed = false;
  String? error;

  CloudSourceConfig? operator [](CloudSourceKind kind) => _configs[kind];
  Iterable<CloudSourceConfig> get configs =>
      List<CloudSourceConfig>.unmodifiable([..._configs.values, ..._extras]);
  Iterable<CloudSourceConfig> get activeConfigs =>
      configs.where((config) => config.kind.isActive);
  Iterable<CloudSourceConfig> configsFor(CloudSourceKind kind) =>
      configs.where((config) => config.kind == kind);
  CloudSourceConfig? byId(String id) {
    if (id.isEmpty) return null;
    for (final config in configs) {
      if (config.connectionId == id) return config;
    }
    return null;
  }

  String newConnectionId(CloudSourceKind kind) {
    final used = configs.map((config) => config.connectionId).toSet();
    var index = 1;
    while (used.contains('${kind.name}-$index')) {
      index++;
    }
    return '${kind.name}-$index';
  }

  /// 页面与搜索会反复读取同一份配置。首次从加密存储解析后缓存住，
  /// 只有保存/外部 reload 才重新读取，避免每次打开来源选择都解析整份书源。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final running = _loading;
    if (running != null) return running;
    final future = load();
    _loading = future;
    try {
      await future;
    } finally {
      if (identical(_loading, future)) _loading = null;
    }
  }

  Future<void> load() async {
    try {
      final text = await storage.read();
      final values = text == null ? <dynamic>[] : jsonDecode(text);
      if (values is! List) throw const FormatException();
      final primary = <CloudSourceKind, CloudSourceConfig>{};
      final extras = <CloudSourceConfig>[];
      final ids = <String>{};
      S3SyncConnection? sync;
      for (final value in values) {
        if (value is Map && value['purpose'] == 'book-sync') {
          if (sync != null) throw const FormatException();
          sync = S3SyncConnection.fromRecord(Map<String, dynamic>.from(value));
          continue;
        }
        var config = CloudSourceConfig.fromRecord(
          Map<String, dynamic>.from(value),
        );
        var id = config.connectionId;
        if (id.isEmpty || !ids.add(id)) {
          id = '${config.kind.name}-${ids.length + 1}';
          while (!ids.add(id)) {
            id = '${config.kind.name}-${ids.length + 1}';
          }
          config = config.copyWith(connectionId: id);
        }
        if (!primary.containsKey(config.kind)) {
          primary[config.kind] = config;
        } else {
          extras.add(config);
        }
      }
      _configs
        ..clear()
        ..addAll(primary);
      _extras
        ..clear()
        ..addAll(extras);
      _s3Sync = sync;
      error = null;
      _loaded = true;
    } catch (_) {
      _loaded = false;
      error = '无法读取本机网盘连接，请重新保存连接';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> rotateTokens(
    CloudSourceConfig config, {
    String? accessToken,
    String? refreshToken,
    String? driveId,
    String? cookie,
    String? deviceId,
  }) => _save(
    config.kind,
    config.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
      driveId: driveId,
      cookie: cookie,
      deviceId: deviceId,
    ),
  );

  Future<void> save(CloudSourceKind kind, CloudSourceConfig? value) =>
      _save(kind, value);

  Future<void> _save(
    CloudSourceKind kind,
    CloudSourceConfig? value, {
    String? expectedCookie,
    String? expectedId,
  }) {
    value?.validate();
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (expectedCookie != null) {
        final current = expectedId == null ? _configs[kind] : byId(expectedId);
        if (current?.cookie != expectedCookie) return;
      }
      final nextPrimary = {..._configs};
      final nextExtras = [..._extras];
      if (value == null) {
        nextPrimary.remove(kind);
        nextExtras.removeWhere((config) => config.kind == kind);
      } else if (value.connectionId.isNotEmpty) {
        var replaced = false;
        for (var i = 0; i < nextExtras.length; i++) {
          if (nextExtras[i].connectionId == value.connectionId) {
            nextExtras[i] = value;
            replaced = true;
            break;
          }
        }
        final primary = nextPrimary[kind];
        if (!replaced && primary?.connectionId == value.connectionId) {
          nextPrimary[kind] = value;
          replaced = true;
        }
        if (!replaced) {
          if (primary == null) {
            nextPrimary[kind] = value;
          } else {
            nextExtras.add(value);
          }
        }
      } else {
        nextPrimary[kind] = value;
      }
      await _writeRecords(nextPrimary, nextExtras, _s3Sync);
      _configs
        ..clear()
        ..addAll(nextPrimary);
      _extras
        ..clear()
        ..addAll(nextExtras);
      error = null;
      _loaded = true;
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    return work;
  }

  /// 删除某一个连接。同一类型还有其它连接时，自动把下一个提升为主连接，
  /// 这样旧代码通过 settings[kind] 仍然能拿到一个有效配置。
  Future<void> remove(CloudSourceConfig target) {
    final work = _writes.catchError((Object _) {}).then((_) async {
      final nextPrimary = {..._configs};
      final nextExtras = [..._extras];
      if (nextPrimary[target.kind]?.connectionId == target.connectionId) {
        nextPrimary.remove(target.kind);
      }
      nextExtras.removeWhere(
        (config) =>
            config.kind == target.kind &&
            config.connectionId == target.connectionId,
      );
      if (!nextPrimary.containsKey(target.kind)) {
        final replacement = nextExtras
            .where((config) => config.kind == target.kind)
            .firstOrNull;
        if (replacement != null) {
          nextPrimary[target.kind] = replacement;
          nextExtras.remove(replacement);
        }
      }
      await _writeRecords(nextPrimary, nextExtras, _s3Sync);
      _configs
        ..clear()
        ..addAll(nextPrimary);
      _extras
        ..clear()
        ..addAll(nextExtras);
      error = null;
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    return work;
  }

  Future<void> _writeRecords(
    Map<CloudSourceKind, CloudSourceConfig> configs,
    List<CloudSourceConfig> extras,
    S3SyncConnection? sync,
  ) => storage.write(
    configs.isEmpty && extras.isEmpty && sync == null
        ? null
        : jsonEncode([
            ...configs.values.map((c) => c.toRecord()),
            ...extras.map((c) => c.toRecord()),
            if (sync != null) sync.toRecord(),
          ]),
  );

  /// Sync is a separate, explicitly saved connection. Editing or removing an
  /// import source never silently changes the destination receiving books.
  Future<void> saveS3Sync(S3SyncConnection? value) {
    value?.validate();
    final work = _writes.catchError((Object _) {}).then((_) async {
      await _writeRecords(_configs, _extras, value);
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
    expectedId: previous.connectionId,
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
    this.summary = '',
    this.coverUrl,
    this.book = false,
    this.extra = const {},
  });
  final String id, name;
  final bool folder;
  final int size;
  final String author;

  /// 书源搜索/目录接口直接给出的封面地址。网盘文件没有这个字段时，
  /// 打开详情后再从文件元数据里补封面，不在搜索阶段下载整本书。
  final String? coverUrl;

  /// RSS/Atom 或目录接口能直接提供的简介；WebDAV 通常为空，需要读取文件
  /// 元数据后再补。只用于搜索和展示，不落盘。
  final String summary;

  /// 书源条目不一定带文件扩展名，不能只靠文件名判断是不是书。
  final bool book;

  /// 账号网盘下载签名所需的少量字段（etag、s3keyFlag 等），不落盘。
  final Map<String, Object?> extra;
  bool get isBook => !folder && (book || supportsBookImport(name));
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
    CloudSourceKind.lanzouPro =>
      config.cookie.trim().isEmpty
          ? DirectLinkBookClient(config)
          : LanzouProBookClient(config, settings: settings),
    CloudSourceKind.uc =>
      config.cookie.trim().isEmpty
          ? DirectLinkBookClient(config)
          : UcBookClient(config, settings: settings),
    CloudSourceKind.baidu =>
      config.cookie.trim().isEmpty
          ? DirectLinkBookClient(config)
          : BaiduBookClient(config),
    CloudSourceKind.pan123 =>
      config.accessToken.trim().isEmpty
          ? DirectLinkBookClient(config)
          : Pan123BookClient(config, settings: settings),
    CloudSourceKind.aliyun =>
      config.accessToken.trim().isEmpty
          ? DirectLinkBookClient(config)
          : AliyunBookClient(config, settings: settings),
    CloudSourceKind.xunlei =>
      config.accessToken.trim().isEmpty
          ? DirectLinkBookClient(config)
          : XunleiBookClient(config, settings: settings),
    CloudSourceKind.guangya => GuangyaBookClient(config, settings: settings),
    CloudSourceKind.rss => RssBookClient(config),
    CloudSourceKind.direct => DirectLinkBookClient(config),
    CloudSourceKind.s3 => S3BookClient(config),
  };
  String get root;
  Future<CloudBookListing> list(String folder, {int page = 1});

  /// 书源可以有自己的搜索地址模板；网盘默认仍按目录浏览。
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

  /// A URL that the in-memory reader can fetch. Most clients store the URL
  /// itself as the entry id; account clients resolve a fresh signed URL.
  Future<String?> directLink(CloudBookEntry entry) async => entry.id;

  /// Removes the provider object. Only clients with a safe single-file API
  /// override this; the default keeps the shelf record untouched.
  Future<void> delete(CloudBookEntry entry) async {
    throw const CloudSourceFailure('当前网盘不支持 App 内删除原文件');
  }

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
/// 下载限速只作用于当前由下载中心发起的请求。0 或 null 表示不限速。
abstract final class CloudThrottle {
  static double? bytesPerSecond;
  static int _bytes = 0;
  static final _clock = Stopwatch();

  static Future<void> consume(int bytes) async {
    final rate = bytesPerSecond;
    if (rate == null || rate <= 0 || bytes <= 0) return;
    if (!_clock.isRunning) _clock.start();
    _bytes += bytes;
    final target = Duration(microseconds: (_bytes / rate * 1000000).round());
    final elapsed = _clock.elapsed;
    if (target > elapsed) await Future<void>.delayed(target - elapsed);
    if (_clock.elapsed > const Duration(seconds: 20)) {
      _clock.reset();
      _bytes = 0;
    }
  }
}

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
              redirectMessage ?? '网盘地址发生跳转，请填写最终 WebDAV 地址或启用 AList 代理',
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
        await CloudThrottle.consume(part.length);
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
      throw const CloudSourceFailure('网盘返回了登录网页，请更新连接或开启 AList 下载代理');
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
        await CloudThrottle.consume(part.length);
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
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);
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
  Future<void> delete(CloudBookEntry entry) async {
    await http.request(
      'DELETE',
      _resource(entry.id),
      headers: _headers,
      allowHttp: config.allowHttp,
    );
  }

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
/// documented by AList. No upstream Go driver is bundled or translated.
class QuarkBookClient implements CloudBookClient {
  QuarkBookClient(
    this.config, {
    this.settings,
    CloudHttp? http,
    Uri? api,
    this.label = '夸克',
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 Safari/537.36 Channel/pckk_other_ch',
    this.referer = 'https://pan.quark.cn/',
    this.pr = 'ucpro',
    this.cookieDomain = 'quark.cn',
  }) : http = http ?? CloudHttp(),
       api = api ?? Uri.parse('https://drive.quark.cn/1/clouddrive') {
    config.validate();
  }
  CloudSourceConfig config;
  final CloudSourceSettings? settings;
  final CloudHttp http;
  final Uri api;
  final String label, userAgent, referer, pr, cookieDomain;
  @override
  String get root => '0';

  @override
  Future<void> delete(CloudBookEntry entry) async {
    final value = await _call(
      '/file/delete',
      body: {
        'fids': [entry.id],
      },
    );
    final data = value['data'];
    if (data is Map && data['task_id'] is String && data['task_id'] != '') {
      // Quark deletes asynchronously; a queued delete is enough for the
      // explicit user confirmation. The file disappears after the task runs.
      return;
    }
    if (value['code'] == 0) return;
    throw const CloudSourceFailure('夸克没有确认删除结果，请到网页端核对');
  }

  Map<String, String> _headers(Uri uri) => {
    'User-Agent': userAgent,
    'Referer': referer,
    if (CloudHttp.sameOrigin(uri, api) ||
        (uri.scheme == 'https' &&
            (uri.host == cookieDomain || uri.host.endsWith('.$cookieDomain'))))
      'Cookie': config.cookie,
  };
  Future<Map<String, dynamic>> _call(
    String path, {
    Map<String, String> query = const {},
    Object? body,
  }) async {
    final uri = api.replace(
      path: '${api.path}$path',
      queryParameters: {'pr': pr, 'fr': 'pc', ...query},
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
      throw CloudSourceFailure('$label返回的数据格式有误');
    }
    if (data['code'] != 0 || (data['status'] is num && data['status'] >= 400)) {
      if (data['status'] == 401 ||
          data['status'] == 403 ||
          data['code'] == 401) {
        throw CloudSourceFailure('$label登录已失效，请重新登录官网账号', authentication: true);
      }
      throw CloudSourceFailure('$label暂时无法完成请求，请稍后重试或重新登录');
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
    if (rows is! List) throw CloudSourceFailure('$label目录数据有误');
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
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

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
      throw CloudSourceFailure('$label没有返回可用的下载地址');
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

/// UC 网盘与夸克共用同一套云盘接口；区别只在域名、UA 和来源标识。
class UcBookClient extends QuarkBookClient {
  UcBookClient(CloudSourceConfig config, {CloudSourceSettings? settings})
    : super(
        config,
        settings: settings,
        api: Uri.parse('https://pc-api.uc.cn/1/clouddrive'),
        label: 'UC 网盘',
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) uc-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 Safari/537.36 Channel/pckk_other_ch',
        referer: 'https://drive.uc.cn/',
        pr: 'UCBrowser',
        cookieDomain: 'uc.cn',
      );
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
  Future<void> delete(CloudBookEntry entry) async {
    await _http.request(
      'DELETE',
      Uri.parse(entry.id),
      headers: (_) => authHeaders,
      allowHttp: config.allowHttp,
    );
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) =>
      list(root, page: page);

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

/// 小说书源：RSS、Atom、JSON Feed、JSON 列表和普通网页目录都走这里。
///
/// 地址可以一行一个，最多 10000 个；带 `{query}` / `{page}` 的地址会按关键词
/// 和页码替换。条目链接既可以是 txt/epub 文件，也可以是网页章节，阅读时
/// 由网页读取器识别目录和正文。
class RssBookClient extends DirectLinkBookClient {
  RssBookClient(
    super.config, {
    List<String>? sources,
    List<CloudBookSource>? sourceEntries,
    this.onSourceDone,
  }) : _override = sources,
       _entriesOverride = sourceEntries;

  static const _maxSources = maxBookSources;
  static const _maxEntries = 500;
  final List<String>? _override;
  final List<CloudBookSource>? _entriesOverride;
  final void Function()? onSourceDone;
  final Completer<void> _sourcesDone = Completer<void>();

  /// 搜索提前返回首批结果时，进度条仍要等所有书源完成/超时后再收起。
  Future<void> get sourcesDone => _sourcesDone.future;

  /// 书源越多，单次搜索需要的时间越长；不能用固定 8 秒把 1000 个书源
  /// 只跑到前 200 个就收掉进度条。
  Duration get searchBudget {
    final count = _sourceObjects.length;
    if (count >= 500) return const Duration(seconds: 30);
    if (count >= 200) return const Duration(seconds: 20);
    if (count >= 50) return const Duration(seconds: 12);
    return const Duration(seconds: 8);
  }

  List<CloudBookSource> get _sourceObjects {
    if (_entriesOverride case final entries?) {
      return entries.take(_maxSources).toList(growable: false);
    }
    if (_override case final urls?) {
      return urls
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => CloudBookSource(url: value))
          .take(_maxSources)
          .toList(growable: false);
    }
    return config.effectiveSources.take(_maxSources).toList(growable: false);
  }

  List<String> get _sources => [
    for (final source in _sourceObjects)
      if (!source.isLegado) source.url,
  ];

  Future<void> _parallel<T>(
    List<T> sources,
    Future<void> Function(T source) action, {
    int workers = 8,
    void Function()? onDone,
  }) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= sources.length) return;
        await action(sources[index]);
        onDone?.call();
      }
    }

    await Future.wait([
      for (var i = 0; i < sources.length && i < workers; i++) worker(),
    ]);
  }

  /// 体检单个书源：能解析出至少一本书或一个目录才算有效。
  Future<CloudBookSourceProbe> probe(
    String source, {
    CloudBookSource? entry,
  }) async {
    final object =
        entry ?? _sourceObjects.where((item) => item.url == source).firstOrNull;
    if (object != null && LegadoReader.supports(object)) {
      try {
        final listing = await LegadoReader.search(
          object,
          '测试',
          allowHttp: config.allowHttp,
          cookie: config.cookie,
          authorization: authHeaders[HttpHeaders.authorizationHeader] ?? '',
        ).timeout(const Duration(seconds: 15));
        if (listing.entries.isNotEmpty) {
          return CloudBookSourceProbe(
            valid: true,
            message: 'Legado 规则识别到 ${listing.entries.length} 本书',
            books: listing.entries.length,
          );
        }
        return const CloudBookSourceProbe(
          valid: false,
          message: 'Legado 规则没有识别到书籍',
        );
      } catch (error) {
        return CloudBookSourceProbe(
          valid: false,
          message: cloudFailureMessage(error),
        );
      }
    }
    final target = source
        .replaceAll('{query}', Uri.encodeQueryComponent('测试'))
        .replaceAll('{page}', '1');
    try {
      final entries = await _entriesFor(
        target,
        page: 1,
      ).timeout(const Duration(seconds: 12));
      if (entries.isNotEmpty) {
        return CloudBookSourceProbe(
          valid: true,
          message: '识别到 ${entries.length} 本书',
        );
      }
      return const CloudBookSourceProbe(valid: false, message: '没有识别到书籍或目录');
    } catch (error) {
      return CloudBookSourceProbe(
        valid: false,
        message: cloudFailureMessage(error),
      );
    }
  }

  @override
  Future<CloudBookListing> list(String folder, {int page = 1}) async {
    if (page > 1 && !_sources.any((source) => source.contains('{page}'))) {
      return const CloudBookListing([]);
    }
    final entries = <String, CloudBookEntry>{};
    var attempted = 0;
    Object? lastFailure;
    final browse = _sources
        .where((source) => !source.contains('{query}'))
        .toList();
    await _parallel(browse, (source) async {
      attempted++;
      try {
        for (final entry in await _entriesFor(source, page: page)) {
          entries.putIfAbsent(entry.id, () => entry);
          if (entries.length >= _maxEntries) return;
        }
      } catch (error) {
        lastFailure = error;
        // 一个书源失效不影响其他书源。
      }
    });
    if (entries.isEmpty && attempted > 0 && lastFailure != null) {
      throw lastFailure!;
    }
    return CloudBookListing(entries.values.toList(growable: false));
  }

  @override
  Future<CloudBookListing> search(String query, {int page = 1}) async {
    final value = query.trim();
    if (value.isEmpty) return const CloudBookListing([]);
    final entries = <String, CloudBookEntry>{};
    final pattern = BookSearch(value);
    var attempted = 0;
    Object? firstFailure;
    final completer = Completer<CloudBookListing>();
    var stopped = false;
    void finish() {
      if (stopped) return;
      stopped = true;
      if (entries.isEmpty && attempted > 0 && firstFailure != null) {
        completer.completeError(firstFailure!);
      } else {
        completer.complete(
          CloudBookListing(entries.values.toList(growable: false)),
        );
      }
    }

    // 书源搜索全是独立 HTTP 请求。原来的 8 个并发配 276 个书源会让
    // 搜索串行排到几分钟；提高到 32 路，8 秒内先把已经返回的条目交给
    // 页面，单个坏源不再拖住整次搜索。
    final sourceTasks =
        _parallel(
          _sourceObjects,
          (source) async {
            if (stopped) return;
            attempted++;
            if (LegadoReader.supports(source)) {
              try {
                final listing = await LegadoReader.search(
                  source,
                  value,
                  page: page,
                  allowHttp:
                      config.allowHttp ||
                      source.url.trim().toLowerCase().startsWith('http://'),
                  cookie: config.cookie,
                  authorization:
                      authHeaders[HttpHeaders.authorizationHeader] ?? '',
                ).timeout(const Duration(seconds: 6));
                for (final entry in listing.entries) {
                  if (stopped) return;
                  entries.putIfAbsent(entry.id, () => entry);
                  if (entries.length >= _maxEntries) return;
                }
              } catch (error) {
                firstFailure ??= error;
                // 一个 Legado 书源规则失效不影响其它书源。
              }
              return;
            }
            final sourceUrl = source.url;
            final hasQuery = sourceUrl.contains('{query}');
            final target = sourceUrl
                .replaceAll('{query}', Uri.encodeQueryComponent(value))
                .replaceAll('{page}', '$page');
            try {
              final pageEntries = await _entriesFor(
                target,
                page: page,
              ).timeout(const Duration(seconds: 6));
              for (final entry in pageEntries) {
                if (stopped) return;
                final matches = hasQuery
                    ? true
                    : pattern.matches(
                        title: entry.name,
                        author: entry.author,
                        tags: '',
                        summary: entry.summary,
                        id: entry.id,
                      );
                if (!matches) continue;
                entries.putIfAbsent(entry.id, () => entry);
                if (entries.length >= _maxEntries) return;
              }
            } catch (error) {
              firstFailure ??= error;
              // 一个书源失效不影响其他书源。
            }
          },
          workers: 32,
          onDone: onSourceDone,
        ).whenComplete(() {
          if (!_sourcesDone.isCompleted) _sourcesDone.complete();
          finish();
        });
    unawaited(sourceTasks);
    final timer = Timer(searchBudget, () {
      if (!_sourcesDone.isCompleted) _sourcesDone.complete();
      finish();
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }

  Future<List<CloudBookEntry>> _entriesFor(
    String source, {
    required int page,
  }) async {
    final target = source.replaceAll('{page}', '$page');
    final uri = Uri.tryParse(target);
    if (uri == null) throw const CloudSourceFailure('小说书源地址无效');
    final allowHttp =
        config.allowHttp || target.trim().toLowerCase().startsWith('http://');
    CloudHttp.validateUrl(uri, allowHttp: allowHttp);

    final segments = uri.pathSegments.where((value) => value.isNotEmpty);
    final last = segments.isEmpty ? '' : Uri.decodeComponent(segments.last);
    if (supportsBookImport(last)) {
      return [
        CloudBookEntry(
          id: target,
          name: last,
          folder: false,
          size: 0,
          book: true,
        ),
      ];
    }

    final res = await _http.request(
      'GET',
      uri,
      headers: (requested) => {
        'Accept':
            'application/rss+xml, application/atom+xml, application/json, '
            'application/xml, text/xml, text/html, */*',
        if (CloudHttp.sameOrigin(requested, uri)) ...authHeaders,
      },
      redirects: true,
      allowHttp: allowHttp,
      redirectMessage: '书源地址发生跳转，请填写最终地址',
    );
    final bytes = await _http.bytes(res, limit: 6 * 1024 * 1024);
    final body = WebNovelReader.decodeBytes(
      bytes,
      res.headers.contentType,
    ).trim();
    if (body.startsWith('{') || body.startsWith('[')) {
      return _jsonEntries(body, uri);
    }
    if (body.startsWith('<')) {
      final document = XmlDocument.parse(body);
      final entries = _feedEntries(document, uri);
      if (entries.isNotEmpty) return entries;
      // XML 目录页（例如 sitemap）也允许按链接识别。
      return WebNovelReader.catalogFromHtml(body, uri).entries.toList();
    }
    return WebNovelReader.catalogFromHtml(body, uri).entries.toList();
  }

  List<CloudBookEntry> _feedEntries(XmlDocument document, Uri base) {
    final items = document.findAllElements('item');
    final entries = document.findAllElements('entry');
    final result = <CloudBookEntry>[];
    void add(
      String title,
      String? link,
      String summary, [
      String author = '',
      String cover = '',
    ]) {
      if (title.trim().isEmpty || link == null || link.trim().isEmpty) return;
      final resolved = base.resolve(link.trim()).toString();
      if (result.any((entry) => entry.id == resolved)) return;
      final coverUrl = cover.trim().isEmpty
          ? null
          : base.resolve(cover.trim()).toString();
      result.add(
        CloudBookEntry(
          id: resolved,
          name: title.trim(),
          folder: false,
          size: 0,
          author: author.trim(),
          summary: summary.trim(),
          coverUrl: coverUrl,
          book: true,
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
      add(title, link, _child(item, 'description'), author, _feedCover(item));
    }
    for (final item in entries) {
      final title = _child(item, 'title');
      String link = '';
      for (final node in item.findElements('link')) {
        final rel = node.getAttribute('rel')?.trim().toLowerCase();
        if (rel != null && rel != '' && rel != 'alternate') continue;
        final href = node.getAttribute('href');
        if (href != null && href.trim().isNotEmpty) {
          link = href;
          break;
        }
      }
      final author = _child(item, 'author').isNotEmpty
          ? _child(item, 'author')
          : _child(item, 'dc:creator');
      add(title, link, _child(item, 'summary'), author, _feedCover(item));
    }
    return result;
  }

  /// RSS 的封面通常藏在 enclosure、media:thumbnail、media:content 或
  /// image 节点里，不在 description 里。搜索阶段直接带上，避免用户看到
  /// 一排没有封面的结果。
  String _feedCover(XmlElement item) {
    for (final node in item.descendants.whereType<XmlElement>()) {
      final name = node.name.local.toLowerCase();
      final type = node.getAttribute('type')?.toLowerCase() ?? '';
      final medium = node.getAttribute('medium')?.toLowerCase() ?? '';
      final url =
          node.getAttribute('url') ??
          node.getAttribute('href') ??
          node.getAttribute('src') ??
          '';
      if (url.trim().isEmpty) continue;
      final looksImage =
          type.startsWith('image') ||
          medium == 'image' ||
          name == 'thumbnail' ||
          name == 'cover' ||
          name == 'image' ||
          RegExp(
            r'\.(?:jpg|jpeg|png|webp|gif|avif)(?:$|\?)',
            caseSensitive: false,
          ).hasMatch(url);
      if (looksImage) return url.trim();
    }
    for (final key in ['cover', 'coverUrl', 'image', 'thumbnail']) {
      final value = _child(item, key);
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  List<CloudBookEntry> _jsonEntries(String body, Uri base) {
    Object? value;
    try {
      value = jsonDecode(body);
    } catch (_) {
      throw const CloudSourceFailure('这个 JSON 书源格式无法识别');
    }
    final root = value is List
        ? value
        : value is Map
        ? (value['items'] ??
              value['data'] ??
              value['books'] ??
              value['list'] ??
              value['results'])
        : null;
    if (root is! List) throw const CloudSourceFailure('这个 JSON 书源里没有书籍列表');
    final result = <CloudBookEntry>[];
    for (final item in root) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final title = _string(map, ['title', 'name', 'bookName', 'book_name']);
      final link = _string(map, [
        'url',
        'link',
        'bookUrl',
        'book_url',
        'href',
        'external_url',
      ]);
      if (title.isEmpty || link.isEmpty) continue;
      final resolved = base.resolve(link).toString();
      final author = _string(map, ['author', 'author_name', 'authors']);
      final summary = _string(map, [
        'summary',
        'description',
        'intro',
        'content_text',
        'content_html',
      ]);
      final cover = _string(map, [
        'cover',
        'coverUrl',
        'cover_url',
        'image',
        'thumbnail',
        'pic',
      ]);
      if (result.any((entry) => entry.id == resolved)) continue;
      result.add(
        CloudBookEntry(
          id: resolved,
          name: title,
          folder: false,
          size: 0,
          author: author,
          summary: summary,
          coverUrl: cover.isEmpty ? null : base.resolve(cover).toString(),
          book: true,
        ),
      );
      if (result.length >= _maxEntries) break;
    }
    if (result.isEmpty) throw const CloudSourceFailure('这个 JSON 书源里没有可阅读条目');
    return result;
  }

  String _string(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        final text = value.trim();
        return text.length <= 1200 ? text : '${text.substring(0, 1200)}…';
      }
      if (value is List) {
        final names = [
          for (final item in value)
            if (item is String && item.trim().isNotEmpty)
              item.trim()
            else if (item is Map && item['name'] is String)
              (item['name'] as String).trim(),
        ].where((name) => name.isNotEmpty);
        if (names.isNotEmpty) return names.join('、');
      }
      if (value is Map && value['name'] is String) {
        final name = (value['name'] as String).trim();
        if (name.isNotEmpty) return name;
      }
    }
    return '';
  }

  String _child(XmlElement item, String name) {
    for (final node in item.findElements(name)) {
      return node.innerText.trim();
    }
    return '';
  }
}
