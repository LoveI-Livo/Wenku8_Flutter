import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'book_source_import.dart';
import 'cloud_catalog_search.dart';
import 'cloud_sources.dart';

/// 小说书源管理：批量导入书源文件，逐个体检并清理失效书源。
class BookSourceManagerPage extends StatefulWidget {
  const BookSourceManagerPage({super.key, required this.settings});
  final CloudSourceSettings settings;

  @override
  State<BookSourceManagerPage> createState() => _BookSourceManagerPageState();
}

class _BookSourceManagerPageState extends State<BookSourceManagerPage> {
  final _documents = BookDocuments();
  List<CloudBookSource> _sources = const [];
  CloudSourceConfig? _config;
  bool _busy = false;
  bool _checking = false;
  int _checked = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final config = widget.settings[CloudSourceKind.rss];
    _config = config;
    _sources = config == null
        ? const []
        : (config.sources.isNotEmpty
              ? List<CloudBookSource>.from(config.sources)
              : config.effectiveSources)
            .toList(growable: true);
    setState(() {});
  }

  CloudSourceConfig? get _baseConfig => _config ??
      (_sources.isEmpty
          ? null
          : CloudSourceConfig(
              kind: CloudSourceKind.rss,
              allowHttp: _sources.any((source) => source.url.startsWith('http://')),
              sources: _sources,
            ));

  Future<bool> _save() async {
    final sources = _sources;
    if (sources.isEmpty) {
      await widget.settings.save(CloudSourceKind.rss, null);
    } else {
      final base = _baseConfig;
      if (base == null) return false;
      final allowHttp = base.allowHttp ||
          sources.any((source) => source.url.startsWith('http://'));
      await widget.settings.save(
        CloudSourceKind.rss,
        base.withSources(sources).withAllowHttp(allowHttp),
      );
    }
    await CloudCatalogSearch.instance.reload();
    _config = widget.settings[CloudSourceKind.rss];
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _importFiles() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在选择书源文件';
    });
    final selections = await _documents.pickBooks();
    if (selections.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final added = <CloudBookSource>[];
    final failures = <String>[];
    try {
      for (final selection in selections) {
        if (selection.path == null) {
          failures.add('${selection.name}：${selection.error ?? '无法读取'}');
          continue;
        }
        try {
          final bytes = await File(selection.path!).readAsBytes();
          for (final source in await BookSourceFileReader.read(selection.name, bytes)) {
            if (_sources.any((item) => item.url == source.url) ||
                added.any((item) => item.url == source.url)) {
              continue;
            }
            added.add(CloudBookSource(url: source.url, name: source.name));
          }
        } catch (error) {
          failures.add('${selection.name}：${error is FormatException ? error.message : '格式无法识别'}');
        }
      }
      if (added.isNotEmpty) {
        _sources = [..._sources, ...added].take(200).toList(growable: true);
        await _save();
        _status = '已导入 ${added.length} 个书源${_sources.length > 200 ? '，超过 200 个已截断' : ''}';
      } else {
        _status = '没有新增书源';
      }
      if (failures.isNotEmpty) {
        _status = '${_status ?? ''}；${failures.length} 个文件未导入：${failures.first}';
      }
    } finally {
      await _documents.releaseBooks(selections);
      if (mounted) {
        setState(() {
          _busy = false;
          _status = _status;
        });
      }
    }
  }

  Future<void> _checkAll() async {
    if (_checking || _sources.isEmpty) return;
    final base = _baseConfig;
    if (base == null) return;
    setState(() {
      _checking = true;
      _checked = 0;
      _status = '正在检测 0 / ${_sources.length}';
    });
    final checked = <CloudBookSource>[];
    for (var start = 0; start < _sources.length; start += 4) {
      final batch = _sources.skip(start).take(4).toList();
      final results = await Future.wait(
        batch.map((source) async {
          final client = RssBookClient(base, sources: [source.url]);
          try {
            final probe = await client.probe(source.url);
            return source.copyWith(
              status: probe.valid ? 'valid' : 'invalid',
              message: probe.message,
              checkedAt: DateTime.now(),
            );
          } finally {
            client.close();
          }
        }),
      );
      checked.addAll(results);
      if (!mounted) return;
      setState(() {
        _checked = checked.length;
        _status = '正在检测 $_checked / ${_sources.length}';
        for (final result in results) {
          final index = _sources.indexWhere((source) => source.url == result.url);
          if (index >= 0) _sources[index] = result;
        }
      });
    }
    await _save();
    if (!mounted) return;
    final valid = _sources.where((source) => source.valid).length;
    final invalid = _sources.where((source) => source.invalid).length;
    setState(() {
      _checking = false;
      _status = '检测完成：$valid 个有效，$invalid 个失效';
    });
  }

  Future<void> _deleteInvalid() async {
    if (_checking || _busy) return;
    final invalid = _sources.where((source) => source.invalid).toList();
    if (invalid.isEmpty) {
      showNovelFeedback(context, '没有已标记为失效的书源，先点“检测全部”');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('删除失效书源？'),
        content: Text('将删除 ${invalid.length} 个检测失败的书源。网络临时中断也会显示失败，请确认后继续。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _sources = _sources.where((source) => !source.invalid).toList(growable: true);
      _status = '已删除 ${invalid.length} 个失效书源';
    });
    await _save();
  }

  Future<void> _deleteOne(CloudBookSource source) async {
    setState(() => _sources = _sources.where((item) => item.url != source.url).toList(growable: true));
    await _save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回',
            onPressed: () => Navigator.pop(context),
          ),
          title: const ArchiveRouteTitle(title: '小说书源', code: 'SOURCES / HEALTH'),
          actions: [
            GlassIconButton(
              icon: CupertinoIcons.refresh,
              label: '检测全部书源',
              onPressed: _checking ? null : _checkAll,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
            24,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          children: [
            const ArchiveSection(title: '书源管理', code: 'BOOK SOURCES'),
            const SizedBox(height: 10),
            const AppText(
              '支持 TXT 地址列表、CSV、Legado 书源 JSON、OPML 订阅表和含订阅链接的 HTML。'
              '导入后先检测，再一键清理失效书源；搜索时可以指定某一个书源。',
              style: TextStyle(fontSize: 13, height: 1.65),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                GlassPillButton(
                  key: const ValueKey('book-source-import-files'),
                  icon: CupertinoIcons.tray_arrow_down,
                  label: '导入书源文件',
                  onPressed: _busy || _checking ? null : _importFiles,
                ),
                GlassPillButton(
                  key: const ValueKey('book-source-check-all'),
                  icon: CupertinoIcons.checkmark_seal,
                  label: _checking ? '检测中 $_checked / ${_sources.length}' : '检测全部',
                  onPressed: _checking || _sources.isEmpty ? null : _checkAll,
                ),
                GlassPillButton(
                  key: const ValueKey('book-source-delete-invalid'),
                  icon: CupertinoIcons.trash,
                  label: '删除失效',
                  onPressed: _checking || _sources.isEmpty ? null : _deleteInvalid,
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              AppText(
                _status!,
                key: const ValueKey('book-source-status'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            if (_sources.isEmpty)
              const ContentNotice(
                icon: CupertinoIcons.layers,
                title: '还没有小说书源',
                message: '点“导入书源文件”选择分享的书源文件，或在网盘页添加书源地址。',
              )
            else
              for (final source in _sources) ...[
                _sourceRow(source),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            GlassTextButton(
              onPressed: _busy || _checking ? null : () async {
                await _save();
                if (context.mounted) showNovelFeedback(context, '书源已保存');
              },
              child: const AppText('保存书源'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sourceRow(CloudBookSource source) {
    final statusColor = source.valid
        ? const Color(0xFF2E7D32)
        : source.invalid
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ContentPanel(
      key: ValueKey('book-source-${source.url}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArchiveIcon(
            source.valid
                ? CupertinoIcons.checkmark_circle
                : source.invalid
                ? CupertinoIcons.xmark_circle
                : CupertinoIcons.circle,
            size: 20,
            color: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  source.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                AppText(
                  source.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (source.message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  AppText(
                    '${source.valid ? '有效' : source.invalid ? '失效' : '未检测'} · ${source.message}',
                    style: TextStyle(fontSize: 12, color: statusColor),
                  ),
                ],
              ],
            ),
          ),
          GlassIconButton(
            icon: CupertinoIcons.trash,
            label: '删除书源',
            onPressed: _checking ? null : () => _deleteOne(source),
          ),
        ],
      ),
    );
  }
}
