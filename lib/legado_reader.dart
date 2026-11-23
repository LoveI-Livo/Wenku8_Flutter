part of 'cloud_sources.dart';

/// 阅读（Legado）书源规则引擎。
///
/// 这里实现的是阅读书源里最常见的 JSON/HTML 规则：`ruleSearch`、
/// `ruleBookInfo`、`ruleToc`、`ruleContent`，支持 `@` 链式选择、
/// `##正则`、`!序号`、`class./id./tag.` 简写和 `$.data.list[*]` JSON 路径。
/// 目标是让用户从阅读导入的书源能直接搜书、读目录和正文，而不是只把
/// `searchUrl` 当成一个普通网页。
final class LegadoReader {
  LegadoReader._();

  static const maxEntries = 500;

  static bool supports(CloudBookSource source) =>
      source.rules.isNotEmpty &&
      (source.rules.containsKey('ruleSearch') ||
          source.rules.containsKey('ruleToc'));

  static String encodePayload({
    required String base,
    required String bookUrl,
    required Map<String, dynamic> rules,
  }) {
    final raw = jsonEncode({'base': base, 'book': bookUrl, 'rules': rules});
    return 'legado://${base64Url.encode(utf8.encode(raw)).replaceAll('=', '')}';
  }

  static Map<String, dynamic>? decodePayload(String url) {
    if (!url.startsWith('legado://')) return null;
    try {
      final raw = base64Url.decode(base64Url.normalize(url.substring(9)));
      final value = jsonDecode(utf8.decode(raw));
      if (value is! Map) return null;
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }
  }

  static Future<CloudBookListing> search(
    CloudBookSource source,
    String query, {
    int page = 1,
    bool allowHttp = false,
    String cookie = '',
    String authorization = '',
  }) async {
    final ruleValue = source.rules['ruleSearch'];
    final rule = _ruleMap(ruleValue);
    final searchUrl = (source.rules['searchUrl'] ?? source.url).toString();
    final target = _applyUrl(searchUrl, query, page);
    final uri = Uri.tryParse(target);
    if (uri == null) throw const CloudSourceFailure('书源搜索地址无效');
    final body = await _fetch(
      uri,
      cookie: cookie,
      authorization: authorization,
      allowHttp: allowHttp,
    );
    final listRule =
        rule['bookList'] ??
        rule['list'] ??
        (ruleValue is String ? ruleValue : null);
    var items = _list(body, listRule, uri);
    if (items.isEmpty) {
      // 有些阅读书源只写了搜索地址，没有 bookList；退回通用网页目录识别。
      final generic = WebNovelReader.catalogFromHtml(body, uri).entries;
      return CloudBookListing([
        for (final entry in generic.take(maxEntries))
          CloudBookEntry(
            id: encodePayload(
              base: source.url,
              bookUrl: entry.id,
              rules: source.rules,
            ),
            name: entry.name,
            folder: false,
            book: true,
            author: entry.author,
            summary: entry.summary,
          ),
      ]);
    }
    final entries = <String, CloudBookEntry>{};
    for (final item in items) {
      if (entries.length >= maxEntries) break;
      final name = _textValue(
        item,
        rule['name'] ?? rule['bookName'] ?? rule['title'],
      );
      final book = _textValue(
        item,
        rule['bookUrl'] ?? rule['url'] ?? rule['link'],
      );
      if (name.isEmpty || book.isEmpty) continue;
      final resolved = _resolve(uri, book);
      if (resolved.isEmpty) continue;
      final author = _textValue(item, rule['author'] ?? rule['authorName']);
      final summary = _textValue(
        item,
        rule['intro'] ?? rule['summary'] ?? rule['desc'],
      );
      final id = encodePayload(
        base: source.url,
        bookUrl: resolved,
        rules: {...source.rules, 'allowHttp': allowHttp},
      );
      entries.putIfAbsent(
        id,
        () => CloudBookEntry(
          id: id,
          name: name,
          folder: false,
          book: true,
          author: author,
          summary: summary,
        ),
      );
    }
    return CloudBookListing(entries.values.toList(growable: false));
  }

  /// 打开书：读取书名/作者/简介和目录。
  static Future<({WebNovelDocument document, Map<String, dynamic> rules})>
  detail(
    String payload, {
    bool allowHttp = false,
    String cookie = '',
    String authorization = '',
  }) async {
    final decoded = decodePayload(payload);
    if (decoded == null) throw const CloudSourceFailure('Legado 书源链接已损坏');
    final base = (decoded['base'] ?? '').toString();
    final bookUrl = (decoded['book'] ?? '').toString();
    final rules = decoded['rules'] is Map
        ? Map<String, dynamic>.from(decoded['rules'] as Map)
        : <String, dynamic>{};
    final useHttp = allowHttp || rules['allowHttp'] == true;
    final uri = Uri.tryParse(bookUrl);
    if (uri == null) throw const CloudSourceFailure('Legado 书籍地址无效');
    final body = await _fetch(
      uri,
      cookie: cookie,
      authorization: authorization,
      allowHttp: useHttp,
    );
    final info = _ruleMap(rules['ruleBookInfo']);
    final title = _firstNonEmpty([
      _textValue(body, info['name'] ?? info['bookName']),
      WebNovelReader.catalogFromHtml(body, uri).entries.isEmpty
          ? ''
          : WebNovelReader.catalogFromHtml(body, uri).entries.first.name,
    ]);
    final author = _textValue(body, info['author']);
    final summary = _textValue(
      body,
      info['intro'] ?? info['summary'] ?? info['desc'],
    );
    final cover = _textValue(body, info['coverUrl'] ?? info['cover']);
    final coverUrl = cover.isEmpty ? null : _resolve(uri, cover);
    final tocValue = rules['ruleToc'];
    final toc = _ruleMap(tocValue);
    final chapterList = _list(
      body,
      toc['chapterList'] ??
          toc['list'] ??
          (tocValue is String ? tocValue : null),
      uri,
    );
    final chapters = <WebNovelChapter>[];
    for (final item in chapterList) {
      if (chapters.length >= 10000) break;
      final name = _textValue(item, toc['chapterName'] ?? toc['name']);
      final link = _textValue(item, toc['chapterUrl'] ?? toc['url']);
      if (name.isEmpty) continue;
      final resolved = link.isEmpty ? bookUrl : _resolve(uri, link);
      if (resolved.isEmpty) continue;
      chapters.add(WebNovelChapter(name, resolved));
    }
    if (chapters.isEmpty) {
      // 没有配置 ruleToc 或规则失效时，仍允许通用目录识别兜底。
      final fallback = WebNovelReader.catalogFromHtml(body, uri).entries;
      final fallbackInfo = WebNovelReader.inspect(bookUrl, allowHttp: useHttp);
      final doc = await fallbackInfo;
      if (doc.chapters.isNotEmpty) {
        return (document: doc, rules: rules);
      }
      if (fallback.isNotEmpty)
        throw const CloudSourceFailure('Legado 书源没有找到目录');
    }
    return (
      document: WebNovelDocument(
        title: title.isEmpty ? null : title,
        author: author.isEmpty ? null : author,
        summary: summary.isEmpty ? null : summary,
        coverUrl: coverUrl,
        chapters: chapters,
      ),
      rules: rules,
    );
  }

  static Future<String> content(
    String url, {
    required String payload,
    bool allowHttp = false,
    String cookie = '',
    String authorization = '',
  }) async {
    final decoded = decodePayload(payload);
    if (decoded == null) throw const CloudSourceFailure('Legado 书源链接已损坏');
    final rules = decoded['rules'] is Map
        ? Map<String, dynamic>.from(decoded['rules'] as Map)
        : <String, dynamic>{};
    final useHttp = allowHttp || rules['allowHttp'] == true;
    final uri = Uri.tryParse(url);
    if (uri == null) throw const CloudSourceFailure('Legado 章节地址无效');
    final body = await _fetch(
      uri,
      cookie: cookie,
      authorization: authorization,
      allowHttp: useHttp,
    );
    final rule = rules['ruleContent'];
    final ruleMap = _ruleMap(rule);
    final selector =
        ruleMap['content'] ?? ruleMap['text'] ?? (rule is String ? rule : null);
    var value = selector == null ? '' : _textValue(body, selector);
    if (value.trim().isEmpty) {
      value = _plain(body);
    } else if (value.contains('<')) {
      value = _plain(value);
    }
    if (value.trim().isEmpty) throw const CloudSourceFailure('Legado 章节没有正文');
    return value;
  }

  static Future<String> _fetch(
    Uri uri, {
    required String cookie,
    required String authorization,
    required bool allowHttp,
  }) async {
    CloudHttp.validateUrl(uri, allowHttp: allowHttp);
    final http = CloudHttp();
    try {
      final response = await http.request(
        'GET',
        uri,
        headers: (requested) => {
          'accept':
              'text/html,application/xhtml+xml,application/json,application/xml,text/xml,*/*',
          if (CloudHttp.sameOrigin(requested, uri) && cookie.trim().isNotEmpty)
            'cookie': cookie.trim(),
          if (CloudHttp.sameOrigin(requested, uri) &&
              authorization.trim().isNotEmpty)
            'authorization': authorization.trim(),
        },
        redirects: true,
        allowHttp: allowHttp,
        redirectMessage: 'Legado 书源地址发生跳转',
      );
      final bytes = await http.bytes(response, limit: 12 * 1024 * 1024);
      return WebNovelReader.decodeBytes(bytes, response.headers.contentType);
    } finally {
      http.close();
    }
  }

  static Map<String, dynamic> _ruleMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) return {'content': value};
    return const {};
  }

  static String _applyUrl(String value, String query, int page) {
    var target = value.trim();
    target = target
        .replaceAll(RegExp(r'\{\{\s*key\s*\}\}'), '{query}')
        .replaceAll(RegExp(r'\{\{\s*page\s*\}\}'), '{page}')
        .replaceAll('{query}', Uri.encodeQueryComponent(query))
        .replaceAll('{page}', '$page');
    return target;
  }

  static String _resolve(Uri base, String value) {
    final clean = value.trim().replaceAll('&amp;', '&');
    if (clean.isEmpty) return '';
    final uri = Uri.tryParse(clean);
    if (uri != null && uri.hasScheme) return clean;
    try {
      return base.resolve(clean).toString();
    } catch (_) {
      return '';
    }
  }

  static List<Object> _list(Object body, Object? rule, Uri base) {
    if (rule == null) return const <Object>[];
    final parsed = _parse(body);
    final value = _extract(parsed, rule, base, list: true);
    if (value is List) return value.cast<Object>();
    if (value == null) return const <Object>[];
    if (value is String && value.isEmpty) return const <Object>[];
    return <Object>[value];
  }

  static String _textValue(Object body, Object? rule) {
    if (rule == null) return '';
    final parsed = _parse(body);
    final value = _extract(parsed, rule, Uri(), list: false);
    if (value == null) return '';
    if (value is List) {
      return value.whereType<String>().join(' ').trim();
    }
    return '$value'.trim();
  }

  static Object _parse(Object body) {
    if (body is! String) return body;
    final text = body.trimLeft();
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return jsonDecode(body);
      } catch (_) {
        // JSON 解析失败时继续按 HTML 处理。
      }
    }
    return html.parse(body);
  }

  static Object? _extract(
    Object root,
    Object rule,
    Uri base, {
    required bool list,
  }) {
    if (rule is Map) {
      final selector =
          rule['selector'] ?? rule['rule'] ?? rule['value'] ?? rule['content'];
      return selector == null
          ? null
          : _extract(root, selector, base, list: list);
    }
    final value = '$rule'.trim();
    if (value.isEmpty) return null;
    if (value.startsWith(r'$.')) {
      return _jsonPath(root, value);
    }
    if (root is Map || root is List) {
      final result = _jsonPath(root, value);
      if (result != null) return result;
    }
    if (root is Document || root is Element) {
      return _htmlChain(root, value, base, list: list);
    }
    return null;
  }

  static Object? _jsonPath(Object root, String path) {
    var value = root;
    var parts = path.trim();
    if (parts.startsWith(r'$.')) parts = parts.substring(2);
    if (parts.startsWith(r'$')) parts = parts.substring(1);
    if (parts.isEmpty || parts == '[*]') {
      return value is List ? value : null;
    }
    for (final raw in parts.split('.')) {
      var key = raw.trim();
      if (key.isEmpty || key == r'$') continue;
      var takeAll = false;
      final all = RegExp(r'^(.+?)\[\*\]$').firstMatch(key);
      if (all != null) {
        key = all.group(1)!;
        takeAll = true;
      }
      final index = RegExp(r'^(.+?)\[(\d+)\]$').firstMatch(key);
      int? at;
      if (index != null) {
        key = index.group(1)!;
        at = int.tryParse(index.group(2)!);
      }
      if (value is List && takeAll) {
        value = [
          for (final item in value)
            if (item is Map) item[key],
        ];
        continue;
      }
      if (value is Map) {
        value = value[key];
      } else if (value is List && at != null) {
        value = at < value.length ? value[at] : null;
      } else {
        return null;
      }
      if (value == null) return null;
      if (at != null && value is List) {
        value = at < value.length ? value[at] : null;
      }
    }
    return value;
  }

  static Object? _htmlChain(
    Object root,
    String rule,
    Uri base, {
    required bool list,
  }) {
    final parts = rule.split('@');
    var nodes = <Object>[root];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index].trim();
      if (part.isEmpty) continue;
      if (part.startsWith('##')) {
        final regexParts = part.substring(2).split('##');
        final pattern = RegExp(regexParts.first, caseSensitive: false);
        nodes = [
          for (final node in nodes)
            if (node is String)
              (pattern.firstMatch(node)?.group(1) ??
                      pattern.firstMatch(node)?.group(0) ??
                      '')
                  .replaceAll(
                    regexParts.length > 1
                        ? RegExp(pattern.pattern)
                        : RegExp(r'^\u0000'),
                    regexParts.length > 1 ? regexParts[1] : '',
                  ),
        ];
        continue;
      }
      if (part.startsWith('!')) {
        final at = int.tryParse(part.substring(1));
        nodes = at != null && at >= 0 && at < nodes.length
            ? [nodes[at]]
            : <Object>[];
        continue;
      }
      final lower = part.toLowerCase();
      if (lower == 'text' || lower == 'owntext' || lower == 'textnodes') {
        nodes = [
          for (final node in nodes)
            if (node is Element) node.text.trim(),
        ];
        continue;
      }
      if (lower == 'html' || lower == 'innerhtml') {
        nodes = [
          for (final node in nodes)
            if (node is Element) node.innerHtml,
        ];
        continue;
      }
      if (lower == 'href' || lower == 'src' || lower == 'content') {
        nodes = [
          for (final node in nodes)
            if (node is Element) node.attributes[lower]?.trim() ?? '',
        ];
        continue;
      }
      final selector = _selector(part);
      nodes = [
        for (final node in nodes)
          if (node is Document)
            ...node.querySelectorAll(selector)
          else if (node is Element)
            if (index == 0)
              ...node.querySelectorAll(selector)
            else
              ..._descendants(node, selector),
      ];
    }
    if (nodes.isEmpty) return null;
    final values = <String>[
      for (final node in nodes)
        if (node is Element) node.text.trim() else '$node'.trim(),
    ];
    if (list) return nodes;
    return values.firstWhere((value) => value.isNotEmpty, orElse: () => '');
  }

  static Iterable<Element> _descendants(Element node, String selector) {
    try {
      final direct = node.querySelectorAll(selector);
      if (direct.isNotEmpty) return direct;
      // 阅读规则里 `li` 经常表示后代；querySelectorAll 已包含后代，这里补
      // 某些规则的 `tag.li` 简写。
      return node.querySelectorAll(selector);
    } catch (_) {
      return const [];
    }
  }

  static String _selector(String value) {
    var selector = value.trim();
    if (selector.startsWith('css:')) selector = selector.substring(4);
    selector = selector
        .replaceAllMapped(RegExp(r'^class\.(.+)$'), (match) => '.${match[1]}')
        .replaceAllMapped(RegExp(r'^id\.(.+)$'), (match) => '#${match[1]}')
        .replaceAllMapped(RegExp(r'^tag\.(.+)$'), (match) => match[1]!);
    return selector;
  }

  static String _firstNonEmpty(List<String> values) =>
      values.firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');

  static String _plain(String body) {
    final document = html.parse(body);
    for (final node in document.querySelectorAll('script,style,noscript')) {
      node.remove();
    }
    final value = document.body?.innerHtml ?? body;
    return html
            .parseFragment(
              value
                  .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
                  .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n'),
            )
            .text
            ?.replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim() ??
        '';
  }
}
