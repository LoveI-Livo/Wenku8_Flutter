import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'cloud_parse_service.dart';
import 'feature_pages.dart';
import 'mod_edition.dart';

class CloudParseCard extends StatefulWidget {
  const CloudParseCard({super.key, this.reduceMotion = false});
  final bool reduceMotion;

  @override
  State<CloudParseCard> createState() => _CloudParseCardState();
}

class _CloudParseCardState extends State<CloudParseCard> {
  @override
  void initState() {
    super.initState();
    CloudParseSettings.instance.load();
  }

  Future<void> _open() => pushNovelPage<void>(
    context,
    CloudParsePage(reduceMotion: widget.reduceMotion),
    reduceMotion: widget.reduceMotion,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: CloudParseSettings.instance,
    builder: (context, _) {
      final settings = CloudParseSettings.instance;
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      return ContentPanel(
        key: const ValueKey('cloud-parse-card'),
        onTap: _open,
        child: Row(
          children: [
            const ArchiveIcon(CupertinoIcons.cloud, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppText(
                    '云端主机解析',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    settings.enabled
                        ? '已连接解析主机，优先在主机解析，失败自动回退本机'
                        : '未设置。可把网盘书交给自己的主机解析，减少手机占用',
                    style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppText(
              settings.enabled ? '已启用' : '未设置',
              style: TextStyle(
                fontSize: 12,
                color: settings.enabled
                    ? Theme.of(context).colorScheme.primary
                    : muted,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CloudParsePage extends StatefulWidget {
  const CloudParsePage({super.key, required this.reduceMotion});
  final bool reduceMotion;
  @override
  State<CloudParsePage> createState() => _CloudParsePageState();
}

class _CloudParsePageState extends State<CloudParsePage> {
  final _endpoint = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await CloudParseSettings.instance.load();
    if (!mounted) return;
    _endpoint.text = CloudParseSettings.instance.endpoint;
    _token.text = CloudParseSettings.instance.token;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudParseSettings.instance.save(_endpoint.text, _token.text);
      if (mounted) {
        showNovelFeedback(context, '云端解析设置已保存');
        Navigator.pop(context);
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => _error = failure is FormatException
              ? failure.message
              : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final endpoint = _endpoint.text.trim();
    final token = _token.text.trim();
    if (endpoint.isEmpty || token.isEmpty) {
      setState(() => _error = '先填写解析接口地址和解析密钥');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await CloudParseService.instance.probe(endpoint, token);
      if (mounted) showNovelFeedback(context, message);
    } catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure is FormatException
              ? failure.message
              : '接口测试失败，请重试';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CloudParseSettings.instance.save('', '');
      if (mounted) {
        _endpoint.clear();
        _token.clear();
        showNovelFeedback(context, '已关闭云端解析');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      controller: controller,
      enabled: _loaded && !_busy,
      minLines: 1,
      maxLines: maxLines,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: secret,
      style: const TextStyle(fontSize: 14, height: 1.5),
      inputFormatters: [LengthLimitingTextInputFormatter(4096)],
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '云端主机解析',
    code: 'CLOUD / REMOTE PARSER',
    child: ListView(
      padding: featurePadding(context),
      children: [
        const AppText(
          '把网盘书的拉取和解析交给自己的主机，主机返回书名、作者、简介、封面、'
          '正文和插图，手机不再解析原文件。主机未配置、解析失败或格式不支持时，'
          '自动回退本机解析。',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
        const SizedBox(height: 18),
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                _endpoint,
                '解析接口地址',
                '例如 https://你的域名/cloud-parse/index.php',
                maxLines: 2,
              ),
              _field(
                _token,
                '解析密钥',
                '与主机 config.php 中的 token 一致',
                secret: true,
              ),
              const SizedBox(height: 14),
              const AppText(
                '只填写你自己的主机。App 会把网盘临时直链和本次阅读所需的登录凭证发送到该地址；'
                '不会上传整本原书到第三方。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppText(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                height: 1.6,
              ),
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            GlassTextButton(
              key: const ValueKey('cloud-parse-test'),
              onPressed: _loaded && !_busy ? _test : null,
              child: const AppText('测试接口'),
            ),
            GlassTextButton(
              key: const ValueKey('cloud-parse-save'),
              onPressed: _loaded && !_busy ? _save : null,
              child: AppText(_busy ? '正在处理' : '保存并启用'),
            ),
          ],
        ),
        if (_loaded && CloudParseSettings.instance.enabled) ...[
          const SizedBox(height: 12),
          GlassTextButton(
            onPressed: _busy ? null : _clear,
            child: const AppText('关闭云端解析'),
          ),
        ],
        const SizedBox(height: 18),
        const AppText(
          '主机端接口文件在项目 server/cloud-parse/ 目录，部署后把地址和密钥填到这里。',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 24),
        AppText(
          '改版 $modEditionVersion · $modAuthorName',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
