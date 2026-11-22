import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import 'book_search.dart';
import 'catalog.dart';
import 'publication_catalog.dart';
import 'tag_catalogue.dart';
import 'wenku8_client.dart';

/// Live adapter for the Wenku8 app protocol. Search, catalogue, metadata,
/// chapter lists and article bodies all come from the same account session as
/// the account page; no book files are downloaded to disk.
class LegacyWenkuRepository extends NovelRepository
    implements PublicationCatalog, ProgressiveTagCatalogue {
  LegacyWenkuRepository({Wenku8Client? client}) : client = client ?? Wenku8Client();

  final Wenku8Client client;
  final Map<int, Novel> _meta = {};
  final Map<int, List<NovelChapter>> _chapters = {};
  List<PublicationLibrary>? _libraries;

  static const _colors = [Color(0xFF334A66), Color(0xFF6B8CAE)];

  XmlDocument _xml(String body) {
    try {
      return XmlDocument.parse(body);
    } on XmlException {
      throw const FormatException('在线书目返回格式异常');
    }
  }

  String? _data(XmlElement item, String name) {
    for (final data in item.findAllElements('data')) {
      if (data.getAttribute('name') != name) continue;
      final value = data.getAttribute('value');
      if (value != null) return value;
      return data.innerText.trim();
    }
    return null;
  }

  int? _aid(XmlElement item) =>
      int.tryParse(item.getAttribute('aid') ?? item.getAttribute('id') ?? '');

  Novel _novel(int id, XmlElement item) {
    final title = _data(item, 'Title')?.trim();
    final author = _data(item, 'Author')?.trim();
    final press = _data(item, 'PressId')?.trim();
    final status = _data(item, 'BookStatus')?.trim();
    final update = _data(item, 'LastUpdate')?.trim();
    final intro = _data(item, 'IntroPreview')?.trim();
    return Novel(
      id: id,
      title: title == null || title.isEmpty ? '未命名书籍 $id' : title,
      author: author == null || author.isEmpty ? '佚名' : author,
      genre: press == null || press.isEmpty ? '轻小说' : press,
      summary: intro ?? '',
      colors: _colors,
      isComplete: status?.contains('完成') == true || status == '1',
      coverUrl: 'https://img.wenku8.com/image/${id ~/ 1000}/$id/${id}s.jpg',
      lastUpdate: update,
    );
  }

  Future<Novel> _metaFor(int id, {bool intro = false}) async {
    final cached = _meta[id];
    if (cached != null && (!intro || cached.summary.isNotEmpty)) return cached;
    final doc = _xml(await client.apiRaw('action=book&do=meta&aid=$id&t=0'));
    final item = doc.findAllElements('item').where((e) {
      return e.getAttribute('aid') == '$id' ||
          e.getAttribute('aid') == null;
    }).firstOrNull ??
        doc.rootElement;
    var novel = _novel(id, item);
    if (intro) {
      try {
        final body = await client.apiRaw(
          'action=book&do=intro&aid=$id&t=0',
          allowHtml: true,
        );
        final text = _plainText(body);
        if (text.isNotEmpty) {
          novel = Novel(
            id: novel.id,
            title: novel.title,
            author: novel.author,
            genre: novel.genre,
            summary: text,
            colors: novel.colors,
            chapters: novel.chapters,
            isComplete: novel.isComplete,
            coverUrl: novel.coverUrl,
            lastUpdate: novel.lastUpdate,
            chapterCount: novel.chapterCount,
          );
        }
      } catch (_) {}
    }
    _meta[id] = novel;
    return novel;
  }

  String _plainText(String body) {
    var source = body
        .replaceAll(RegExp(r'<!--image-->', caseSensitive: false), '\n[插图] ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    final document = html_parser.parse(source);
    final content = document.getElementById('content');
    source = content?.innerHtml ?? source;
    return html_parser.parseFragment(source).text
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  Future<List<Novel>> list() async => (await browse()).items;

  @override
  Future<Novel?> find(int id) async {
    try {
      return await _metaFor(id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Novel>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final numeric = int.tryParse(text);
    if (numeric != null) {
      final book = await _metaFor(numeric);
      return [book];
    }
    final results = await Future.wait([
      _searchApi(text, 'articlename'),
      _searchApi(text, 'author'),
    ]);
    return _dedupe([...results[0], ...results[1]]);
  }

  Future<List<Novel>> _searchApi(String text, String type) async {
    final body = await client.apiRaw(
      'action=search&searchtype=$type&searchkey=${Uri.encodeQueryComponent(text)}&t=0',
    );
    final ids = <int>[];
    for (final item in _xml(body).findAllElements('item')) {
      final id = _aid(item);
      if (id != null && id < 0x60000000 && !ids.contains(id)) ids.add(id);
    }
    final books = List<Novel?>.filled(ids.length, null);
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < ids.length) {
        final index = cursor++;
        try {
          books[index] = await _metaFor(ids[index]);
        } catch (_) {}
      }
    }
    await Future.wait([for (var i = 0; i < 5; i++) worker()]);
    return [for (final book in books) if (book != null) book];
  }

  List<Novel> _dedupe(Iterable<Novel> books) {
    final seen = <int>{};
    return [
      for (final book in books)
        if (seen.add(book.id)) book,
    ];
  }

  @override
  Future<NovelPage> searchFilteredPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return NovelPage.fromItems(const [], page);
    if (field == BookSearchField.id) {
      final aid = int.tryParse(text);
      final book = aid == null ? null : await _metaFor(aid);
      return NovelPage.fromItems(book == null ? const [] : [book], page);
    }
    final items = switch (field) {
      BookSearchField.title => await _searchApi(text, 'articlename'),
      BookSearchField.author => await _searchApi(text, 'author'),
      BookSearchField.tags => await _searchApi(text, 'articlename'),
      _ => await search(text),
    };
    return NovelPage.fromItems(items, page);
  }

  @override
  Future<NovelPage> authorPage(
    String author, {
    int page = 1,
    bool refresh = false,
  }) async => NovelPage.fromItems(
    await _searchApi(author.trim(), 'author'),
    page,
  );

  @override
  Future<Novel> detail(Novel novel) async {
    final base = await _metaFor(novel.id, intro: true);
    final chapters = await this.chapters(novel.id);
    return base.withChapters(chapters);
  }

  @override
  Future<List<NovelChapter>> chapters(int id) async {
    final cached = _chapters[id];
    if (cached != null) return cached;
    final doc = _xml(await client.apiRaw('action=book&do=list&aid=$id&t=0'));
    final chapters = <NovelChapter>[];
    for (final volume in doc.findAllElements('volume')) {
      final volumeId = int.tryParse(volume.getAttribute('vid') ?? '') ?? 0;
      final volumeTitle = volume.innerText
          .split('\n')
          .first
          .trim();
      for (final chapter in volume.findAllElements('chapter')) {
        final cid = int.tryParse(chapter.getAttribute('cid') ?? '');
        final title = chapter.innerText.trim();
        if (cid == null || title.isEmpty) continue;
        chapters.add(NovelChapter(
          title,
          '',
          id: cid,
          volumeId: volumeId,
          volumeTitle: volumeTitle,
        ));
      }
    }
    if (chapters.isEmpty) {
      for (final chapter in doc.findAllElements('chapter')) {
        final cid = int.tryParse(chapter.getAttribute('cid') ?? '');
        final title = chapter.innerText.trim();
        if (cid != null && title.isNotEmpty) {
          chapters.add(NovelChapter(title, '', id: cid));
        }
      }
    }
    _chapters[id] = List.unmodifiable(chapters);
    return _chapters[id]!;
  }

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) async {
    final body = await client.apiRaw(
      'action=book&do=text&aid=$novelId&cid=${chapter.id}&t=0',
      allowHtml: true,
    );
    return _plainText(body);
  }

  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) async {
    final doc = _xml(await client.apiRaw(
      'action=novellist&sort=${sort.apiKey}&page=$page&t=0',
    ));
    return _pageFrom(doc, page);
  }

  Future<NovelPage> _pageFrom(XmlDocument doc, int page) async {
    final ids = <int>[];
    for (final item in doc.findAllElements('item')) {
      final id = _aid(item);
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    final books = List<Novel?>.filled(ids.length, null);
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < ids.length) {
        final index = cursor++;
        try {
          final item = doc.findAllElements('item').firstWhere((e) => _aid(e) == ids[index]);
          books[index] = _novel(ids[index], item);
        } catch (_) {}
      }
    }
    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    final total = int.tryParse(
      doc.findAllElements('page').firstOrNull?.getAttribute('num') ?? '',
    );
    return NovelPage(
      items: [for (final book in books) if (book != null) book],
      page: page,
      totalPages: total,
    );
  }

  @override
  Future<List<PublicationLibrary>> publicationLibraries({bool refresh = false}) async {
    final cached = _libraries;
    if (cached != null && !refresh) return cached;
    final doc = _xml(await client.apiRaw('action=xml&item=sort&t=0'));
    final libraries = <PublicationLibrary>[];
    for (final item in doc.findAllElements('item')) {
      final id = int.tryParse(item.getAttribute('sort') ?? '');
      final name = item.innerText.trim();
      if (id != null && name.isNotEmpty) libraries.add(PublicationLibrary(id, name));
    }
    _libraries = List.unmodifiable(libraries);
    return _libraries!;
  }

  @override
  Future<NovelPage> browsePublication(
    int libraryId, {
    int page = 1,
    bool refresh = false,
  }) async {
    final doc = _xml(await client.apiRaw(
      'action=novellist&sort=$libraryId&page=$page&t=0',
    ));
    return _pageFrom(doc, page);
  }

  @override
  Future<NovelPage> tagPage(
    String tag, {
    int page = 1,
    bool refresh = false,
    bool Function()? current,
    TagProgressCallback? onProgress,
  }) async {
    final items = await search(tag);
    final result = NovelPage.fromItems(items, page);
    onProgress?.call(TagSearchProgress(items: result.items, scannedPages: 1, totalPages: 1));
    return result;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
