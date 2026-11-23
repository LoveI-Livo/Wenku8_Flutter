part of 'cloud_sources.dart';

/// 网页书源的通用读取器。
///
/// 很多小说站没有公开 API，只提供目录页和章节页。这里不绑定具体站点，
/// 而是按常见结构识别书名、作者、简介、目录和正文；遇到不认识的结构时
/// 保留原文页面，避免把整本书误判成空内容。
class WebNovelDocument {
  const WebNovelDocument({
    this.title,
    this.author,
    this.summary,
    this.coverUrl,
    this.chapters = const [],
    this.singlePage = false,
  });

  final String? title;
  final String? author;
  final String? summary;
  final String? coverUrl;
  final List<WebNovelChapter> chapters;
  final bool singlePage;
  bool get hasContent => singlePage || chapters.isNotEmpty;
}

class WebNovelChapter {
  const WebNovelChapter(this.title, this.url);
  final String title;
  final String url;
}

class WebNovelReader {
  WebNovelReader._();

  static const _maxPageBytes = 12 * 1024 * 1024;
  static final _chapterTitle = RegExp(
    r'^(?:第[\d一二三四五六七八九十百千万零两〇]+[章节回卷部篇]|[序楔引]|Chapter\s+\d+|正文)',
    caseSensitive: false,
  );
  static final _chapterHref = RegExp(
    r'(?:chapter|read|content)(?:\d+|/|\.)',
    caseSensitive: false,
  );
  static final _navWords = RegExp(
    r'^(?:首页|登录|注册|排行|分类|全部|上一页|下一页|目录|更多|搜索|返回|评论|收藏|推荐|最新|章节|书签|加入书架|开始阅读|继续阅读|手机版|电脑版|TXT下载|下载|作者|简介|详情)$',
  );

  static Future<CloudBookListing> catalog(
    String url, {
    String cookie = '',
    String authorization = '',
    bool allowHttp = false,
  }) async {
    final page = await _fetch(
      url,
      cookie: cookie,
      authorization: authorization,
      allowHttp: allowHttp,
    );
    return catalogFromHtml(page.body, page.uri);
  }

  static CloudBookListing catalogFromHtml(String body, Uri uri) {
    final doc = html.parse(body);
    final chapters = _chapterLinks(doc, uri);
    if (chapters.length >= 2) {
      final info = _bookInfo(doc, uri);
      return CloudBookListing([
        CloudBookEntry(
          id: uri.toString(),
          name: info.title ?? _cleanTitle(doc, uri),
          folder: false,
          size: 0,
          author: info.author ?? '',
          summary: info.summary ?? '',
          book: true,
        ),
      ], nextPage: null);
    }
    final entries = _catalogLinks(doc, uri);
    if (entries.isEmpty) {
      throw const CloudSourceFailure('这个网页里没有找到可阅读的书籍或目录');
    }
    return CloudBookListing(entries);
  }

  static Future<WebNovelDocument> inspect(
    String url, {
    String cookie = '',
    String authorization = '',
    bool allowHttp = false,
  }) async {
    final page = await _fetch(
      url,
      cookie: cookie,
      authorization: authorization,
      allowHttp: allowHttp,
    );
    final doc = html.parse(page.body);
    final info = _bookInfo(doc, page.uri);
    final title = info.title ?? _cleanTitle(doc, page.uri);
    final chapters = _chapterLinks(doc, page.uri);
    if (chapters.length >= 2) {
      return WebNovelDocument(
        title: title,
        author: info.author,
        summary: info.summary,
        coverUrl: info.coverUrl,
        chapters: chapters,
      );
    }
    final content = _extractContent(doc);
    if (content.length >= 120) {
      return WebNovelDocument(
        title: title,
        author: info.author,
        summary: info.summary,
        coverUrl: info.coverUrl,
        chapters: [WebNovelChapter(title.isEmpty ? '正文' : title, page.uri.toString())],
        singlePage: true,
      );
    }
    throw const CloudSourceFailure('这个网页既没有目录，也没有可识别的正文');
  }

  static Future<String> content(
    String url, {
    String cookie = '',
    String authorization = '',
    bool allowHttp = false,
  }) async {
    final page = await _fetch(
      url,
      cookie: cookie,
      authorization: authorization,
      allowHttp: allowHttp,
    );
    final text = _extractContent(html.parse(page.body));
    if (text.isEmpty) throw const CloudSourceFailure('章节网页没有可读取的正文');
    return text;
  }

  static Future<({String body, Uri uri})> _fetch(
    String url, {
    required String cookie,
    required String authorization,
    required bool allowHttp,
  }) async {
    final target = Uri.tryParse(url.trim());
    if (target == null) throw const CloudSourceFailure('书源网页地址无效');
    CloudHttp.validateUrl(target, allowHttp: allowHttp);
    final client = CloudHttp();
    try {
      final response = await client.request(
        'GET',
        target,
        headers: (requested) => {
          HttpHeaders.acceptHeader:
              'text/html,application/xhtml+xml,application/json,application/xml,text/xml,*/*',
          if (CloudHttp.sameOrigin(requested, target) &&
              cookie.trim().isNotEmpty)
            HttpHeaders.cookieHeader: cookie.trim(),
          if (CloudHttp.sameOrigin(requested, target) &&
              authorization.trim().isNotEmpty)
            HttpHeaders.authorizationHeader: authorization.trim(),
        },
        redirects: true,
        allowHttp: allowHttp,
        redirectMessage: '书源网页发生跳转，请填写最终网页地址',
      );
      final bytes = await client.bytes(response, limit: _maxPageBytes);
      final body = _decode(bytes, response.headers.contentType);
      return (body: body, uri: target);
    } finally {
      client.close();
    }
  }

  static String decodeBytes(Uint8List bytes, ContentType? contentType) =>
      _decode(bytes, contentType);

  static String _decode(Uint8List bytes, ContentType? contentType) {
    final header = contentType?.parameters['charset']?.toLowerCase();
    final head = utf8.decode(
      bytes.take(2048).toList(growable: false),
      allowMalformed: true,
    );
    final meta = RegExp(
      "(?:charset|encoding)\\s*=\\s*[\"']?([a-zA-Z0-9_\\-]+)",
      caseSensitive: false,
    ).firstMatch(head)?.group(1)?.toLowerCase();
    final name = header ?? meta;
    if (name == null || name == 'utf-8' || name == 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      final encoding = Charset.getByName(name);
      if (encoding != null) return encoding.decode(bytes);
    } catch (_) {
      // 某些页面声明了错误编码，继续用宽松 UTF-8 读取。
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static _BookInfo _bookInfo(Document doc, Uri base) {
    String? meta(String key) {
      for (final node in doc.querySelectorAll('meta')) {
        final property = node.attributes['property'] ?? node.attributes['name'];
        if (property != null &&
            property.toLowerCase() == key.toLowerCase()) {
          final value = node.attributes['content']?.trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
      return null;
    }

    String? firstText(String selector) {
      for (final element in doc.querySelectorAll(selector)) {
        final value = _text(element).trim();
        if (value.isNotEmpty && value.length <= 1200) return value;
      }
      return null;
    }

    final title =
        meta('og:title') ??
        meta('twitter:title') ??
        firstText('h1') ??
        firstText('.book-name,.book-title,.title');
    final author =
        meta('author') ??
        meta('og:novel:author') ??
        _authorFromText(doc) ??
        firstText('.author,.book-author,.novel-author');
    final summary =
        meta('description') ??
        meta('og:description') ??
        firstText(
          '.intro,.summary,.description,.book-intro,.book-desc,.novel-intro,#intro,#summary',
        );
    final cover = meta('og:image');
    return _BookInfo(
      title: _cleanTitleText(title),
      author: _cleanAuthor(author),
      summary: _cleanSummary(summary),
      coverUrl: cover == null ? null : base.resolve(cover).toString(),
    );
  }

  static String? _authorFromText(Document doc) {
    final root = doc.body ?? doc.documentElement;
    if (root == null) return null;
    final text = _text(root).replaceAll('\u3000', ' ');
    final match = RegExp(
      r'作\s*者\s*[：:]\s*([^\s|/，,；;]{1,40})',
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  static String _cleanAuthor(String? value) {
    if (value == null) return '';
    return value
        .replaceFirst(RegExp(r'^作\s*者\s*[：:]\s*'), '')
        .trim();
  }

  static String? _cleanSummary(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    return text.length <= 1200 ? text : '${text.substring(0, 1200)}…';
  }

  static String _cleanTitle(Document doc, Uri base) {
    final value =
        _cleanTitleText(doc.querySelector('h1')?.text) ??
        _cleanTitleText(doc.querySelector('title')?.text) ??
        _cleanTitleText(base.pathSegments.isEmpty
            ? null
            : Uri.decodeComponent(base.pathSegments.last));
    return value ?? '网页书籍';
  }

  static String? _cleanTitleText(String? value) {
    if (value == null) return null;
    var text = value.replaceAll('\u3000', ' ').trim();
    if (text.isEmpty) return null;
    text = text.replaceFirst(
      RegExp(r'\s*[_|\-–—]\s*(?:最新章节|全文阅读|无弹窗|笔趣阁|小说|小说网|在线阅读).*$'),
      '',
    );
    text = text.replaceFirst(RegExp(r'\s*_\s*$'), '');
    return text.trim().isEmpty ? null : text.trim();
  }

  static List<WebNovelChapter> _chapterLinks(Document doc, Uri base) {
    final result = <String, WebNovelChapter>{};
    for (final anchor in doc.querySelectorAll('a')) {
      if (_insideChrome(anchor)) continue;
      final href = anchor.attributes['href']?.trim();
      final title = _text(anchor).trim();
      if (href == null || href.isEmpty || title.isEmpty) continue;
      if (href.startsWith('#') ||
          href.startsWith('javascript:') ||
          href.startsWith('mailto:') ||
          href.startsWith('tel:')) {
        continue;
      }
      if (title.length > 100 ||
          !_chapterTitle.hasMatch(title) && !_chapterHref.hasMatch(href)) {
        continue;
      }
      if (title.contains('最新章节') || title.contains('章节目录')) continue;
      final uri = base.resolve(href);
      if (uri.scheme != 'http' && uri.scheme != 'https') continue;
      result.putIfAbsent(
        uri.toString(),
        () => WebNovelChapter(title, uri.toString()),
      );
      if (result.length >= 3000) break;
    }
    return result.values.toList(growable: false);
  }

  static List<CloudBookEntry> _catalogLinks(Document doc, Uri base) {
    final result = <String, CloudBookEntry>{};
    var total = 0;
    for (final anchor in doc.querySelectorAll('a')) {
      if (_insideChrome(anchor)) continue;
      final href = anchor.attributes['href']?.trim();
      final title = _text(anchor).trim();
      if (href == null || href.isEmpty || title.isEmpty) continue;
      if (href.startsWith('#') ||
          href.startsWith('javascript:') ||
          href.startsWith('mailto:') ||
          href.startsWith('tel:') ||
          _navWords.hasMatch(title)) {
        continue;
      }
      if (title.length < 2 || title.length > 80) continue;
      final uri = base.resolve(href);
      if (uri.scheme != 'http' && uri.scheme != 'https') continue;
      if (uri.toString() == base.toString()) continue;
      total++;
      if (!_looksLikeBookHref(href) && title.length < 4) continue;
      result.putIfAbsent(
        uri.toString(),
        () => CloudBookEntry(
          id: uri.toString(),
          name: title,
          folder: false,
          size: 0,
          book: true,
        ),
      );
      if (result.length >= 120) break;
    }
    if (result.isEmpty && total > 0) {
      // 目录页链接不带常见路径时，保留标题足够长的条目，避免整页为空。
      for (final anchor in doc.querySelectorAll('a')) {
        final href = anchor.attributes['href']?.trim();
        final title = _text(anchor).trim();
        if (href == null || title.length < 4 || _navWords.hasMatch(title)) {
          continue;
        }
        final uri = base.resolve(href);
        if (uri.scheme != 'http' && uri.scheme != 'https') continue;
        result.putIfAbsent(
          uri.toString(),
          () => CloudBookEntry(
            id: uri.toString(),
            name: title,
            folder: false,
            size: 0,
            book: true,
          ),
        );
        if (result.length >= 60) break;
      }
    }
    return result.values.toList(growable: false);
  }

  static bool _looksLikeBookHref(String href) => RegExp(
    r'(?:book|novel|read|info|content|article|txt|/b/|/n/|/p/)(?:[\d/._-]|$)',
    caseSensitive: false,
  ).hasMatch(href);

  static bool _insideChrome(Element element) {
    var current = element.parent;
    while (current != null) {
      final cls = '${current.attributes['class'] ?? ''} '
          '${current.attributes['id'] ?? ''}'.toLowerCase();
      if (RegExp(r'(?:nav|menu|header|footer|comment|recommend|related|share|advert|\bad\b)').hasMatch(cls)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  static String _extractContent(Document doc) {
    const selectors = [
      'article',
      'main',
      '#chaptercontent',
      '#chapter-content',
      '#content',
      '.chapter-content',
      '.chaptercontent',
      '.read-content',
      '.readcontent',
      '.entry-content',
      '.post-content',
      '.article-content',
      '.book-content',
      '.content',
    ];
    Element? best;
    var bestScore = 0;
    for (final selector in selectors) {
      for (final element in doc.querySelectorAll(selector)) {
        if (_insideChrome(element)) continue;
        final score = _contentScore(element);
        if (score > bestScore) {
          best = element;
          bestScore = score;
        }
      }
    }
    final body = doc.body;
    if (best == null && body != null) {
      best = body;
      bestScore = _contentScore(body);
    }
    if (best == null || bestScore < 80) return '';
    _stripNoise(best);
    final paragraphs = best.querySelectorAll('p');
    if (paragraphs.isNotEmpty) {
      final values = [
        for (final p in paragraphs)
          if (_text(p).trim().isNotEmpty) _text(p).trim(),
      ];
      if (values.length >= 2) return values.join('\n\n');
    }
    return _htmlText(best);
  }

  static int _contentScore(Element element) {
    final text = _text(element).trim();
    if (text.isEmpty) return 0;
    final paragraphs = element.querySelectorAll('p').length;
    var links = 0;
    for (final anchor in element.querySelectorAll('a')) {
      links += _text(anchor).length;
    }
    return text.length + paragraphs * 80 - links * 2;
  }

  static void _stripNoise(Element element) {
    for (final child in element.querySelectorAll(
      'script,style,noscript,iframe,svg,form,header,footer,nav,aside,'
      '.nav,.menu,.header,.footer,.comment,.comments,.recommend,.related,'
      '.share,.ad,.ads,.advert,.advertisement',
    )) {
      child.remove();
    }
  }

  static String _htmlText(Element element) {
    final out = StringBuffer();
    void walk(Node node) {
      if (node is Text) {
        out.write(node.text);
        return;
      }
      if (node is! Element) return;
      final tag = node.localName?.toLowerCase() ?? '';
      if (const {
        'script',
        'style',
        'noscript',
        'iframe',
        'svg',
        'form',
      }.contains(tag)) {
        return;
      }
      if (tag == 'br') {
        out.write('\n');
        return;
      }
      final block = const {
        'p',
        'div',
        'section',
        'article',
        'li',
        'tr',
        'h1',
        'h2',
        'h3',
        'h4',
        'blockquote',
      }.contains(tag);
      if (block && out.length > 0 && !out.toString().endsWith('\n')) {
        out.write('\n');
      }
      for (final child in node.children) {
        walk(child);
      }
      if (block) out.write('\n');
    }

    walk(element);
    return _normalizeText(out.toString());
  }

  static String _text(Node node) => _normalizeText(node.text ?? '');

  static String _normalizeText(String value) {
    final lines = value
        .replaceAll('\r', '')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t\u3000]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
    return lines;
  }
}

class _BookInfo {
  const _BookInfo({
    this.title,
    this.author,
    this.summary,
    this.coverUrl,
  });
  final String? title;
  final String? author;
  final String? summary;
  final String? coverUrl;
}
