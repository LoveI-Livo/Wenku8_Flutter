import 'dart:async';

import 'package:flutter/material.dart';

import 'book_categories.dart';
import 'book_identity.dart';
import 'catalog.dart';
import 'cloud_document_service.dart';
import 'library_state.dart';
import 'local_library_preferences.dart';

/// 书架批量管理：自由勾选在线书，统一移出书架或加入分类。
/// 只删除书架记录和本机阅读缓存指向，不删除网盘原文件。
Future<void> openShelfBatch(
  BuildContext context, {
  required LibraryState library,
  required NovelRepository repository,
  required Set<int> ids,
  String title = '批量管理书架',
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ShelfBatchPage(
        library: library,
        repository: repository,
        ids: ids,
        title: title,
      ),
    ),
  );
}

class ShelfBatchPage extends StatefulWidget {
  const ShelfBatchPage({
    super.key,
    required this.library,
    required this.repository,
    required this.ids,
    this.title = '批量管理书架',
  });

  final LibraryState library;
  final NovelRepository repository;
  final Set<int> ids;
  final String title;

  @override
  State<ShelfBatchPage> createState() => _ShelfBatchPageState();
}

class _ShelfBatchPageState extends State<ShelfBatchPage> {
  late Set<int> _selected;
  final _removed = <int>{};
  final _resolved = <int, Novel>{};
  bool _loading = false;
  bool _busy = false;

  LibraryState get _library => widget.library;

  List<Novel> get _books {
    final known = <int, Novel>{};
    for (final id in widget.ids) {
      if (_removed.contains(id)) continue;
      final book = _library.cachedNovel(id) ?? _resolved[id];
      if (book != null) known[id] = book;
      if (isCloudBookId(id)) {
        final cloud = CloudDocumentService.instance.known(id);
        if (cloud != null) known[id] = cloud;
      }
    }
    final books = known.values.toList(growable: false)
      ..sort((a, b) => a.title.compareTo(b.title));
    return books;
  }

  Future<void> _resolveMissing() async {
    final missing = <int>[
      for (final id in widget.ids)
        if (!_removed.contains(id) &&
            (_library.cachedNovel(id) == null &&
                CloudDocumentService.instance.known(id) == null))
          id,
    ];
    if (missing.isEmpty) return;
    setState(() => _loading = true);
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < missing.length) {
        final id = missing[cursor++];
        try {
          final book = await widget.repository.find(id);
          if (book != null && mounted) _resolved[id] = book;
        } catch (_) {
          // 单本失败不阻塞其他书；页面仍可用删除书架记录。
        }
      }
    }

    await Future.wait(
      List.generate(missing.length.clamp(0, 4), (_) => worker()),
    );
    if (mounted) setState(() => _loading = false);
  }

  bool get _allSelected {
    final books = _books;
    return books.isNotEmpty &&
        books.every((book) => _selected.contains(book.id));
  }

  @override
  void initState() {
    super.initState();
    _selected = <int>{...widget.ids};
    unawaited(_resolveMissing());
  }

  void _selectAll() {
    if (_busy) return;
    final books = _books;
    setState(() {
      if (books.isNotEmpty &&
          books.every((book) => _selected.contains(book.id))) {
        _selected.clear();
      } else {
        _selected.addAll(books.map((book) => book.id));
      }
    });
  }

  void _invert() {
    if (_busy) return;
    setState(() {
      for (final book in _books) {
        if (!_selected.remove(book.id)) _selected.add(book.id);
      }
    });
  }

  Future<void> _assignCategory() async {
    if (_busy || _selected.isEmpty) return;
    final group = await chooseBookCategory(
      context,
      _library.organization,
      bookIds: _selected,
      reduceMotion: _library.reduceMotion,
    );
    if (!mounted || group == null) return;
    setState(() => _busy = true);
    try {
      await _library.organization.assignMany(_selected, group);
      if (!mounted) return;
      final name = group == LocalLibraryPreferences.unfiled
          ? '未分类'
          : _library.organization.groups[group] ?? group;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('已把 ${_selected.length} 本书加入「$name」')),
        );
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException ? error.message : '分类保存失败，请重试';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Set<int> ids) async {
    if (_busy || ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('移出 ${ids.length} 本书？'),
        content: const Text('只会删除书架记录和阅读进度入口，网盘原文件与本机缓存不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('移出书架'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    var removed = 0;
    final failures = <String>[];
    for (final id in ids) {
      try {
        await _library.setShelfMembership(id, false);
        if (isCloudBookId(id)) CloudDocumentService.instance.forget(id);
        _removed.add(id);
        _selected.remove(id);
        removed++;
      } catch (error) {
        failures.add(error is FormatException ? error.message : '移出未完成');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final message = removed == 0
        ? (failures.isEmpty ? '没有移出任何书籍。' : failures.first)
        : failures.isEmpty
        ? '已移出 $removed 本书。'
        : '已移出 $removed 本，${failures.length} 本未完成：${failures.first}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _row(BuildContext context, Novel book) => CheckboxListTile(
    key: ValueKey<String>('shelf-batch-book-${book.id}'),
    value: _selected.contains(book.id),
    onChanged: _busy
        ? null
        : (value) => setState(() {
            if (value == true) {
              _selected.add(book.id);
            } else {
              _selected.remove(book.id);
            }
          }),
    title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        book.author.trim().isEmpty ? '在线书籍' : book.author.trim(),
        book.sourceLabel?.trim() ?? '',
        isCloudBookId(book.id) ? '在线阅读 · 不占本机' : '书架收藏',
      ].where((value) => value.isNotEmpty).join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    controlAffinity: ListTileControlAffinity.leading,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _library,
    builder: (context, _) {
      final theme = Theme.of(context);
      final books = _books;
      final selected = books
          .where((book) => _selected.contains(book.id))
          .length;
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              key: const ValueKey<String>('shelf-batch-select-all'),
              tooltip: _allSelected ? '取消全选' : '全选',
              onPressed: _busy || books.isEmpty ? null : _selectAll,
              icon: Icon(_allSelected ? Icons.deselect : Icons.select_all),
            ),
            IconButton(
              key: const ValueKey<String>('shelf-batch-invert'),
              tooltip: '反选',
              onPressed: _busy || books.isEmpty ? null : _invert,
              icon: const Icon(Icons.flip_to_back),
            ),
            IconButton(
              key: const ValueKey<String>('shelf-batch-remove-all'),
              tooltip: '全部移出书架',
              onPressed: _busy || books.isEmpty
                  ? null
                  : () => _remove({for (final book in books) book.id}),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: books.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '这里还没有可批量管理的在线书籍。',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  if (_busy || _loading)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: books.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _row(context, books[index]),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected == 0 ? '未选择书籍' : '已选 $selected 本',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('shelf-batch-category'),
                onPressed: _busy || selected == 0 ? null : _assignCategory,
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('加入分类'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey<String>('shelf-batch-remove'),
                onPressed: _busy || selected == 0
                    ? null
                    : () => _remove({
                        for (final book in books)
                          if (_selected.contains(book.id)) book.id,
                      }),
                icon: const Icon(Icons.bookmark_remove_outlined),
                label: const Text('移出书架'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
