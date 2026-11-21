import 'package:flutter/material.dart';

import 'book_documents.dart';
import 'local_book_scanner.dart';

/// Entry point for the folder scanner.
///
/// The importer owns the scan itself; this page only renders the state it
/// publishes through the callbacks and forwards taps to [onScan].
class LocalScanPage extends StatefulWidget {
  const LocalScanPage({
    super.key,
    required this.documents,
    required this.changes,
    required this.isBusy,
    required this.progress,
    required this.result,
    required this.failure,
    required this.onScan,
  });

  /// Read only access to the scan folder and the scanner session.
  final BookDocuments documents;

  /// Importer notifier: rebuilds when busy, progress or result changes.
  final Listenable changes;

  /// Whether an import, including this scan, is already running.
  final bool Function() isBusy;

  /// `done / total` of the running import, or `null` while it is unknown.
  final (int, int)? Function() progress;

  /// Result of the last scan and import run.
  final LocalScanResult? Function() result;

  /// Reader facing failure of the last run.
  final String? Function() failure;

  /// Starts the scan; resolves when the importer finished or gave up.
  final Future<void> Function(BuildContext page) onScan;

  @override
  State<LocalScanPage> createState() => _LocalScanPageState();
}

class _LocalScanPageState extends State<LocalScanPage> {
  /// Read once: the folder changes from the import settings page, not here.
  late final Future<BookScanFolder?> _folder =
      widget.documents.scanFolderInfo();
  bool _starting = false;

  Future<void> _scan() async {
    if (_starting || widget.isBusy()) return;
    setState(() => _starting = true);
    try {
      await widget.onScan(context);
    } catch (_) {
      // The importer publishes failures through [widget.failure].
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描本地书籍')),
    body: AnimatedBuilder(
      animation: widget.changes,
      builder: (context, _) {
        final busy = widget.isBusy();
        final progress = widget.progress();
        final result = widget.result();
        final failure = widget.failure();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _folderCard(),
            const SizedBox(height: 16),
            _scanCard(context, busy: busy, progress: progress),
            if (failure != null) ...[
              const SizedBox(height: 16),
              _failureCard(failure),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _resultCard(context, result),
            ],
            const SizedBox(height: 24),
            _hint(context),
          ],
        );
      },
    ),
  );

  Widget _folderCard() => FutureBuilder<BookScanFolder?>(
    future: _folder,
    builder: (context, snapshot) {
      final folder = snapshot.data;
      if (folder == null) return const SizedBox.shrink();
      return Card(
        child: ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text(folder.name),
          subtitle: Text(
            !folder.readable
                ? '目录不可读取，请重新授权'
                : folder.automatic
                ? '可读取 · 进入应用时自动扫描'
                : '可读取',
          ),
          trailing: Icon(
            folder.allStorage ? Icons.storage_outlined : Icons.folder_outlined,
          ),
        ),
      );
    },
  );

  Widget _scanCard(
    BuildContext context, {
    required bool busy,
    required (int, int)? progress,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const ValueKey('local-scan-start'),
              onPressed: busy || _starting ? null : _scan,
              icon: const Icon(Icons.manage_search),
              label: Text(busy ? '正在扫描…' : '开始扫描'),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress == null || progress.$2 <= 0
                    ? null
                    : (progress.$1 / progress.$2).clamp(0.0, 1.0).toDouble(),
              ),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? '正在读取扫描目录…'
                    : '已处理 ${progress.$1} / ${progress.$2} 本',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _failureCard(String failure) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline, color: colors.onErrorContainer),
        title: Text(
          failure,
          style: TextStyle(color: colors.onErrorContainer),
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, LocalScanResult result) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(result.summary),
            subtitle: Text(
              '导入 ${result.imported} 本 · 失败 ${result.failed} 本 · '
              '未处理 ${result.pending} 本',
            ),
          ),
          if (result.warnings.isNotEmpty)
            ExpansionTile(
              key: const ValueKey('local-scan-warnings'),
              title: Text('提示 ${result.warnings.length} 条'),
              children: [
                for (final warning in result.warnings)
                  ListTile(
                    dense: true,
                    title: Text(warning, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '扫描只读取目录中的书籍文件，不会修改或删除原文件。',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
