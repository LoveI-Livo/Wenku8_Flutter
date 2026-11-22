import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'feature_pages.dart';
import 'legacy_cover.dart';
import 'library_state.dart';
import 'mod_edition.dart';
import 'offline_cache.dart';
import 'offline_repository.dart';
import 'widget_cache_bridge.dart';

/// 「缓存与存储」中心：查看占用、按类别清理。
///
/// 清理动作全部复用原有的存储接口（[OfflineCacheStore.clear] 等），
/// 不会删除书架、阅读进度、书签和本地导入的原书。
class CacheCenterPage extends StatefulWidget {
  const CacheCenterPage({
    super.key,
    required this.repository,
    required this.reduceMotion,
    this.state,
  });

  /// 只有离线仓库才知道缓存目录；为 null 时只清理图片与临时文件。
  final OfflineNovelRepository? repository;
  final bool reduceMotion;
  final LibraryState? state;

  @override
  State<CacheCenterPage> createState() => _CacheCenterPageState();
}

class _CacheCenterPageState extends State<CacheCenterPage> {
  final _scroll = ScrollController();
  bool _measuring = true;
  bool _busy = false;
  int _chapterBytes = 0;
  int _chapterBooks = 0;
  int _tempBytes = 0;
  int _cacheBytes = 0;
  int _widgetBytes = 0;
  int _imageBytes = 0;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    if (mounted) setState(() => _measuring = true);
    var chapterBytes = 0;
    var chapterBooks = 0;
    final repository = widget.repository;
    if (repository != null) {
      try {
        await repository.cache.load();
        chapterBytes = repository.cache.bytes;
        chapterBooks = repository.cache.books.length;
      } catch (_) {
        // 目录不可读时按 0 处理，不影响其他清理项。
      }
    }
    var tempBytes = 0;
    var cacheBytes = 0;
    try {
      tempBytes = await _folderBytes(await getTemporaryDirectory());
    } catch (_) {
      tempBytes = 0;
    }
    try {
      cacheBytes = await _folderBytes(await getApplicationCacheDirectory());
    } catch (_) {
      cacheBytes = 0;
    }
    final widgetBytes = await WidgetCacheBridge.nativeBytes() +
        await WidgetCacheBridge.flutterBytes() +
        await _widgetCoverBytes();
    if (!mounted) return;
    setState(() {
      _chapterBytes = chapterBytes;
      _chapterBooks = chapterBooks;
      _tempBytes = tempBytes;
      _cacheBytes = cacheBytes;
      _widgetBytes = widgetBytes;
      _imageBytes = PaintingBinding.instance.imageCache.currentSizeBytes + LegacyCover.encodedBytes;
      _measuring = false;
    });
  }

  static Future<int> _folderBytes(Directory directory) async {
    var total = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // 单个文件读不到时跳过。
          }
        }
      }
    } catch (_) {
      return 0;
    }
    return total;
  }

  Future<void> _clearChapters() async {
    final repository = widget.repository;
    if (repository == null) return;
    await repository.cache.clear();
  }

  void _clearImages() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    LegacyCover.clear();
  }

  Future<void> _clearAppCache() async {
    try {
      final directory = await getApplicationCacheDirectory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // 被系统占用的缓存保持原样。
        }
      }
    } catch (_) {}
  }

  Future<Directory?> _widgetCoverDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/reading-widget-covers-v1');
    } catch (_) {
      return null;
    }
  }

  Future<int> _widgetCoverBytes() async {
    final directory = await _widgetCoverDirectory();
    return directory == null ? 0 : _folderBytes(directory);
  }

  Future<void> _clearWidgets() async {
    await WidgetCacheBridge.clearNative();
    await WidgetCacheBridge.clearFlutter();
    final coverDirectory = await _widgetCoverDirectory();
    if (coverDirectory != null && await coverDirectory.exists()) {
      await coverDirectory.delete(recursive: true);
    }
    // 这里不再立刻重建图片，否则刚清掉的缓存会马上重新写回来；桌面组件
    // 会在下次启动、修改配置或打开书籍时按当前卡片重新生成。
  }

  Future<void> _clearTemp() async {
    try {
      final directory = await getTemporaryDirectory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // 被系统占用的临时文件保持原样。
        }
      }
    } catch (_) {
      // 临时目录不可用时静默跳过。
    }
  }

  Future<void> _run({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
  }) async {
    if (_busy) return;
    final confirmed = await confirmNovelAction(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      _clearImages();
      if (mounted) showNovelFeedback(context, '已清理完成');
    } catch (_) {
      if (mounted) showNovelFeedback(context, '清理失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _measure();
    }
  }

  Future<void> _clearAll() => _run(
    title: '清理全部缓存？',
    message: '包括正文与插图、网页与应用缓存、临时文件、桌面小组件图片和图片内存缓存。'
        '书架、阅读进度、书签、登录状态与本地导入的原书都会保留，缓存内容在需要时重新生成。',
    confirmLabel: '全部清理',
    action: () async {
      await _clearChapters();
      await _clearAppCache();
      await _clearTemp();
      await _clearWidgets();
    },
  );

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailing,
    VoidCallback? onTap,
  }) => ContentPanel(
    onTap: onTap,
    child: Row(
      children: [
        ArchiveIcon(icon, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              AppText(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppText(
          trailing,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // 图片缓存是运行期内存，不占安装存储；不计入“已占用”，避免空书架也显示二十多 MB。
    final total = _chapterBytes + _tempBytes + _cacheBytes + _widgetBytes;
    return ArchiveFeaturePage(
      title: '缓存与存储',
      code: 'SYSTEM / CACHE',
      child: ListView(
        controller: _scroll,
        key: const ValueKey('cache-center'),
        padding: featurePadding(context),
        children: [
          ArchiveSection(title: '当前占用', code: 'STORAGE / USAGE'),
          const SizedBox(height: 14),
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppText(
                  _measuring ? '正在统计…' : formatCacheBytes(total),
                  key: const ValueKey('cache-total-size'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                AppText(
                  '正文 ${formatCacheBytes(_chapterBytes)}（$_chapterBooks 本） · '
                  '网页 ${formatCacheBytes(_cacheBytes)} · 临时 ${formatCacheBytes(_tempBytes)}\n'
                  '小组件图片 ${formatCacheBytes(_widgetBytes)} · '
                  '图片内存 ${formatCacheBytes(_imageBytes)}（运行期，不占存储）',
                  style: TextStyle(fontSize: 12, height: 1.6, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassTextButton(
            key: const ValueKey('cache-refresh'),
            onPressed: _measuring || _busy ? null : _measure,
            child: AppText(_measuring ? '正在统计' : '重新统计'),
          ),
          const SizedBox(height: 24),
          ArchiveSection(title: '分类清理', code: 'CLEAN / BY TYPE'),
          const SizedBox(height: 14),
          _row(
            icon: CupertinoIcons.book,
            title: '正文与插图缓存',
            subtitle: '已缓存到本机的章节正文和插图，清理后重新阅读时自动下载',
            trailing: formatCacheBytes(_chapterBytes),
            onTap: widget.repository == null || _busy
                ? null
                : () => _run(
                    title: '清理正文与插图缓存？',
                    message: '清理后已缓存的章节需要重新下载，阅读进度和书签不受影响。',
                    confirmLabel: '清理',
                    action: _clearChapters,
                  ),
          ),
          const SizedBox(height: 14),
          _row(
            icon: CupertinoIcons.square_grid_2x2,
            title: '网页与应用缓存',
            subtitle: '网页登录、封面、网络请求和系统生成的缓存文件，清理后自动重新生成',
            trailing: formatCacheBytes(_cacheBytes),
            onTap: _busy
                ? null
                : () => _run(
                    title: '清理网页与应用缓存？',
                    message: '不会退出书源登录，也不会删除书架与阅读记录；网页内容下次打开时重新加载。',
                    confirmLabel: '清理',
                    action: _clearAppCache,
                  ),
          ),
          const SizedBox(height: 14),
          _row(
            icon: CupertinoIcons.photo,
            title: '图片内存缓存',
            subtitle: '运行期内存，不占安装存储；清理后重新加载封面与插图',
            trailing: formatCacheBytes(_imageBytes),
            onTap: _busy
                ? null
                : () => _run(
                    title: '清理图片内存缓存？',
                    message: '只释放内存占用，下次显示封面或插图时重新加载。',
                    confirmLabel: '清理',
                    action: () async {
                      _clearImages();
                    },
                  ),
          ),
          const SizedBox(height: 14),
          _row(
            icon: CupertinoIcons.square_on_square,
            title: '桌面小组件图片',
            subtitle: '系统桌面小组件使用的图片；清理后桌面组件下次刷新时自动重建',
            trailing: formatCacheBytes(_widgetBytes),
            onTap: _busy
                ? null
                : () => _run(
                    title: '清理桌面小组件图片？',
                    message: '会删除桌面小组件旧图片；桌面上的小组件会在下次刷新时重建，不影响书架。',
                    confirmLabel: '清理',
                    action: _clearWidgets,
                  ),
          ),
          const SizedBox(height: 14),
          _row(
            icon: CupertinoIcons.folder,
            title: '临时文件',
            subtitle: '导入、导出与转码过程产生的临时文件',
            trailing: formatCacheBytes(_tempBytes),
            onTap: _busy
                ? null
                : () => _run(
                    title: '清理临时文件？',
                    message: '只删除系统临时目录中的缓存文件，不影响书架与本地原书。',
                    confirmLabel: '清理',
                    action: _clearTemp,
                  ),
          ),
          const SizedBox(height: 24),
          ArchiveSection(title: '一键清理', code: 'CLEAN / ALL'),
          const SizedBox(height: 14),
          GlassTextButton(
            key: const ValueKey('cache-clear-all'),
            onPressed: _busy ? null : _clearAll,
            child: AppText(_busy ? '正在清理' : '清理全部缓存'),
          ),
          const SizedBox(height: 16),
          AppText(
            '书架、阅读进度、书签、笔记与本地导入的原书不会被删除。'
            '清理后再次阅读时会重新从来源获取内容。',
            style: TextStyle(fontSize: 12, height: 1.7, color: muted),
          ),
          const SizedBox(height: 20),
          AppText(
            '改版 $modEditionVersion · $modAuthorName',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}
