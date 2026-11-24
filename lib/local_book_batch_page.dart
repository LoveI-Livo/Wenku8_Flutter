import 'package:flutter/material.dart';

import 'book_categories.dart';
import 'local_library_preferences.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';

/// Opens the batch manager for the local library.
///
/// The page only uses durable [LocalBookStore] operations. [library] supplies
/// the shelf state used to describe hidden books; deleting a book never
/// touches the user's original file outside the library folder.
Future<void> openLocalBookBatch(
  BuildContext context, {
  required LocalBookStore books,
  required LibraryState library,
  Set<int>? selected,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => LocalBookBatchPage(
        books: books,
        library: library,
        initialSelected: selected ?? const <int>{},
      ),
    ),
  );
}

class LocalBookBatchPage extends StatefulWidget {
  const LocalBookBatchPage({
    super.key,
    required this.books,
    required this.library,
    this.initialSelected = const <int>{},
  });

  final LocalBookStore books;
  final LibraryState library;
  final Set<int> initialSelected;

  @override
  State<LocalBookBatchPage> createState() => _LocalBookBatchPageState();
}

class _LocalBookBatchPageState extends State<LocalBookBatchPage> {
  late final Set<int> _selected = <int>{...widget.initialSelected};
  bool _busy = false;

  List<Novel> get _all => widget.books.books;

  bool get _allSelected {
    final books = _all;
    return books.isNotEmpty &&
        books.every((book) => _selected.contains(book.id));
  }

  void _toggle(int id, bool selected) {
    if (_busy) return;
    setState(() {
      if (selected) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _selectAll() {
    if (_busy) return;
    final books = _all;
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
      for (final book in _all) {
        if (!_selected.remove(book.id)) _selected.add(book.id);
      }
    });
  }

  Future<void> _assign(Set<int> ids) async {
    if (_busy || ids.isEmpty) return;
    final organization = widget.library.organization;
    final group = await chooseBookCategory(
      context,
      organization,
      bookIds: ids,
      reduceMotion: widget.library.reduceMotion,
    );
    if (!mounted || group == null) return;
    setState(() => _busy = true);
    try {
      await organization.assignMany(ids, group);
      if (!mounted) return;
      final name = group == LocalLibraryPreferences.unfiled
          ? '未分类'
          : organization.groups[group] ?? group;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已把 ${ids.length} 本书加入「$name」')));
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

  Future<void> _deleteSelected() async {
    if (_busy) return;
    final store = widget.books;
    final ids = <int>[
      for (final book in store.books)
        if (_selected.contains(book.id)) book.id,
    ];
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('删除本地书'),
        content: Text('将删除选中的 ${ids.length} 本本地书及阅读缓存，无法恢复。书库外的原始文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final skipped = <String>[];
    var removed = 0;
    for (final id in ids) {
      final name = store.book(id)?.title ?? '这本书';
      try {
        await store.remove(id);
        removed++;
        _selected.remove(id);
      } on FormatException catch (error) {
        skipped.add('《$name》：${error.message}');
      } catch (_) {
        skipped.add('《$name》：删除未完成，请稍后重试。');
      }
    }
    if (!mounted) return;
    _selected.removeWhere((id) => store.book(id) == null);
    setState(() => _busy = false);
    final String message;
    if (removed == 0) {
      message = skipped.isEmpty ? '没有删除任何书籍。' : skipped.first;
    } else if (skipped.isEmpty) {
      message = '已删除 $removed 本本地书。';
    } else {
      message = '已删除 $removed 本，${skipped.length} 本未能删除：${skipped.first}';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _row(BuildContext context, Novel book) {
    final theme = Theme.of(context);
    final series = widget.books.seriesFor(book.id);
    final hidden = !widget.library.localBookVisible(book.id);
    final details = <String>[
      book.author.trim().isEmpty ? '本地书籍' : book.author.trim(),
      if (series != null) '合订本 ${series.volumes.length} 卷',
      if (hidden) '已从书架隐藏',
    ];
    return CheckboxListTile(
      key: ValueKey<String>('local-batch-book-${book.id}'),
      value: _selected.contains(book.id),
      onChanged: _busy ? null : (value) => _toggle(book.id, value == true),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        details.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      secondary: series == null
          ? null
          : Icon(
              Icons.library_books_outlined,
              color: theme.colorScheme.primary,
            ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.books,
    builder: (context, _) {
      final theme = Theme.of(context);
      final books = widget.books.books;
      final selected = books
          .where((book) => _selected.contains(book.id))
          .length;
      return Scaffold(
        appBar: AppBar(
          title: const Text('批量整理本地书'),
          actions: [
            IconButton(
              key: const ValueKey<String>('local-batch-assign-all'),
              tooltip: '全部加入分类',
              onPressed: _busy || books.isEmpty
                  ? null
                  : () => _assign({for (final book in books) book.id}),
              icon: const Icon(Icons.drive_file_move_outline),
            ),
            IconButton(
              key: const ValueKey<String>('local-batch-select-all'),
              tooltip: _allSelected ? '取消全选' : '全选',
              onPressed: _busy || books.isEmpty ? null : _selectAll,
              icon: Icon(_allSelected ? Icons.deselect : Icons.select_all),
            ),
            IconButton(
              key: const ValueKey<String>('local-batch-invert'),
              tooltip: '反选',
              onPressed: _busy || books.isEmpty ? null : _invert,
              icon: const Icon(Icons.flip_to_back),
            ),
          ],
        ),
        body: books.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '书库里还没有本地书籍。',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
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
                key: const ValueKey<String>('local-batch-assign'),
                onPressed: _busy || selected == 0
                    ? null
                    : () => _assign({
                        for (final book in books)
                          if (_selected.contains(book.id)) book.id,
                      }),
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('加入分类'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey<String>('local-batch-delete'),
                onPressed: _busy || selected == 0 ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: Text(_busy ? '正在删除' : '删除'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
