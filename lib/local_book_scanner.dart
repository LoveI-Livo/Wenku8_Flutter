import 'book_documents.dart';

/// What one scan-and-import run achieved.
///
/// [report] is the durable report of the last book this run imported. Its type
/// belongs to the import batch, so it stays a type parameter here: the import
/// hub only renders [summary], while callers that know the batch type read
/// [report] without a cast.
class LocalScanResult<T> {
  LocalScanResult({
    required this.report,
    required this.total,
    required this.unchanged,
    this.pending = 0,
    this.imported = 0,
    this.failed = 0,
    this.warnings = const [],
  });

  /// The last durable import report, or `null` when nothing was imported.
  final T? report;

  /// Books the scanner found; equals the snapshot size when the host is silent.
  final int total;

  /// Books the scanner already knew and did not report again.
  final int unchanged;

  /// Selected books the run never reached, for example after leaving the page.
  final int pending;

  /// Books handed to the importer successfully.
  final int imported;

  /// Books whose import threw; the reason is kept in [warnings].
  final int failed;

  /// Reader facing notes: scanner warnings first, then one line per failure.
  final List<String> warnings;

  /// One line the import hub can show without knowing the batch report type.
  String get summary {
    final parts = <String>[
      if (total > 0) '扫描到 $total 本',
      if (unchanged > 0) '$unchanged 本已存在',
      if (imported > 0) '导入 $imported 本',
      if (failed > 0) '$failed 本失败',
      if (pending > 0) '$pending 本未处理',
    ];
    return parts.isEmpty ? '没有发现可以导入的书' : parts.join('，');
  }
}

/// Imports the [selectedTokens] of [snapshot] one book at a time.
///
/// [importSource] owns the durable write for a single selection; this function
/// stages the book, hands it over, releases the staged copy and marks the token
/// as handled. [current] stops the run as soon as the page that started it is
/// gone, [onProgress] reports `done / total`, and a failing book is collected
/// in [LocalScanResult.warnings] instead of aborting the batch.
Future<LocalScanResult<T>> scanLocalBooks<T>({
  required BookDocuments documents,
  required BookScanSnapshot snapshot,
  required Set<String> selectedTokens,
  required bool linkText,
  required Future<T> Function(BookDocumentSelection source) importSource,
  required bool Function() current,
  required void Function(int done, int total) onProgress,
}) async {
  final entries = <BookScanEntry>[
    for (final book in snapshot.books)
      if (selectedTokens.contains(book.token)) book,
  ];
  final warnings = <String>[...snapshot.warnings];
  T? report;
  var imported = 0;
  var failed = 0;
  var done = 0;
  onProgress(done, entries.length);
  try {
    for (final book in entries) {
      if (!current()) break;
      BookDocumentSelection? source;
      try {
        source = await _openSource(documents, book, linkText: linkText);
        report = await importSource(source);
        imported += 1;
        await _mark(documents, book.token);
      } catch (error) {
        failed += 1;
        warnings.add('${book.name}：${_reason(error)}');
      } finally {
        if (source != null) await _release(documents, source);
        done += 1;
        onProgress(done, entries.length);
      }
    }
  } finally {
    try {
      await documents.finishBookScan();
    } catch (_) {
      // The scan session also ends when the page that owns it closes.
    }
  }
  final remaining = entries.length - done;
  return LocalScanResult<T>(
    report: report,
    total: snapshot.total > 0 ? snapshot.total : snapshot.books.length,
    unchanged: snapshot.unchanged,
    pending: remaining > 0 ? remaining : 0,
    imported: imported,
    failed: failed,
    warnings: warnings,
  );
}

/// Stages [book], or keeps a reference to its original text file.
Future<BookDocumentSelection> _openSource(
  BookDocuments documents,
  BookScanEntry book, {
  required bool linkText,
}) async {
  if (linkText && _isText(book.name)) {
    try {
      return await documents.linkScanBook(book.token);
    } catch (_) {
      // Hosts without a linked text index fall back to a staged copy.
    }
  }
  return documents.stageScanBook(book.token);
}

bool _isText(String name) => name.toLowerCase().endsWith('.txt');

/// Marks the token so the next scan reports the book as unchanged.
Future<void> _mark(BookDocuments documents, String token) async {
  try {
    await documents.markScanBook(token);
  } catch (_) {
    // The book is imported; a missing mark only repeats it in the next scan.
  }
}

/// Releases a staged copy. Linked references belong to the importer.
Future<void> _release(
  BookDocuments documents,
  BookDocumentSelection source,
) async {
  if (source.path == null) return;
  try {
    await documents.releaseBooks([source]);
  } catch (_) {
    // Cache cleanup is retried when the batch closes.
  }
}

String _reason(Object error) {
  final text = error is FormatException ? error.message : '$error';
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return '导入失败';
  return line.length > 80 ? '${line.substring(0, 80)}…' : line;
}
