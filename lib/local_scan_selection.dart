import 'package:flutter/material.dart';

import 'book_documents.dart';

/// Lets the reader choose which scanned books join the library.
///
/// Pops with the chosen tokens. A `null` result means the whole scan was
/// cancelled, and the caller finishes the scan without importing anything.
class LocalScanSelection extends StatefulWidget {
  const LocalScanSelection({super.key, required this.snapshot});

  /// Result of [BookDocuments.scanBooks], including folders and sizes.
  final BookScanSnapshot snapshot;

  @override
  State<LocalScanSelection> createState() => _LocalScanSelectionState();
}

class _LocalScanSelectionState extends State<LocalScanSelection> {
  late final Set<String> _selected = _everyToken();

  Set<String> _everyToken() => {
    for (final book in widget.snapshot.books) book.token,
  };

  bool get _allSelected =>
      _selected.length == widget.snapshot.books.length;

  void _toggle(String token, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(token);
      } else {
        _selected.remove(token);
      }
    });
  }

  void _toggleAll() {
    final every = _everyToken();
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.clear();
        _selected.addAll(every);
      }
    });
  }

  void _confirm() {
    final tokens = Set<String>.of(_selected);
    Navigator.of(context).pop(tokens);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final books = snapshot.books;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择要导入的书'),
        actions: [
          TextButton(
            key: const ValueKey('scan-selection-all'),
            onPressed: books.isEmpty ? null : _toggleAll,
            child: Text(_allSelected ? '全不选' : '全选'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '新书 ${books.length} 本 · 共扫描 ${snapshot.total} 本 · '
              '已存在 ${snapshot.unchanged} 本',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: books.isEmpty
                ? const Center(child: Text('没有发现待导入的书'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: books.length,
                    itemBuilder: (context, index) => _tile(books[index]),
                  ),
          ),
          _footer(theme),
        ],
      ),
    );
  }

  Widget _tile(BookScanEntry book) {
    final detail = widget.snapshot.details[book.token];
    final folder = detail?.folder ?? '';
    final size = detail?.size;
    final subtitle = [
      if (folder.isNotEmpty) folder,
      if (size != null && size > 0) _sizeLabel(size),
    ].join('  ·  ');
    return CheckboxListTile(
      key: ValueKey('scan-book-${book.token}'),
      value: _selected.contains(book.token),
      onChanged: (selected) => _toggle(book.token, selected ?? false),
      title: Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }

  Widget _footer(ThemeData theme) {
    final warnings = widget.snapshot.warnings;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${warnings.first}'
                  '${warnings.length > 1 ? '（共 ${warnings.length} 条提示）' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text('已选 ${_selected.length} / '
                      '${widget.snapshot.books.length} 本'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const ValueKey('scan-selection-import'),
                  onPressed: _selected.isEmpty ? null : _confirm,
                  child: const Text('导入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(kilobytes < 10 ? 1 : 0)} KB';
  }
  final megabytes = kilobytes / 1024;
  return '${megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0)} MB';
}
