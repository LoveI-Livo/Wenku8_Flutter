import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'cloud_backup.dart';
import 'cloud_library_page.dart';
import 'cloud_sources.dart';
import 'library_backup.dart';
import 'library_state.dart';
import 'local_platform.dart';

class LibraryBackupPage extends StatefulWidget {
  const LibraryBackupPage({super.key, required this.state});
  final LibraryState state;
  @override
  State<LibraryBackupPage> createState() => _LibraryBackupPageState();
}

class _LibraryBackupPageState extends State<LibraryBackupPage> {
  String? _busy;
  String? _error;
  LibraryBackup? _preview;
  bool _preferences = false;
  late final CloudSourceSettings _cloud = CloudSourceSettings();
  CloudBackupReceipt? _cloudReceipt;

  @override
  void initState() {
    super.initState();
    _cloud.addListener(_cloudChanged);
    _cloud.load();
  }

  @override
  void dispose() {
    _cloud
      ..removeListener(_cloudChanged)
      ..dispose();
    super.dispose();
  }

  void _cloudChanged() {
    if (mounted) setState(() {});
  }

  static String _cloudKey(CloudSourceConfig config) =>
      '${config.kind.name}|${config.address}|${config.bucket}';

  List<CloudSourceConfig> get _cloudTargets {
    final targets = <CloudSourceConfig>[];
    void add(CloudSourceConfig? config) {
      if (config == null ||
          config.kind != CloudSourceKind.webdav &&
              config.kind != CloudSourceKind.s3 ||
          targets.any((other) => _cloudKey(other) == _cloudKey(config))) {
        return;
      }
      targets.add(config);
    }

    for (final config in _cloud.configs) {
      add(config);
    }
    add(_cloud.s3Sync?.config);
    return targets;
  }

  String _cloudLabel(CloudSourceConfig config) => switch (config.kind) {
    CloudSourceKind.webdav => 'WebDAV / OpenList',
    CloudSourceKind.s3 => 'S3 / 兼容对象存储',
    _ => config.kind.label,
  };

  String _cloudDetail(CloudSourceConfig config) => switch (config.kind) {
    CloudSourceKind.webdav =>
      Uri.tryParse(config.address)?.host ?? config.address,
    CloudSourceKind.s3 => [
      if (config.bucket.isNotEmpty) config.bucket,
      config.region,
      if (config.prefix.isNotEmpty) config.prefix,
    ].join(' · '),
    _ => config.address,
  };

  Future<void> _connectCloud(CloudSourceKind kind) async {
    final config = await pushNovelPage<CloudSourceConfig>(
      context,
      CloudConnectionPage(settings: _cloud, kind: kind),
      reduceMotion: widget.state.reduceMotion,
    );
    await _cloud.load();
    if (!mounted || config == null) return;
    showNovelFeedback(context, '网盘连接已保存');
  }

  Future<CloudSourceConfig?> _pickCloudTarget(String title) async {
    final targets = _cloudTargets;
    if (targets.isEmpty) {
      setState(() => _error = '请先连接 WebDAV 或 S3 网盘');
      return null;
    }
    return showCupertinoModalPopup<CloudSourceConfig>(
      context: context,
      builder: (picker) => CupertinoActionSheet(
        title: Text(title),
        message: const Text('选择一个已连接的网盘'),
        actions: [
          for (final config in targets)
            CupertinoActionSheetAction(
              key: ValueKey('cloud-backup-pick-${_cloudKey(config)}'),
              onPressed: () => Navigator.pop(picker, config),
              child: Column(
                children: [
                  Text(_cloudLabel(config)),
                  const SizedBox(height: 2),
                  Text(
                    _cloudDetail(config),
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(picker),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _cloudBackup({CloudSourceConfig? target}) async {
    final config = target ?? await _pickCloudTarget('选择备份网盘');
    if (config == null) return;
    await _run('正在备份到${_cloudLabel(config)}…', () async {
      final backup = await widget.state.createBackup();
      final text = await backup.encode();
      final receipt = await CloudBackupService().backup(config, text);
      if (!mounted) return;
      setState(() => _cloudReceipt = receipt);
      showNovelFeedback(context, '已备份到网盘：${receipt.fileName}');
    });
  }

  Future<void> _cloudRestore() async {
    final config = await _pickCloudTarget('选择恢复网盘');
    if (config == null) return;
    await _run('正在读取云端备份…', () async {
      final text = await CloudBackupService().restoreLatest(config);
      if (text == null) {
        throw const FormatException('这个网盘里还没有备份，请先上传一次');
      }
      final backup = await LibraryBackup.parse(text);
      if (!mounted) return;
      setState(() {
        _preview = backup;
        _preferences = false;
      });
      showNovelFeedback(context, '已读取云端最新备份');
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = label;
      _error = null;
    });
    // Present the progress state before serializing/merging an explicit backup.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on CloudSourceFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on SocketException catch (_) {
      if (mounted) setState(() => _error = '无法连接网盘，请检查网络、地址和证书');
    } catch (error) {
      if (mounted) setState(() => _error = cloudFailureMessage(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _export({bool clipboard = false}) => _run('正在生成备份…', () async {
    final text = await (await widget.state.createBackup()).encode();
    if (clipboard) {
      if (text.length > 256 * 1024) throw const FormatException('备份较大，请使用文件导出');
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showNovelFeedback(context, '备份已复制');
    } else {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await LocalPlatform.exportBackup(
        text,
        'wenku8-backup-$date.json',
      );
      if (mounted && saved) showNovelFeedback(context, '备份文件已保存');
    }
  });

  Future<void> _import({bool clipboard = false}) => _run('正在读取备份…', () async {
    final text = clipboard
        ? (await Clipboard.getData(Clipboard.kTextPlain))?.text
        : await LocalPlatform.importBackup();
    if (text == null) {
      if (clipboard) throw const FormatException('剪贴板中没有备份文本');
      return; // System picker cancellation is not an error.
    }
    final backup = await LibraryBackup.parse(text);
    if (mounted) {
      setState(() {
        _preview = backup;
        _preferences = false;
      });
    }
  });

  Future<void> _restore() => _run('正在合并本地记录…', () async {
    final backup = _preview;
    if (backup == null) return;
    await widget.state.restoreBackup(backup, importPreferences: _preferences);
    if (mounted) {
      setState(() => _preview = null);
      showNovelFeedback(context, '备份已合并，较新的阅读进度已保留');
    }
  });

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _busy == null,
    child: Scaffold(
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: ArchiveHeaderBar(
            leading: GlassIconButton(
              icon: CupertinoIcons.back,
              label: '返回设置',
              onPressed: _busy == null ? () => Navigator.pop(context) : null,
            ),
            title: const ArchiveRouteTitle(
              title: '备份与恢复',
              code: 'SYSTEM / DATA TRANSFER',
            ),
          ),
          body: LoadedContentSequence(
            generation: _preview,
            child: ListView(
              key: const ValueKey('backup-scroll'),
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.paddingOf(context).top +
                    FrostedHeader.toolbarHeight +
                    20,
                24,
                MediaQuery.paddingOf(context).bottom + 32,
              ),
              children: [
                const AppText(
                  '带走你的阅读记录',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const AppText('备份书架、阅读进度、书签、阅读历史、最近搜索和偏好。离线正文与账号信息不包含在备份中。'),
                const SizedBox(height: 24),
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (LocalPlatform.fileActions) ...[
                        GlassTextButton(
                          key: const ValueKey('backup-export-file'),
                          onPressed: _busy == null ? _export : null,
                          child: const AppText('导出备份文件'),
                        ),
                        GlassTextButton(
                          key: const ValueKey('backup-import-file'),
                          onPressed: _busy == null ? _import : null,
                          child: const AppText('选择备份文件'),
                        ),
                        const Divider(height: 24),
                      ],
                      GlassTextButton(
                        key: const ValueKey('backup-copy'),
                        onPressed: _busy == null
                            ? () => _export(clipboard: true)
                            : null,
                        child: const AppText('复制备份文本'),
                      ),
                      GlassTextButton(
                        key: const ValueKey('backup-paste'),
                        onPressed: _busy == null
                            ? () => _import(clipboard: true)
                            : null,
                        child: const AppText('从剪贴板读取备份'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                sectionHeader(context, '云端备份', 'CLOUD / BACKUP'),
                const SizedBox(height: 14),
                const AppText(
                  '除了导出文件，也可以直接备份到已连接的 WebDAV 或 S3。'
                  '连接信息保存在本机加密存储，备份文件只包含书架、进度、书签、历史和偏好。',
                  style: TextStyle(fontSize: 13, height: 1.65),
                ),
                const SizedBox(height: 14),
                if (_cloud.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppText(
                      _cloud.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ContentPanel(
                  key: const ValueKey('cloud-backup-actions'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_cloudTargets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: AppText(
                            '还没有可备份的网盘。先连接一个 WebDAV 或 S3，之后点按钮手动选择要备份的网盘。',
                            style: TextStyle(fontSize: 13, height: 1.6),
                          ),
                        ),
                      if (_cloudTargets.isNotEmpty) ...[
                        GlassTextButton(
                          key: const ValueKey('cloud-backup-now'),
                          onPressed: _busy == null
                              ? () => _cloudBackup()
                              : null,
                          child: AppText('选择网盘并备份'),
                        ),
                        GlassTextButton(
                          key: const ValueKey('cloud-backup-restore'),
                          onPressed: _busy == null ? _cloudRestore : null,
                          child: const AppText('选择网盘并恢复最近备份'),
                        ),
                        const Divider(height: 24),
                      ],
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          GlassTextButton(
                            key: const ValueKey('cloud-connect-webdav'),
                            onPressed: _busy == null
                                ? () => _connectCloud(CloudSourceKind.webdav)
                                : null,
                            compact: true,
                            child: const AppText('连接 WebDAV'),
                          ),
                          GlassTextButton(
                            key: const ValueKey('cloud-connect-s3'),
                            onPressed: _busy == null
                                ? () => _connectCloud(CloudSourceKind.s3)
                                : null,
                            compact: true,
                            child: const AppText('连接 S3'),
                          ),
                        ],
                      ),
                      if (_cloudReceipt case final receipt?) ...[
                        const SizedBox(height: 12),
                        AppText(
                          '最近上传：${receipt.fileName} · ${(receipt.bytes / 1024).ceil()} KB',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const AppText(
                        'WebDAV 会写入 wenku8-backups 目录，每次保留带日期的文件；S3 会覆盖 wenku8-backups/latest.json。恢复时读取最近一次。',
                        style: TextStyle(fontSize: 12, height: 1.55),
                      ),
                    ],
                  ),
                ),
                if (_busy != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Row(
                      children: [
                        Expanded(child: AppText(_busy!)),
                        const SizedBox(width: 12),
                        const SizedBox(
                          width: 120,
                          height: 64,
                          child: LoadingSkeleton(
                            layout: SkeletonLayout.actions,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Semantics(
                      liveRegion: true,
                      child: AppText(
                        _error!,
                        key: const ValueKey('backup-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (_preview case final backup?) ...[
                  const SizedBox(height: 24),
                  LoadedContentItem(
                    index: 0,
                    child: sectionHeader(context, '恢复预览', ''),
                  ),
                  const SizedBox(height: 14),
                  LoadedContentItem(
                    index: 1,
                    child: ContentPanel(
                      key: const ValueKey('backup-preview'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppText('备份时间 ${_date(backup.createdAt)}'),
                          const SizedBox(height: 12),
                          AppText(
                            '${backup.shelfCount} 本书架收藏 · ${backup.positionCount} 条阅读进度\n${backup.bookmarkCount} 个书签 · ${backup.historyCount} 本阅读记录',
                          ),
                          const SizedBox(height: 14),
                          const AppText('恢复将合并到本机，不清空已有书架和书签；同一本书保留更新时间较新的进度。'),
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Expanded(child: AppText('同时恢复外观与阅读偏好')),
                              AppControls.toggle(
                                context,
                                key: const ValueKey(
                                  'backup-import-preferences',
                                ),
                                value: _preferences,
                                onChanged: _busy == null
                                    ? (value) =>
                                          setState(() => _preferences = value)
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GlassTextButton(
                            key: const ValueKey('backup-confirm'),
                            onPressed: _busy == null ? _restore : null,
                            child: const AppText('确认合并恢复'),
                          ),
                          GlassTextButton(
                            onPressed: _busy == null
                                ? () => setState(() => _preview = null)
                                : null,
                            child: const AppText('取消恢复'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String _date(int timestamp) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        timestamp,
      ).toLocal().toString().substring(0, 16);
    } catch (_) {
      return '未记录';
    }
  }
}
