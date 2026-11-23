import 'catalog.dart';
import 'book_search.dart';
import 'cloud_catalog_search.dart';

enum SearchSource {
  library('文库搜索'),
  cloud('网盘搜索'),
  sources('书源搜索');

  const SearchSource(this.label);
  final String label;
}

/// Keeps the app's single search surface, but lets the user explicitly choose
/// which catalogue is queried. All modes delegate detail/chapter loading to the
/// same repository, so cloud hits open exactly like ordinary online books.
class ScopedSearchRepository extends NovelRepository {
  ScopedSearchRepository({required this.source, required this.scope});
  final NovelRepository source;
  final SearchSource scope;

  /// null 表示全部来源；网盘为 CloudSourceKind.name，书源为 rss:<url>。
  String? targetKey;

  @override
  Future<List<Novel>> list() => source.list();

  @override
  Future<Novel?> find(int id) => source.find(id);

  @override
  Future<Novel> detail(Novel novel) => source.detail(novel);

  @override
  Future<List<NovelChapter>> chapters(int id) => source.chapters(id);

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) =>
      source.chapterContent(novelId, chapter);

  @override
  Future<List<Novel>> search(String query) async =>
      (await searchFilteredPage(query, field: BookSearchField.all)).items;

  @override
  Future<NovelPage> searchPage(
    String query, {
    int page = 1,
    bool refresh = false,
  }) => searchFilteredPage(query, page: page, refresh: refresh);

  @override
  Future<NovelPage> searchFilteredPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) async {
    if (scope == SearchSource.library) {
      return source.searchFilteredPage(
        query,
        field: field,
        page: page,
        refresh: refresh,
      );
    }
    final text = query.trim();
    if (text.isEmpty) return const NovelPage(items: [], page: 1);
    final cloud = await CloudCatalogSearch.instance.search(
      text,
      scope: scope == SearchSource.cloud
          ? CloudSearchScope.netDisks
          : CloudSearchScope.sources,
      sourceKey: targetKey,
      refresh: refresh,
    );
    final pattern = BookSearch(text, field: field);
    final matches = cloud
        .where(
          (book) => pattern.matches(
            title: book.title,
            author: book.author,
            tags: book.genre,
            summary: book.summary,
            id: '${book.remoteEntryId ?? book.id}',
          ),
        )
        .toList();
    return NovelPage.fromItems(matches, page);
  }
}
