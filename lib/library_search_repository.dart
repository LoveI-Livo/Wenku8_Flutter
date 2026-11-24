import 'catalog.dart';
import 'book_search.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'offline_repository.dart';
import 'bookshelf_scope.dart';
import 'cloud_catalog_search.dart';

/// Feeds the same search presentation as discovery, with a library-only data
/// scope. Missing legacy snapshots resolve at bounded concurrency, not on each
/// input frame; existing metadata is used without network requests.
class LibrarySearchRepository extends NovelRepository {
  LibrarySearchRepository({
    required this.source,
    required this.state,
    this.local,
    this.localOnly = false,
    this.cachedOnly,
  });
  final NovelRepository source;
  final LibraryState state;
  final LocalBookStore? local;
  final bool localOnly;
  final bool Function()? cachedOnly;
  final Map<int, Future<Novel?>> _pending = {};
  @override
  Future<List<Novel>> list() async {
    if (localOnly) return local?.books ?? const [];
    final offline = source is OfflineNovelRepository
        ? source as OfflineNovelRepository
        : null;
    final cached = cachedOnly?.call() ?? false;
    if ((cached || state.combinedShelf) && offline != null) {
      await offline.cache.load();
    }
    final ids = bookshelfIds(state, offline, readableOnly: cached).toList(),
        found = <int, Novel>{};
    final missing = <int>[];
    for (final id in ids) {
      final known =
          local?.book(id) ??
          offline?.cache.book(id)?.novel ??
          state.cachedNovel(id);
      if (known != null) {
        found[id] = known;
      } else {
        missing.add(id);
      }
    }
    var cursor = 0;
    Future<void> resolve() async {
      while (cursor < missing.length) {
        final id = missing[cursor++];
        try {
          final book = await _pending.putIfAbsent(id, () => source.find(id));
          if (book != null) {
            found[id] = book;
            await state.rememberNovel(book);
          }
        } catch (_) {
          _pending.remove(id);
          rethrow;
        }
      }
    }

    await Future.wait(
      List.generate(missing.length.clamp(0, 4), (_) => resolve()),
    );
    final books = [
      for (final id in ids)
        if (found[id] != null) found[id]!,
    ];
    books.sort((a, b) {
      final order = (state.positionFor(b.id)?.updatedAt ?? 0).compareTo(
        state.positionFor(a.id)?.updatedAt ?? 0,
      );
      return order != 0 ? order : a.title.compareTo(b.title);
    });
    return books;
  }

  @override
  Future<List<Novel>> search(String query) => _search(query);

  @override
  Future<NovelPage> searchFilteredPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) async => NovelPage.fromItems(await _search(query, field: field), page);

  Future<List<Novel>> _search(
    String query, {
    BookSearchField field = BookSearchField.all,
  }) async {
    final pattern = BookSearch(query, field: field);
    final books = await list();
    final organization = pattern.terms.isEmpty ? null : state.organization;
    final localMatches = books
        .where(
          (book) => pattern.matches(
            title: book.title,
            author: book.author,
            tags: book.genre,
            id: '${book.id}',
            classification: organization != null
                ? organization.nameOf(organization.groupOf(book.id))
                : '',
          ),
        )
        .toList();
    if (pattern.terms.isEmpty) return localMatches;
    final libraryFuture = () async {
      try {
        final page = await source.searchFilteredPage(query, field: field);
        return page.items;
      } catch (error) {
        // 网络或登录暂时失败时仍返回书架和已识别网盘书，避免整页空白；
        // 三类都没有结果时再把真实错误抛给搜索页展示。
        return <Novel>[];
      }
    }();
    final cloudFuture = CloudCatalogSearch.instance.search(query);
    final results = await Future.wait([libraryFuture, cloudFuture]);
    final libraryMatches = results[0];
    final cloud = results[1];
    final ids = {
      for (final book in localMatches) book.id,
      for (final book in libraryMatches) book.id,
    };
    return [
      ...localMatches,
      for (final book in libraryMatches)
        if (ids.add(book.id))
          if (pattern.matches(
            title: book.title,
            author: book.author,
            tags: book.genre,
            id: '${book.id}',
            classification: '',
          ))
            book,
      for (final book in cloud)
        if (ids.add(book.id))
          if (pattern.matches(
            title: book.title,
            author: book.author,
            tags: book.genre,
            id: '${book.id}',
            classification: '',
          ))
            book,
    ];
  }

  @override
  Future<Novel?> find(int id) => source.find(id);
  @override
  Future<Novel> detail(Novel novel) => source.detail(novel);
  @override
  Future<List<NovelChapter>> chapters(int id) => source.chapters(id);
  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) =>
      source.chapterContent(novelId, chapter);
}
