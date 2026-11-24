import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'catalog.dart';
import 'cloud_document_service.dart';
import 'cloud_sources.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'ui_notifiers.dart';

class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.title,
    required this.author,
    required this.source,
    required this.path,
    required this.bytes,
    required this.createdAt,
  });
  final int id;
  final String title, author, source, path, createdAt;
  final int bytes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'source': source,
    'path': path,
    'bytes': bytes,
    'createdAt': createdAt,
  };

  static DownloadRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final path = value['path'];
    if (id is! int || title is! String || path is! String) return null;
    return DownloadRecord(
      id: id,
      title: title,
      author: '${value['author'] ?? '网盘书源'}',
      source: '${value['source'] ?? '在线书籍'}',
      path: path,
      bytes: value['bytes'] is int ? value['bytes'] as int : 0,
      createdAt: '${value['createdAt'] ?? ''}',
    );
  }
}

/// 下载记录独立于书架；删除书架记录后，已经下载到本机的文件仍可导出。
final class DownloadStore extends ChangeNotifier {
  DownloadStore._();
  static final instance = DownloadStore._();
  static const _key = 'download_center_records_v1';
  final List<DownloadRecord> _records = [];
  bool _loaded = false;

  List<DownloadRecord> get records => List.unmodifiable(_records);
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _records
        ..clear()
        ..addAll(decoded.map(DownloadRecord.fromJson).whereType());
      notifyListeners();
    } catch (_) {
      // 损坏的单条下载记录不会影响页面打开。
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final record in _records) record.toJson()]),
    );
  }

  Future<void> put(DownloadRecord record) async {
    _records.removeWhere((item) => item.id == record.id);
    _records.insert(0, record);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(int id) async {
    _records.removeWhere((item) => item.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _records.clear();
    await _persist();
    notifyListeners();
  }
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.state,
    required this.repository,
  });
  final LibraryState state;
  final NovelRepository repository;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  static const _speeds = <(int, String)>[
    (0, '不限速'),
    (1, '1 MB/s'),
    (2, '2 MB/s'),
    (5, '5 MB/s'),
    (10, '10 MB/s'),
  ];
  int _speed = 0;
  bool _rateLoaded = false;
  int? _busyBook;
  String _progress = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    DownloadStore.instance.load();
    _loadRate();
  }

  Future<void> _loadRate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _speed = prefs.getInt('download_speed_mbps') ?? 0;
      _rateLoaded = true;
    });
  }

  Future<void> _setSpeed(int value) async {
    setState(() => _speed = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('download_speed_mbps', value);
    if (mounted) showNovelFeedback(context, '下载速度已设为 ${_speedLabel(value)}');
  }

  String _speedLabel(int value) => _speeds
      .firstWhere((item) => item.$1 == value, orElse: () => (0, '不限速'))
      .$2;

  List<Novel> get _downloadable {
    final seen = <int>{};
    final books = <Novel>[];
    for (final id in widget.state.shelf) {
      final novel = CloudDocumentService.instance.known(id);
      if (novel == null || !seen.add(id)) continue;
      books.add(novel);
    }
    return books;
  }

  Future<void> _download(Novel novel) async {
    if (_busyBook != null) return;
    setState(() {
      _busyBook = novel.id;
      _progress = '正在连接网盘…';
      _error = null;
    });
    CloudThrottle.bytesPerSecond = _speed == 0 ? null : _speed * 1024 * 1024;
    try {
      final detail = await CloudDocumentService.instance.detail(novel);
      final chapters = await CloudDocumentService.instance.chapters(detail.id);
      final output = StringBuffer()
        ..writeln(detail.title)
        ..writeln(detail.author)
        ..writeln()
        ..writeln('来源：${detail.sourceLabel ?? '网盘书源'}')
        ..writeln();
      for (var index = 0; index < chapters.length; index++) {
        final chapter = chapters[index];
        if (mounted && (index % 5 == 0 || index == chapters.length - 1)) {
          setState(() => _progress = '正在读取 ${index + 1}/${chapters.length} 章');
        }
        final body = await CloudDocumentService.instance.chapterContent(
          detail.id,
          chapter,
        );
        output
          ..writeln(chapter.title)
          ..writeln(body.replaceAll(RegExp(r'<!--[^>]*-->'), '').trim())
          ..writeln();
      }
      final directory = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/downloads',
      );
      await directory.create(recursive: true);
      final safe = _safeName(detail.title);
      final file = File('${directory.path}/$safe.txt');
      await file.writeAsString(output.toString(), flush: true);
      final record = DownloadRecord(
        id: detail.id,
        title: detail.title,
        author: detail.author,
        source: detail.sourceLabel ?? '在线书籍',
        path: file.path,
        bytes: await file.length(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await DownloadStore.instance.put(record);
      if (mounted) {
        setState(() => _progress = '已下载 ${chapters.length} 章');
        showNovelFeedback(context, '《${detail.title}》已下载到本机');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = cloudFailureMessage(error));
      }
    } finally {
      CloudThrottle.bytesPerSecond = null;
      if (mounted) setState(() => _busyBook = null);
    }
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    return cleaned.isEmpty ? '下载的小说' : cleaned;
  }

  Future<void> _export(DownloadRecord record) async {
    try {
      final file = File(record.path);
      if (!await file.exists()) {
        if (mounted) showNovelFeedback(context, '下载文件已不存在，请重新下载');
        return;
      }
      final saved = await BookDocuments().exportText(
        record.path,
        '${record.title}.txt',
      );
      if (saved != null && saved.isNotEmpty && mounted) {
        showNovelFeedback(context, '已保存到本地文件夹');
      }
    } catch (_) {
      if (mounted) showNovelFeedback(context, '无法打开系统文件夹，请稍后重试');
    }
  }

  Future<void> _delete(DownloadRecord record) async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除下载文件？',
      message: '会删除《${record.title}》保存在本机的下载文件，并移除这条下载记录。',
      confirmLabel: '删除文件',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      final file = File(record.path);
      if (await file.exists()) await file.delete();
      await DownloadStore.instance.remove(record.id);
      if (mounted) showNovelFeedback(context, '已删除《${record.title}》的下载文件');
    } catch (_) {
      if (mounted) showNovelFeedback(context, '删除失败，请稍后重试');
    }
  }

  Future<void> _deleteAvailable(Novel novel) async {
    final confirmed = await confirmNovelAction(
      context,
      title: '从网络书架删除？',
      message: '只会移除《${novel.title}》在网络书架里的记录，网盘或书源里的原文件不会被删除。',
      confirmLabel: '删除',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.state.setShelfMembership(novel.id, false);
      CloudDocumentService.instance.forget(novel.id);
      if (mounted) showNovelFeedback(context, '已从网络书架删除《${novel.title}》');
    } catch (_) {
      if (mounted) showNovelFeedback(context, '删除失败，请稍后重试');
    }
  }

  Future<void> _clearAll() async {
    final records = DownloadStore.instance.records;
    if (records.isEmpty) return;
    final confirmed = await confirmNovelAction(
      context,
      title: '清空全部下载？',
      message:
          '会删除已下载的 ${records.length} 个本机文件，并清空全部下载记录。'
          '网盘原文件和网络书架不受影响。',
      confirmLabel: '清空全部',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    var failed = 0;
    for (final record in records) {
      try {
        final file = File(record.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        failed++;
      }
    }
    await DownloadStore.instance.clear();
    if (!mounted) return;
    showNovelFeedback(
      context,
      failed == 0 ? '已清空全部下载，本机文件已删除' : '已清空下载记录，$failed 个文件未能删除',
    );
  }

  String _size(int bytes) {
    if (bytes >= 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '下载',
    code: 'SYSTEM / DOWNLOADS',
    child: ActiveListenableBuilder(
      listenable: Listenable.merge([DownloadStore.instance, widget.state]),
      builder: (context) => ListView(
        padding: featurePadding(context),
        children: [
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    ArchiveIcon(CupertinoIcons.arrow_down_to_line, size: 21),
                    SizedBox(width: 12),
                    AppText(
                      '下载速度',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AppText(
                  '限速只作用于下载中心，不影响正常阅读。默认不限速。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (_rateLoaded)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final speed in _speeds)
                        GlassTextButton(
                          key: ValueKey('download-speed-${speed.$1}'),
                          selected: _speed == speed.$1,
                          compact: true,
                          onPressed: () => _setSpeed(speed.$1),
                          child: AppText(speed.$2),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: _SectionTitle('已下载小说')),
              if (DownloadStore.instance.records.isNotEmpty)
                GlassTextButton(
                  key: const ValueKey('download-clear-all'),
                  compact: true,
                  onPressed: _clearAll,
                  haptic: HapticCue.warning,
                  child: const AppText('清空全部'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (DownloadStore.instance.records.isEmpty)
            ContentPanel(
              child: AppText(
                '还没有下载记录。下面选一本网络书架里的书，下载后保存在本机，'
                '还能导出到你指定的文件夹。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final record in DownloadStore.instance.records) ...[
              ContentPanel(
                key: ValueKey('download-record-${record.id}'),
                child: Row(
                  children: [
                    const ArchiveIcon(CupertinoIcons.doc_text, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            record.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          AppText(
                            '${record.source} · ${_size(record.bytes)} · 已保存到本机',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              GlassTextButton(
                                key: ValueKey('download-export-${record.id}'),
                                compact: true,
                                onPressed: () => _export(record),
                                child: const AppText('保存到本地文件夹'),
                              ),
                              GlassTextButton(
                                key: ValueKey('download-delete-${record.id}'),
                                compact: true,
                                onPressed: () => _delete(record),
                                child: const AppText('删除文件'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 14),
          const _SectionTitle('可下载的网络书'),
          const SizedBox(height: 10),
          if (_downloadable.isEmpty)
            ContentPanel(
              child: AppText(
                '网络书架里还没有书。先在“网络”书架添加网盘或小说书源，再回来下载。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final novel in _downloadable) ...[
              ContentPanel(
                key: ValueKey('download-book-${novel.id}'),
                child: Row(
                  children: [
                    const ArchiveIcon(CupertinoIcons.cloud, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            novel.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          AppText(
                            '${novel.sourceLabel ?? '在线书籍'} · ${novel.author}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_busyBook == novel.id) ...[
                            const SizedBox(height: 8),
                            AppText(
                              _progress,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlassTextButton(
                          key: ValueKey('download-start-${novel.id}'),
                          compact: true,
                          onPressed: _busyBook == null
                              ? () => _download(novel)
                              : null,
                          child: AppText(_busyBook == novel.id ? '下载中' : '下载'),
                        ),
                        const SizedBox(height: 4),
                        GlassTextButton(
                          key: ValueKey('download-remove-${novel.id}'),
                          compact: true,
                          onPressed: _busyBook == null
                              ? () => _deleteAvailable(novel)
                              : null,
                          haptic: HapticCue.warning,
                          child: const AppText('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            AppText(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: AppText(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}
