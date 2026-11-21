import 'book_documents.dart';
import 'catalog.dart';
import 'local_books.dart';

/// One file that could not be imported, with a message suitable for display.
typedef LocalImportFailure = ({String name, String message});

/// A non-fatal remark about a file that was imported (for example a category
/// that could not be saved). Kept separate from failures: the book is durable.
typedef LocalImportNotice = ({String name, String message});

/// The outcome of one batch import. Callers read the counts, the imported book
/// ids and the two human-readable lists; the report never throws by itself.
class LocalImportReport {
  const LocalImportReport({
    this.bookIds = const [],
    this.added = 0,
    this.existing = 0,
    this.failures = const [],
    this.notices = const [],
  });

  /// Every imported book, in import order. A book that already existed is
  /// included as well, so review screens can group all touched volumes.
  final List<int> bookIds;
  final int added;
  final int existing;
  final List<LocalImportFailure> failures;
  final List<LocalImportNotice> notices;

  int get failed => failures.length;
  int get succeeded => added + existing;

  /// Files that were attempted: new and existing books plus failures.
  int get total => added + existing + failures.length;

  bool get isEmpty => bookIds.isEmpty && failures.isEmpty && notices.isEmpty;

  String get summary {
    final parts = <String>[
      if (added > 0) '新增 $added 本',
      if (existing > 0) '已在书库 $existing 本',
      if (failures.isNotEmpty) '${failures.length} 个文件未能导入',
    ];
    if (parts.isEmpty) {
      return notices.isEmpty ? '没有需要导入的本地书籍。' : '导入完成，有 ${notices.length} 条提示。';
    }
    return '导入完成：${parts.join('，')}。';
  }
}

/// A set of freshly imported volumes that appear to belong to one series.
class LocalImportGroup {
  const LocalImportGroup({
    required this.seed,
    required this.title,
    required this.volumes,
    this.targetId,
    this.needsTarget = false,
  });

  /// The first imported volume. It identifies the group and is the book the
  /// series editor opens from the review screen.
  final int seed;

  /// The merged title suggested for this group.
  final String title;

  /// An already existing series this group could join, when one was found.
  final int? targetId;

  /// True when the target cannot be applied automatically and the user has to
  /// confirm the merge in the series editor.
  final bool needsTarget;

  /// The imported volumes, in import order. The records match
  /// [LocalBookStore.saveSeries] so they can be saved without conversion.
  final List<({int bookId, String title})> volumes;

  int get volumeCount => volumes.length;
}

/// Runs one prepared batch of documents through the caller supplied import
/// callbacks. A single unreadable file is reported, never fatal for the batch.
Future<LocalImportReport> importLocalDocuments({
  required Iterable<BookDocumentSelection> selections,
  required BookDocuments documents,
  required LocalBookStore books,
  required Future<Novel> Function(String name, String path) importFile,
  Future<Novel> Function(BookDocumentSelection selection)? importSelection,
  bool releaseSources = false,
  void Function(Iterable<BookDocumentSelection> selections)? onCleanupFailed,
  void Function(int done, int total)? onProgress,
}) async {
  final items = selections.toList(growable: false);
  final known = <int>{
    for (final book in books.books) book.id,
    for (final book in books.originals) book.id,
  };
  final importedIds = <int>{};
  final failures = <LocalImportFailure>[];
  var added = 0;
  var existing = 0;
  final total = items.length;
  if (total > 0) onProgress?.call(0, total);
  for (final (index, selection) in items.indexed) {
    final name = selection.name;
    try {
      final reason = selection.error?.trim();
      if (reason != null && reason.isNotEmpty) {
        throw FormatException(reason);
      }
      final book = await _importOne(
        selection,
        importFile: importFile,
        selectionHandler: importSelection,
      );
      if (importedIds.add(book.id)) {
        if (known.contains(book.id)) {
          existing++;
        } else {
          added++;
          known.add(book.id);
        }
      }
    } catch (failure) {
      failures.add((name: name, message: _failureMessage(failure)));
    } finally {
      onProgress?.call(index + 1, total);
    }
  }
  if (releaseSources && items.isNotEmpty) {
    try {
      await documents.releaseBooks(items);
    } catch (_) {
      onCleanupFailed?.call(items);
    }
  }
  return LocalImportReport(
    bookIds: importedIds.toList(growable: false),
    added: added,
    existing: existing,
    failures: failures,
  );
}

Future<Novel> _importOne(
  BookDocumentSelection selection, {
  required Future<Novel> Function(String name, String path) importFile,
  required Future<Novel> Function(BookDocumentSelection)? selectionHandler,
}) {
  final path = selection.path;
  final derived = selection.originReference != null;
  final linked = selection.reference != null;
  if (!derived && !linked) {
    if (path == null || path.isEmpty) {
      throw const FormatException('文件尚未准备好，请重新选择后再导入。');
    }
    return importFile(selection.name, path);
  }
  final handler = selectionHandler;
  if (handler == null) {
    throw const FormatException('无法读取这个文件，请重新选择后再导入。');
  }
  return handler(selection);
}

String _failureMessage(Object failure) {
  var message = '';
  if (failure is FormatException) {
    message = failure.message.trim();
  } else {
    final text = failure.toString().trim();
    const prefix = 'Exception: ';
    message = text.startsWith(prefix)
        ? text.substring(prefix.length).trim()
        : text;
    if (message.startsWith('Instance of ')) message = '';
  }
  if (message.isEmpty) return '导入失败，请重试。';
  if (message.length > 240) return '${message.substring(0, 240)}…';
  return message;
}

/// Groups freshly imported books that look like volumes of the same series.
/// Books without a series hint, or already inside a series, are left alone.
List<LocalImportGroup> localImportGroups(
  LocalBookStore books,
  Iterable<int> bookIds,
) {
  final grouped = <String, List<int>>{};
  final seen = <int>{};
  for (final id in bookIds) {
    if (!seen.add(id)) continue;
    if (books.book(id) == null) continue;
    if (books.seriesFor(id) != null) continue;
    final key = books.seriesHint(id)?.key;
    if (key == null || key.isEmpty) continue;
    (grouped[key] ??= <int>[]).add(id);
  }
  final groups = <LocalImportGroup>[];
  for (final entry in grouped.entries) {
    final ids = entry.value;
    if (ids.length < 2) continue;
    final titles = <String>[
      for (final id in ids) books.book(id)?.title.trim() ?? '',
    ];
    int? targetId;
    var ambiguous = false;
    for (final series in books.series) {
      if (series.volumes.isEmpty) continue;
      final key = books.seriesHint(series.volumes.first.bookId)?.key;
      if (key != entry.key) continue;
      if (targetId == null) {
        targetId = series.id;
      } else if (targetId != series.id) {
        ambiguous = true;
        break;
      }
    }
    final derived = _groupTitle(titles);
    final existingTitle = targetId == null
        ? null
        : books.book(targetId)?.title.trim();
    final title = existingTitle != null && existingTitle.isNotEmpty
        ? existingTitle
        : derived;
    final volumes = <({int bookId, String title})>[
      for (final (index, id) in ids.indexed)
        (bookId: id, title: _volumeTitle(titles[index], derived, index)),
    ];
    groups.add(
      LocalImportGroup(
        seed: ids.first,
        title: title.length > 160 ? title.substring(0, 160) : title,
        volumes: List<({int bookId, String title})>.unmodifiable(volumes),
        targetId: targetId,
        // Joining an existing series is only applied through the series
        // editor: a wrong target must never rewrite another book's volumes.
        needsTarget: ambiguous || targetId != null,
      ),
    );
  }
  return groups;
}

String _groupTitle(List<String> titles) {
  final values = <String>[
    for (final title in titles)
      if (title.isNotEmpty) title,
  ];
  if (values.isEmpty) return '待整理的分卷';
  final candidate = _cleanSeriesTitle(_commonPrefix(values));
  if (candidate.isNotEmpty) return candidate;
  final cleaned = _cleanSeriesTitle(values.first);
  return cleaned.isNotEmpty ? cleaned : values.first;
}

/// The label suggested for one volume: the book title without the series
/// prefix when that leaves something meaningful, otherwise the book title.
String _volumeTitle(String bookTitle, String seriesTitle, int index) {
  var title = bookTitle.trim();
  if (seriesTitle.isNotEmpty && title.startsWith(seriesTitle)) {
    title = title
        .substring(seriesTitle.length)
        .replaceFirst(_leadingSeparators, '')
        .replaceFirst(_trailingSeparators, '')
        .trim();
  }
  if (title.isEmpty) return '第 ${index + 1} 卷';
  return title.length > 160 ? title.substring(0, 160) : title;
}

String _commonPrefix(List<String> values) {
  var prefix = values.first;
  for (final value in values.skip(1)) {
    final limit = prefix.length < value.length ? prefix.length : value.length;
    var length = 0;
    while (length < limit &&
        prefix.codeUnitAt(length) == value.codeUnitAt(length)) {
      length++;
    }
    if (length == 0) return '';
    prefix = prefix.substring(0, length);
  }
  return prefix;
}

final RegExp _volumeSuffix = RegExp(
  r'(?:[\s·•・_:：、,，.。()（）\[\]【】《》/\\|~\-—–]*'
  r'(?:'
  r'第\s*[0-9０-９一二三四五六七八九十百千万零〇两]+\s*[卷册部集篇回]?'
  r'|[vV][oO][lL]\.?\s*[0-9]+'
  r'|[卷册部集篇回]\s*[0-9０-９一二三四五六七八九十百千万零〇两]*'
  r'|[上下中]\s*[册卷部]?'
  r'|第'
  r'|[0-9０-９]+'
  r')'
  r'[\s·•・_:：、,，.。()（）\[\]【】《》/\\|~\-—–]*)$',
);

final RegExp _trailingSeparators = RegExp(
  r'[\s·•・_:：、,，.。()（）\[\]【】《》/\\|~\-—–]+$',
);

final RegExp _leadingSeparators = RegExp(
  r'^[\s·•・_:：、,，.。()（）\[\]【】《》/\\|~\-—–]+',
);

String _cleanSeriesTitle(String value) {
  var title = value.trim();
  for (var round = 0; round < 3; round++) {
    final next = title.replaceFirst(_volumeSuffix, '').trim();
    if (next == title) break;
    title = next;
  }
  title = title.replaceFirst(_trailingSeparators, '').trim();
  return title.length >= 2 ? title : '';
}
