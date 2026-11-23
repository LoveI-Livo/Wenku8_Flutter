import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'app_ui.dart';
import 'book_source_manager_page.dart';
import 'app_interactions.dart';
import 'catalog.dart';
import 'cloud_sources.dart';
import 'cloud_catalog_search.dart';
import 'cloud_parse_page.dart';
import 'offline_cache.dart' show formatCacheBytes;
import 'source_login_page.dart';

typedef ImportCloudBook = Future<Novel> Function(String name, String path);
typedef AddCloudBook =
    Future<void> Function(
      CloudBookEntry entry,
      CloudSourceConfig config,
      String? groupId,
    );
typedef AddCloudShelf =
    Future<void> Function(CloudBookEntry entry, CloudSourceConfig config);
typedef ImportCloudBatch =
    Future<({int imported, int failed})> Function(String name, String path);
typedef ReadCloudBook =
    Future<void> Function(
      BuildContext context,
      CloudBookEntry entry,
      CloudSourceConfig config,
    );

class CloudLibraryPage extends StatelessWidget {
  const CloudLibraryPage({
    super.key,
    required this.settings,
    required this.onImport,
    this.onImportBatch,
    this.onAddCloud,
    this.onAddShelf,
    this.onReadCloud,
    this.booklists = const {},
    this.reduceMotion = false,
  });
  final CloudSourceSettings settings;
  final ImportCloudBook onImport;
  final ImportCloudBatch? onImportBatch;
  final AddCloudBook? onAddCloud;
  final AddCloudShelf? onAddShelf;
  final ReadCloudBook? onReadCloud;
  final Map<String, String> booklists;
  final bool reduceMotion;
  Future<void> _edit(BuildContext context, CloudSourceKind kind) async {
    final config = await pushNovelPage<CloudSourceConfig>(
      context,
      CloudConnectionPage(settings: settings, kind: kind),
      reduceMotion: reduceMotion,
    );
    if (context.mounted && config != null) {
      await CloudCatalogSearch.instance.reload();
      if (context.mounted) await _browse(context, config);
    }
  }

  Future<void> _loginAccount(BuildContext context, CloudSourceKind kind) async {
    final address = kind == CloudSourceKind.quark
        ? 'https://pan.quark.cn/'
        : 'https://pc.woozooo.com/mydisk.php?item=files&action=index';
    final cookie = await pushNovelPage<String>(
      context,
      SourceLoginPage(
        address: address,
        title: kind == CloudSourceKind.quark ? '登录夸克网盘' : '登录蓝奏云',
        autoCookieNames: kind == CloudSourceKind.quark
            ? const ['__puus']
            : const ['phpdisk_info'],
      ),
      reduceMotion: reduceMotion,
    );
    if (cookie == null || !context.mounted) return;
    try {
      final config = CloudSourceConfig(kind: kind, cookie: cookie);
      config.validate();
      await settings.save(kind, config);
      await CloudCatalogSearch.instance.reload();
      if (context.mounted) await _browse(context, config);
    } catch (error) {
      if (context.mounted)
        showNovelFeedback(context, cloudFailureMessage(error));
    }
  }

  Future<void> _browse(BuildContext context, CloudSourceConfig config) =>
      pushNovelPage<void>(
        context,
        CloudBookBrowser(
          config: config,
          settings: settings,
          onImport: onImport,
          onImportBatch: onImportBatch,
          onAddCloud: onAddCloud,
          onAddShelf: onAddShelf,
          onReadCloud: onReadCloud,
          booklists: booklists,
        ),
        reduceMotion: reduceMotion,
      );
  @override
  Widget build(BuildContext context) => _CloudScaffold(
    title: '网盘在线阅读',
    code: 'ONLINE / CLOUD SOURCES',
    child: AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ArchiveSection(title: '网盘与小说书源', code: 'BOOKS / DOCUMENTS / SOURCES'),
          const SizedBox(height: 12),
          const AppText(
            '点账号登录后直接浏览网盘；点书即在线读取，只把正文读进内存，'
            '不下载到本机。小说书源支持 RSS、Atom、JSON 和网页目录，'
            '可一行填多个地址；主搜索框切到“书源搜索”可检索全部已配置书源。',
            style: TextStyle(fontSize: 13, height: 1.65),
          ),
          const SizedBox(height: 18),
          CloudParseCard(reduceMotion: reduceMotion),
          const SizedBox(height: 24),
          if (settings.error != null)
            AppText(
              settings.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final kind in CloudSourceKind.values) ...[
            ContentPanel(
              key: ValueKey('cloud-source-${kind.name}'),
              onTap: !kind.isWebLogin
                  ? null
                  : settings[kind] == null
                  ? () => _loginAccount(context, kind)
                  : () => _browse(context, settings[kind]!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          kind == CloudSourceKind.quark
                              ? '夸克网盘 · 扫码登录'
                              : kind == CloudSourceKind.lanzou
                              ? '蓝奏云 · 账号登录'
                              : kind.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ArchiveIcon(
                        kind != CloudSourceKind.quark
                            ? CupertinoIcons.cloud
                            : CupertinoIcons.folder,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AppText(switch (kind) {
                    CloudSourceKind.webdav =>
                      '连接 OpenList、AList、NAS 或其他 WebDAV 服务。百度网盘等可先在 OpenList 挂载。',
                    CloudSourceKind.quark =>
                      '点账号打开夸克官网，扫码或验证码登录后自动保存会话，直接浏览全盘并参与全局搜索。',
                    CloudSourceKind.s3 => '连接 Amazon S3 或 S3 兼容存储，按文件夹浏览并导入书籍。',
                    CloudSourceKind.lanzou =>
                      '点账号打开蓝奏云官网登录，自动保存 Cookie，直接浏览账号全部文件夹并参与全局搜索。',
                    CloudSourceKind.lanzouPro =>
                      '蓝奏云优享版暂按直链读取；普通版已支持账号登录和全盘搜索。',
                    CloudSourceKind.xunlei => '迅雷云盘：复制文件的下载直链，流式读取，不经过本地下载目录。',
                    CloudSourceKind.aliyun => '阿里云盘：复制分享文件的下载直链，流式读取。',
                    CloudSourceKind.baidu => '百度网盘：复制文件的下载直链（需带有效签名）。',
                    CloudSourceKind.pan123 => '123 云盘：复制文件下载直链，流式读取。',
                    CloudSourceKind.uc => 'UC 网盘：复制文件下载直链，流式读取。',
                    CloudSourceKind.direct =>
                      '任意 HTTPS 文件直链，粘贴后直接流式读取，不保存账号 Cookie。',
                    CloudSourceKind.rss =>
                      '小说书源：支持 RSS / Atom / JSON Feed / JSON 列表和普通网页目录。一行一个地址，最多 12 个；带 {query} 或 {page} 的地址会按关键词和页码替换。',
                  }, style: const TextStyle(fontSize: 13, height: 1.65)),
                  const SizedBox(height: 12),
                  if (settings[kind] case final config?) ...[
                    AppText(
                      switch (kind) {
                        CloudSourceKind.quark => '已登录夸克账号 · 可浏览全盘',
                        CloudSourceKind.lanzou when config.cookie.isNotEmpty =>
                          '已登录蓝奏云账号 · 可浏览全盘',
                        _ => '已保存直链',
                      },
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GlassPillButton(
                      key: ValueKey('cloud-browse-${kind.name}'),
                      icon: CupertinoIcons.folder_open,
                      label: kind.isWebLogin
                          ? '浏览全盘'
                          : kind.isAccount
                          ? '浏览文件夹'
                          : '浏览书籍',
                      onPressed: () => _browse(context, config),
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        GlassTextButton(
                          onPressed: kind.isWebLogin
                              ? () => _loginAccount(context, kind)
                              : () => _edit(context, kind),
                          child: AppText(kind.isWebLogin ? '重新登录' : '修改连接'),
                        ),
                        if (kind == CloudSourceKind.rss)
                          GlassTextButton(
                            key: const ValueKey('cloud-rss-manager'),
                            onPressed: () => pushNovelPage<void>(
                              context,
                              BookSourceManagerPage(settings: settings),
                              reduceMotion: reduceMotion,
                            ),
                            child: const AppText('书源管理 / 检测'),
                          ),
                        GlassTextButton(
                          onPressed: () async {
                            try {
                              await settings.save(kind, null);
                              await CloudCatalogSearch.instance.reload();
                            } catch (e) {
                              if (context.mounted) {
                                showNovelFeedback(
                                  context,
                                  cloudFailureMessage(e),
                                );
                              }
                            }
                          },
                          child: const AppText('移除连接'),
                        ),
                      ],
                    ),
                  ] else
                    GlassPillButton(
                      key: ValueKey('cloud-add-${kind.name}'),
                      icon: CupertinoIcons.plus,
                      label: switch (kind) {
                        CloudSourceKind.webdav => '添加 WebDAV 连接',
                        CloudSourceKind.quark => '登录夸克网盘',
                        CloudSourceKind.lanzou => '登录蓝奏云',
                        CloudSourceKind.lanzouPro ||
                        CloudSourceKind.xunlei ||
                        CloudSourceKind.aliyun ||
                        CloudSourceKind.baidu ||
                        CloudSourceKind.pan123 ||
                        CloudSourceKind.uc ||
                        CloudSourceKind.direct => '添加直链',
                        CloudSourceKind.rss => '添加小说书源',
                        CloudSourceKind.s3 => '添加 S3 连接',
                      },
                      onPressed: kind.isWebLogin
                          ? () => _loginAccount(context, kind)
                          : () => _edit(context, kind),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    ),
  );
}

class CloudConnectionPage extends StatefulWidget {
  const CloudConnectionPage({
    super.key,
    required this.settings,
    required this.kind,
    this.syncConnection = false,
  }) : assert(!syncConnection || kind == CloudSourceKind.s3);
  final CloudSourceSettings settings;
  final CloudSourceKind kind;
  final bool syncConnection;
  @override
  State<CloudConnectionPage> createState() => _CloudConnectionPageState();
}

class _CloudConnectionPageState extends State<CloudConnectionPage> {
  final _address = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController(),
      _cookie = TextEditingController();
  final _bucket = TextEditingController(),
      _region = TextEditingController(),
      _prefix = TextEditingController(),
      _token = TextEditingController(),
      _syncPath = TextEditingController();
  bool _pathStyle = true;
  bool _http = false, _busy = false;
  String? _error;
  CloudBookClient? _testing;
  @override
  void initState() {
    super.initState();
    final savedSync = widget.syncConnection ? widget.settings.s3Sync : null;
    final config = savedSync?.config ?? widget.settings[widget.kind];
    _address.text = config?.address ?? '';
    _user.text = config?.username ?? '';
    _password.text = config?.password ?? '';
    _cookie.text = config?.cookie ?? '';
    _http = config?.allowHttp ?? false;
    _bucket.text = config?.bucket ?? '';
    _region.text = config?.region ?? 'us-east-1';
    _prefix.text = config?.prefix ?? '';
    _token.text = config?.sessionToken ?? '';
    _pathStyle = config?.pathStyle ?? true;
    _syncPath.text = savedSync?.path ?? 'wenku8/library.wenku8sync';
  }

  @override
  void dispose() {
    _testing?.close();
    for (final c in [
      _address,
      _user,
      _password,
      _cookie,
      _bucket,
      _region,
      _prefix,
      _token,
      _syncPath,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _webLogin({
    String? address,
    List<String> autoCookieNames = const [],
    String title = '登录书源',
  }) async {
    final target = (address ?? _address.text)
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      setState(() => _error = '请先填写书源或网站地址，再打开网页登录');
      return;
    }
    final cookie = await Navigator.of(context).push<String>(
      CupertinoPageRoute(
        builder: (_) => SourceLoginPage(
          address: target,
          title: title,
          autoCookieNames: autoCookieNames,
        ),
      ),
    );
    if (cookie != null && mounted) {
      setState(() => _cookie.text = cookie);
    }
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var config = CloudSourceConfig(
        kind: widget.kind,
        address: _address.text.trim(),
        username: _user.text.trim(),
        password: _password.text,
        cookie: _cookie.text.trim(),
        allowHttp: _http,
        bucket: _bucket.text.trim(),
        region: _region.text.trim(),
        prefix: _prefix.text.trim(),
        sessionToken: _token.text.trim(),
        pathStyle: _pathStyle,
      );
      config.validate();
      if (widget.syncConnection) {
        final connection = S3SyncConnection(
          config: config,
          path: _syncPath.text.trim(),
        );
        connection.validate();
        await widget.settings.saveS3Sync(connection);
        if (mounted) Navigator.pop(context, config);
        return;
      }
      final client = _testing = CloudBookClient(config);
      await client.list(client.root);
      if (client is QuarkBookClient) config = client.config;
      if (!mounted) return;
      await widget.settings.save(widget.kind, config);
      if (mounted) Navigator.pop(context, config);
    } catch (e) {
      if (mounted) setState(() => _error = cloudFailureMessage(e));
    } finally {
      _testing?.close();
      _testing = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    String? helper,
    bool secret = false,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        CupertinoTextField(
          key: ValueKey('cloud-field-$label'),
          onTap: () => AppHaptics.play(context, HapticCue.selection),
          onSubmitted: (_) => AppHaptics.play(context, HapticCue.action),
          controller: controller,
          enabled: !_busy,
          placeholder: hint,
          obscureText: secret,
          maxLines: secret ? 1 : maxLines,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: label.contains('地址')
              ? TextInputType.url
              : TextInputType.text,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .045),
            borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 7),
          AppText(
            helper,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => _CloudScaffold(
    title: widget.syncConnection ? 'S3 云端同步' : '连接 ${widget.kind.label}',
    code: widget.syncConnection ? 'LIBRARY / S3 SYNC' : 'LOCAL / CONNECTION',
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.kind.isDirectLink) ...[
              AppText(
                widget.kind == CloudSourceKind.rss
                    ? '填写小说书源地址，一行一个，最多 12 个。支持 RSS、Atom、'
                          'JSON Feed、JSON 列表和普通网页目录；网页里的章节会按目录和正文自动识别。'
                          '搜索地址可以用 {query} 代表关键词、{page} 代表页码。'
                    : '在${widget.kind.label}网页复制文件的下载直链（https 开头、带 sign 参数的地址），粘贴到下方。'
                          '应用会直接流式读取，不保存账号 Cookie，也不会把整本书长期留在本机。'
                          '蓝奏云普通版与优享版域名不同，请复制带真实文件名的下载地址，不要粘贴分享页。',
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 24),
              _field(
                widget.kind == CloudSourceKind.rss ? '小说书源地址（一行一个）' : '文件直链',
                _address,
                maxLines: widget.kind == CloudSourceKind.rss ? 6 : 1,
                hint: widget.kind == CloudSourceKind.rss
                    ? 'https://example.com/feed.xml\nhttps://example.com/search?q={query}&page={page}'
                    : 'https://wwx.lanzoui.com/… 或迅雷直链',
                helper: widget.kind == CloudSourceKind.rss
                    ? '支持 RSS / Atom / JSON / 网页目录；一行一个，最多 12 个。'
                    : '分享页地址不是直链；请在下载按钮上右键或长按复制真实下载地址。',
              ),
              GlassTextButton(
                key: const ValueKey('cloud-web-login'),
                onPressed: _busy ? null : _webLogin,
                child: const AppText('网页登录并自动获取 Cookie'),
              ),
              const SizedBox(height: 12),
              if (widget.kind == CloudSourceKind.rss)
                _field(
                  '登录 Cookie（可选）',
                  _cookie,
                  hint: 'sessionid=…; token=…',
                  secret: true,
                  helper: '需要登录的书源可填；公开订阅和网页可以留空。Cookie 会随书架记录保存在本机。',
                ),
              _field('用户名（Basic 登录，可选）', _user),
              _field('密码', _password, secret: true),
              Row(
                children: [
                  const Expanded(child: AppText('允许 HTTP 直链')),
                  AppControls.toggle(
                    context,
                    value: _http,
                    onChanged: _busy ? null : (v) => setState(() => _http = v),
                  ),
                ],
              ),
            ] else if (widget.kind == CloudSourceKind.webdav) ...[
              const AppText(
                'OpenList 地址一般以 /dav/ 结尾。账号需要 WebDAV 读取权限。',
                style: TextStyle(height: 1.65),
              ),
              const SizedBox(height: 24),
              _field('WebDAV 地址', _address, hint: 'https://你的域名/dav/'),
              _field('用户名', _user),
              _field('密码', _password, secret: true),
              Row(
                children: [
                  const Expanded(child: AppText('允许 HTTP 连接')),
                  AppControls.toggle(
                    context,
                    value: _http,
                    onChanged: _busy ? null : (v) => setState(() => _http = v),
                  ),
                ],
              ),
              AnimatedOptionSection(
                expanded: _http,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: AppText(
                    'HTTP 不加密传输账号和书籍，仅在可信局域网中使用。',
                    style: TextStyle(height: 1.6),
                  ),
                ),
              ),
            ] else if (widget.kind == CloudSourceKind.s3) ...[
              AppText(
                widget.syncConnection
                    ? '两台设备填写相同的桶与同步文件路径。同步需要读取、写入此文件的权限，只有点按「立即同步」才会传输。'
                    : '填写存储服务的 Endpoint 和桶名。连接只需列目录、读取对象的权限。',
                style: const TextStyle(height: 1.65),
              ),
              const SizedBox(height: 24),
              _field(
                'Endpoint 地址',
                _address,
                hint: 'https://s3.us-east-1.amazonaws.com',
              ),
              _field('存储桶 Bucket', _bucket),
              _field('区域 Region', _region, hint: 'us-east-1'),
              _field('Access Key ID', _user),
              _field('Secret Access Key', _password, secret: true),
              _field('目录前缀（可选）', _prefix, hint: 'books/'),
              if (widget.syncConnection)
                _field(
                  '同步文件路径',
                  _syncPath,
                  hint: 'wenku8/library.wenku8sync',
                  helper: '位于目录前缀内；使用独立的 .wenku8sync 文件。',
                ),
              _field('Session Token（可选）', _token, secret: true),
              Row(
                children: [
                  const Expanded(child: AppText('路径式寻址')),
                  AppControls.toggle(
                    context,
                    value: _pathStyle,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _pathStyle = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: AppText('允许 HTTP 连接')),
                  AppControls.toggle(
                    context,
                    value: _http,
                    onChanged: _busy ? null : (v) => setState(() => _http = v),
                  ),
                ],
              ),
              AnimatedOptionSection(
                expanded: _http,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: AppText(
                    'HTTP 不加密传输连接信息和书籍，仅在可信局域网中使用。',
                    style: TextStyle(height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const AppText(
                '凭据只保存在本机加密存储，不写入阅读备份。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ] else ...[
              const AppText(
                '在电脑登录 pan.quark.cn，打开开发者工具的「网络」，复制网盘请求中的 Cookie 请求头。只填写 Cookie 的值。',
                style: TextStyle(height: 1.7),
              ),
              const SizedBox(height: 24),
              GlassTextButton(
                key: const ValueKey('cloud-quark-web-login'),
                onPressed: _busy
                    ? null
                    : () => _webLogin(
                        address: 'https://pan.quark.cn/',
                        autoCookieNames: const ['__puus'],
                        title: '登录夸克网盘',
                      ),
                child: const AppText('网页扫码 / 验证码登录，自动获取 Cookie'),
              ),
              const SizedBox(height: 8),
              const AppText(
                '在夸克官网完成扫码或验证码登录，页面识别到登录成功后自动返回，'
                '不需要手动复制 Cookie。',
                style: TextStyle(fontSize: 12, height: 1.55),
              ),
              const SizedBox(height: 20),
              _field(
                'Cookie',
                _cookie,
                hint: '__pus=…; __puus=…',
                secret: true,
              ),
              const AppText(
                '登录凭据仅加密保存在这台设备。导入只读取文件，不移动或删除网盘内容。',
                style: TextStyle(height: 1.65),
              ),
            ],
            const SizedBox(height: 20),
            if (_busy)
              BookRowSkeleton(
                label: widget.syncConnection ? '正在保存同步连接' : '正在检查目录读取权限',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AppText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            GlassPillButton(
              key: const ValueKey('cloud-connect'),
              icon: CupertinoIcons.link,
              label: _busy
                  ? widget.syncConnection
                        ? '正在保存'
                        : '正在连接'
                  : widget.syncConnection
                  ? '保存同步连接'
                  : '连接并浏览',
              onPressed: _busy ? null : _connect,
            ),
            if (_busy && !widget.syncConnection)
              GlassTextButton(
                onPressed: () => _testing?.cancel(),
                child: const AppText('取消连接'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CloudEntryArt extends StatelessWidget {
  const _CloudEntryArt({required this.entry});
  final CloudBookEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.folder) {
      return Container(
        width: 42,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF2F6FEB).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          CupertinoIcons.folder_fill,
          color: Color(0xFF2F6FEB),
          size: 24,
        ),
      );
    }
    final extension = entry.name.contains('.')
        ? entry.name.split('.').last.toUpperCase()
        : 'FILE';
    final (icon, color) = switch (extension) {
      'EPUB' ||
      'MOBI' ||
      'AZW' ||
      'AZW3' => (CupertinoIcons.book_fill, const Color(0xFF8A5CF6)),
      'PDF' => (CupertinoIcons.doc_plaintext, const Color(0xFFE05B4F)),
      'DOC' ||
      'DOCX' ||
      'ODT' => (CupertinoIcons.doc_plaintext, const Color(0xFFE08A3C)),
      'FB2' => (CupertinoIcons.book, const Color(0xFF7D5BBE)),
      'RTF' => (CupertinoIcons.doc_text, const Color(0xFF9A7B4F)),
      'TXT' ||
      'MD' ||
      'MARKDOWN' ||
      'HTML' ||
      'HTM' ||
      'XHTML' => (CupertinoIcons.doc_text, const Color(0xFF3A8F68)),
      'ZIP' ||
      'RAR' ||
      '7Z' => (CupertinoIcons.archivebox_fill, const Color(0xFFB07A35)),
      'JPG' ||
      'JPEG' ||
      'PNG' ||
      'WEBP' => (CupertinoIcons.photo_fill, const Color(0xFF2980B9)),
      _ => (CupertinoIcons.doc, const Color(0xFF5D6D7E)),
    };
    return Container(
      width: 42,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.22), color.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 2),
          Text(
            extension,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class CloudBookBrowser extends StatefulWidget {
  const CloudBookBrowser({
    super.key,
    required this.config,
    required this.settings,
    required this.onImport,
    this.onImportBatch,
    this.onAddCloud,
    this.onAddShelf,
    this.onReadCloud,
    this.booklists = const {},
    this.client,
  });
  final CloudSourceConfig config;
  final CloudSourceSettings settings;
  final ImportCloudBook onImport;
  final ImportCloudBatch? onImportBatch;
  final AddCloudBook? onAddCloud;
  final AddCloudShelf? onAddShelf;
  final ReadCloudBook? onReadCloud;
  final Map<String, String> booklists;
  final CloudBookClient? client;
  @override
  State<CloudBookBrowser> createState() => _CloudBookBrowserState();
}

class _CloudBookBrowserState extends State<CloudBookBrowser> {
  late CloudBookClient _client;
  final _folders = <({String id, String name})>[];
  final _selected = <String, CloudBookEntry>{};
  final _imported = <String>{};
  final _addedToShelf = <String>{};
  String? _readingOnline;
  List<CloudBookEntry> _entries = [];
  int? _next;
  bool _loading = true,
      _searching = false,
      _importing = false,
      _cancelled = false,
      _committing = false,
      _batch = false;
  int _generation = 0, _received = 0;
  int? _total;
  String? _error, _current, _loadedFolder, _query;
  @override
  void initState() {
    super.initState();
    _client =
        widget.client ??
        CloudBookClient(widget.config, settings: widget.settings);
    _folders.add((id: _client.root, name: '全部文件'));
    _load();
  }

  @override
  void dispose() {
    _client.close();
    _generation++;
    super.dispose();
  }

  Future<void> _search(String query) async {
    final value = query.trim();
    if (value.isEmpty) {
      setState(() => _query = null);
      await _load();
      return;
    }
    final token = ++_generation;
    setState(() {
      _query = value;
      _searching = true;
      _loading = true;
      _error = null;
    });
    try {
      final matches = <String, CloudBookEntry>{};
      if (_client is RssBookClient) {
        final listing = await _client.search(value);
        for (final entry in listing.entries) {
          if (entry.isBook) matches[entry.id] = entry;
        }
      } else {
        final pending = <String>[_client.root];
        final visited = <String>{};
        var folders = 0;
        while (pending.isNotEmpty && folders < 120 && matches.length < 300) {
          if (!mounted || token != _generation) return;
          final folder = pending.removeAt(0);
          if (!visited.add(folder)) continue;
          folders++;
          try {
            final listing = await _client.list(folder);
            for (final entry in listing.entries) {
              if (entry.folder) {
                pending.add(entry.id);
              } else if (entry.isBook &&
                  (entry.name.toLowerCase().contains(value.toLowerCase()) ||
                      entry.author
                          .toLowerCase()
                          .contains(value.toLowerCase()) ||
                      entry.summary
                          .toLowerCase()
                          .contains(value.toLowerCase()))) {
                matches[entry.id] = entry;
              }
            }
          } catch (_) {
            // 个别子目录无权限时继续搜索其他目录。
          }
        }
      }
      if (!mounted || token != _generation) return;
      setState(() {
        _entries = matches.values.toList();
        _next = null;
      });
      if (matches.isEmpty) {
        showNovelFeedback(context, '没有搜到包含「$value」的书');
      }
    } catch (error) {
      if (mounted && token == _generation) {
        setState(() => _error = cloudFailureMessage(error));
      }
    } finally {
      if (mounted && token == _generation) {
        setState(() {
          _searching = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _load({bool more = false}) async {
    final token = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await _client.list(
        _folders.last.id,
        page: more ? _next! : 1,
      );
      if (!mounted || token != _generation) return;
      setState(() {
        final old = more ? _entries : <CloudBookEntry>[];
        final values = {
          for (final e in old) e.id: e,
          for (final e in listing.entries) e.id: e,
        };
        _entries = values.values.toList();
        _loadedFolder = _folders.last.id;
        _next = listing.nextPage;
      });
    } catch (e) {
      if (mounted && token == _generation) {
        setState(() => _error = cloudFailureMessage(e));
      }
    } finally {
      if (mounted && token == _generation) setState(() => _loading = false);
    }
  }

  void _enter(CloudBookEntry entry) {
    if (_importing || _loading) return;
    setState(() {
      _folders.add((id: entry.id, name: entry.name));
      _entries = [];
      _selected.clear();
      _batch = false;
      _next = null;
    });
    _load();
  }

  void _up() {
    if (_folders.length <= 1 || _importing) return;
    setState(() {
      _folders.removeLast();
      _entries = [];
      _selected.clear();
      _batch = false;
      _next = null;
    });
    _load();
  }

  Future<void> _readOnline(CloudBookEntry entry) async {
    final reader = widget.onReadCloud;
    if (reader == null || _importing || _loading || _readingOnline != null) {
      return;
    }
    setState(() => _readingOnline = entry.id);
    try {
      await reader(context, entry, widget.config);
    } catch (error) {
      if (mounted) showNovelFeedback(context, cloudFailureMessage(error));
    } finally {
      if (mounted) setState(() => _readingOnline = null);
    }
  }

  void _toggleBatch() {
    if (_importing) return;
    setState(() {
      _batch = !_batch;
      if (!_batch) _selected.clear();
    });
  }

  void _toggleSelection(CloudBookEntry entry) {
    if (_importing) return;
    setState(() {
      if (_selected.containsKey(entry.id)) {
        _selected.remove(entry.id);
      } else {
        _selected[entry.id] = entry;
      }
    });
  }

  /// 默认状态下点右侧圆圈就是一次明确的“加入书架”，不再让用户先勾选、
  /// 再回到页面顶部点按钮。批量模式仍保留在顶部统一操作。
  Future<void> _addShelfEntry(CloudBookEntry entry) async {
    final add = widget.onAddShelf;
    if (add == null) {
      _toggleSelection(entry);
      return;
    }
    if (_importing) return;
    setState(() => _importing = true);
    try {
      await add(entry, widget.config);
      if (!mounted) return;
      setState(() => _addedToShelf.add(entry.id));
      showNovelFeedback(
        context,
        '已加入书架 · ${widget.config.kind.label}，点开即在线阅读',
      );
    } catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          '加入书架未完成：${cloudFailureMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

Future<void> _import(List<CloudBookEntry> entries) async {
    if (_importing || entries.isEmpty) return;
    setState(() {
      _importing = true;
      _cancelled = false;
      _error = null;
    });
    var count = 0;
    var failed = 0;
    Directory? work;
    try {
      work = await Directory(
        '${(await getTemporaryDirectory()).path}/cloud-book-import',
      ).create(recursive: true);
      final batch = await work.createTemp('batch-');
      work = batch;
      for (final entry in entries) {
        if (!mounted || _cancelled) break;
        setState(() {
          _current = entry.name;
          _received = 0;
          _total = entry.size > 0 ? entry.size : null;
        });
        final file = File('${work.path}/book');
        try {
          await _client.download(
            entry,
            file,
            onProgress: (received, total) {
              // Throttle UI updates, not downloads or parsing, to avoid rebuilding
              // the glass list on every socket chunk.
              if (mounted &&
                  (received - _received >= 128 * 1024 || received == total)) {
                setState(() {
                  _received = received;
                  _total = total;
                });
              }
            },
          );
          if (!mounted || _cancelled) break;
          setState(() => _committing = true);
          var complete = true;
          if (widget.onImportBatch != null) {
            final batch = await widget.onImportBatch!(entry.name, file.path);
            count += batch.imported;
            failed += batch.failed;
            complete = batch.failed == 0;
          } else {
            await widget.onImport(entry.name, file.path);
            count++;
          }
          if (complete) {
            _selected.remove(entry.id);
            _imported.add(entry.id);
          }
        } finally {
          _committing = false;
          if (await file.exists()) await file.delete();
        }
      }
      if (mounted) {
        showNovelFeedback(
          context,
          _cancelled
              ? '已取消，已导入 $count 本'
              : failed > 0
              ? '已导入 $count 本 · $failed 本未导入，返回后可查看详情'
              : '已导入 $count 本，返回书库即可阅读',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${cloudFailureMessage(e)}${count > 0 ? ' · 已导入 $count 本' : ''}',
        );
      }
    } finally {
      if (work != null &&
          work.path.split('/').last.startsWith('batch-') &&
          await work.exists()) {
        await work.delete(recursive: true);
      }
      if (_cancelled) {
        _client = CloudBookClient(
          widget.settings[widget.config.kind] ?? widget.config,
          settings: widget.settings,
        );
      }
      if (mounted) {
        setState(() {
          _importing = false;
          _current = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_committing && _folders.length == 1,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_committing) _up();
    },
    child: _CloudScaffold(
      title: widget.config.label,
      code: 'LOCAL / FILE BROWSER',
      onBack: _folders.length > 1 ? _up : null,
      sliverBody: LoadedContentSequence(
        generation: _folders.last.id,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.paddingOf(context).top +
                    FrostedHeader.toolbarHeight +
                    20,
                24,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppText(
                            _folders.last.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GlassTextButton(
                          key: const ValueKey('cloud-batch-toggle'),
                          onPressed: _loading || _importing
                              ? null
                              : _toggleBatch,
                          child: AppText(_batch ? '完成' : '批量选择'),
                        ),
                        GlassIconButton(
                          icon: CupertinoIcons.refresh,
                          label: '刷新网盘目录',
                          onPressed: _loading || _importing
                              ? null
                              : () => _load(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppText(
                      widget.config.kind.isDirectLink
                          ? '点右侧圆圈直接加入书架；点“批量选择”后可勾选多本加入书单。搜索请用主界面并切到“网盘搜索”。'
                          : '点书在线读取，不下载到本机；点右侧圆圈直接加入书架。需要批量时点“批量选择”，勾选多本后统一加入书单或书架。搜索请用主界面并切到“网盘搜索”。',
                      style: const TextStyle(height: 1.65),
                    ),
                    const SizedBox(height: 16),
                    if (_importing) ...[
                      AppText(
                        _current == null
                            ? '正在识别书名、作者、简介和封面…'
                            : '正在导入 · $_current',
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 8),
                      if (_current != null) ...[
                        AppText(
                          _committing
                              ? '正在解析目录与插图'
                              : '${(_received / 1024).round()} KB${_total == null ? '' : ' / ${(_total! / 1024).round()} KB'}',
                        ),
                        GlassTextButton(
                          onPressed: _committing
                              ? null
                              : () {
                                  _cancelled = true;
                                  _client.cancel();
                                },
                          child: const AppText('取消导入'),
                        ),
                      ] else
                        const AppText(
                          '只读取文件信息，不会把原文件保存到本机。',
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                    ] else if (_batch && _selected.isNotEmpty) ...[
                      AppText(
                        '已选 ${_selected.length} 本',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.onAddShelf != null) ...[
                        GlassPillButton(
                          icon: CupertinoIcons.book,
                          label: '加入书架（不下载）',
                          onPressed: _importing
                              ? null
                              : () async {
                                  final selected = _selected.values.toList();
                                  setState(() => _importing = true);
                                  try {
                                    await Future.wait([
                                      for (final entry in selected)
                                        widget.onAddShelf!(
                                          entry,
                                          widget.config,
                                        ),
                                    ]);
                                    if (!mounted) return;
                                    setState(() {
                                      _selected.clear();
                                      _addedToShelf.addAll(
                                        selected.map((entry) => entry.id),
                                      );
                                    });
                                    showNovelFeedback(
                                      context,
                                      '已加入书架 · ${widget.config.kind.label}，点开即在线阅读',
                                    );
                                  } catch (_) {
                                    if (mounted) {
                                      showNovelFeedback(
                                        context,
                                        '加入书架未完成，请重试；已成功的书不会重复写入',
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _importing = false);
                                    }
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.onAddCloud != null) ...[
                        GlassPillButton(
                          icon: CupertinoIcons.book_fill,
                          label: '导入到书单（不下载）',
                          onPressed: _importing
                              ? null
                              : () async {
                                  String? groupId;
                                  if (widget.booklists.isNotEmpty) {
                                    groupId =
                                        await showCupertinoModalPopup<String>(
                                          context: context,
                                          builder: (_) => CupertinoActionSheet(
                                            title: const Text('加入哪个书单'),
                                            actions: [
                                              for (final entry
                                                  in widget.booklists.entries)
                                                CupertinoActionSheetAction(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        entry.key,
                                                      ),
                                                  child: Text(entry.value),
                                                ),
                                            ],
                                            cancelButton:
                                                CupertinoActionSheetAction(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('取消'),
                                                ),
                                          ),
                                        );
                                    if (groupId == null) return;
                                  }
                                  setState(() => _importing = true);
                                  try {
                                    for (final entry in _selected.values) {
                                      await widget.onAddCloud!(
                                        entry,
                                        widget.config,
                                        groupId,
                                      );
                                    }
                                    if (!mounted) return;
                                    _selected.clear();
                                    showNovelFeedback(
                                      context,
                                      '已导入书单 · ${widget.config.kind.label}，点开即在线阅读，不下载到本地',
                                    );
                                  } catch (_) {
                                    if (mounted) {
                                      showNovelFeedback(
                                        context,
                                        '导入书单未完成，请重试；已成功的书不会重复写入',
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _importing = false);
                                    }
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    if (_error != null) ...[
                      AppText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          height: 1.6,
                        ),
                      ),
                      GlassTextButton(
                        onPressed: _loading || _importing
                            ? null
                            : () => _load(),
                        child: const AppText('刷新目录'),
                      ),
                    ],
                    if (_loading &&
                        _entries.isEmpty &&
                        _loadedFolder != _folders.last.id)
                      const BookRowSkeleton(label: '正在读取网盘目录'),
                    if (!_loading && _error == null && _entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: AppText(
                          '这个目录没有可导入的书籍。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverList.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return LoadedContentItem(
                    key: ValueKey(('cloud-entry', entry.id)),
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          _CloudEntryArt(entry: entry),
                          const SizedBox(width: 14),
                          Expanded(
                            child: JellyTapSurface(
                              onTap:
                                  _importing ||
                                      _loading ||
                                      _readingOnline != null
                                  ? null
                                  : () {
                                      if (_batch && !entry.folder) {
                                        _toggleSelection(entry);
                                        return;
                                      }
                                      if (entry.folder) {
                                        _enter(entry);
                                        return;
                                      }
                                      if (widget.onReadCloud != null) {
                                        _readOnline(entry);
                                        return;
                                      }
                                      showNovelFeedback(
                                        context,
                                        '请点右侧圆圈加入书架，或先点“批量选择”再导入书单。',
                                      );
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      entry.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.5,
                                      ),
                                    ),
                                    if (!entry.folder)
                                      AppText(
                                        _addedToShelf.contains(entry.id)
                                            ? '已在书架 · 点开在线阅读'
                                            : _imported.contains(entry.id)
                                            ? '已在书单 · 点开在线阅读'
                                            : _readingOnline == entry.id
                                            ? '正在打开在线阅读…'
                                            : entry.size > 0
                                            ? '${formatCacheBytes(entry.size)} · 点开在线读'
                                            : '点开在线读，不下载到本地',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.6,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (entry.folder)
                            const ArchiveIcon(
                              CupertinoIcons.chevron_forward,
                              size: 16,
                            )
                          else
                            GlassIconButton(
                              icon: _batch
                                  ? (_selected.containsKey(entry.id)
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle)
                                  : (_addedToShelf.contains(entry.id) ||
                                            _imported.contains(entry.id)
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle),
                              label: _batch
                                  ? '选择 ${entry.name}'
                                  : (_addedToShelf.contains(entry.id) ||
                                            _imported.contains(entry.id)
                                        ? '${entry.name} 已在书架'
                                        : '加入书架 ${entry.name}'),
                              onPressed: _importing
                                  ? null
                                  : _batch
                                  ? () => _toggleSelection(entry)
                                  : widget.onAddShelf != null
                                  ? () => _addShelfEntry(entry)
                                  : () => _toggleSelection(entry),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                MediaQuery.paddingOf(context).bottom + 32,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading && _entries.isNotEmpty)
                      const BookRowSkeleton(label: '正在读取更多文件'),
                    if (!_loading && _next != null)
                      GlassTextButton(
                        onPressed: _importing ? null : () => _load(more: true),
                        child: const AppText('加载更多文件'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CloudScaffold extends StatelessWidget {
  const _CloudScaffold({
    required this.title,
    required this.code,
    this.child,
    this.sliverBody,
    this.onBack,
  });
  final String title, code;
  final Widget? child, sliverBody;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回',
            onPressed: onBack ?? () => Navigator.maybePop(context),
          ),
          title: ArchiveRouteTitle(title: title, code: code),
        ),
        body:
            sliverBody ??
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.paddingOf(context).top +
                    FrostedHeader.toolbarHeight +
                    20,
                24,
                MediaQuery.paddingOf(context).bottom + 32,
              ),
              child: child,
            ),
      ),
    ),
  );
}
