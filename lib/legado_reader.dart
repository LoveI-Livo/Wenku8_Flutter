part of 'cloud_sources.dart';

class _LegadoRequest {
  const _LegadoRequest({
    required this.uri,
    required this.method,
    required this.body,
    required this.headers,
  });
  final Uri uri;
  final String method, body;
  final Map<String, String> headers;
}

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
    final request = _searchRequest(source, query, page);
    final body = await _fetch(
      request.uri,
      cookie: cookie,
      authorization: authorization,
      allowHttp: allowHttp,
      method: request.method,
      body: request.body,
      extraHeaders: request.headers,
    );
    final listRule =
        rule['bookList'] ??
        rule['list'] ??
        (ruleValue is String ? ruleValue : null);
    var items = _list(body, listRule, request.uri);
    if (items.isEmpty) {
      // 有些阅读书源只写了搜索地址，没有 bookList；退回通用网页目录识别。
      final generic = WebNovelReader.catalogFromHtml(body, request.uri).entries;
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
      final resolved = _resolve(request.uri, book);
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
      extraHeaders: _headers(rules['header']),
    );
    final info = _ruleMap(rules['ruleBookInfo']);
    var title = _textValue(body, info['name'] ?? info['bookName']);
    if (title.isEmpty) {
      try {
        final generic = WebNovelReader.catalogFromHtml(body, uri).entries;
        if (generic.isNotEmpty) title = generic.first.name;
      } catch (_) {
        // 详情页不一定有通用目录，规则没写书名时继续用空标题。
      }
    }
    final author = _textValue(body, info['author']);
    final summary = _textValue(
      body,
      info['intro'] ?? info['summary'] ?? info['desc'],
    );
    final cover = _textValue(body, info['coverUrl'] ?? info['cover']);
    final coverUrl = cover.isEmpty ? null : _resolve(uri, cover);
    var tocUri = uri;
    var tocBody = body;
    final tocAddress = _textValue(body, info['tocUrl'] ?? info['toc']);
    if (tocAddress.isNotEmpty) {
      final resolved = _resolve(uri, tocAddress);
      final next = Uri.tryParse(resolved);
      if (next != null) {
        tocUri = next;
        tocBody = await _fetch(
          next,
          cookie: cookie,
          authorization: authorization,
          allowHttp: useHttp,
          extraHeaders: _headers(rules['header']),
        );
      }
    }
    final tocValue = rules['ruleToc'];
    final toc = _ruleMap(tocValue);
    var chapterRule =
        toc['chapterList'] ??
        toc['list'] ??
        (tocValue is String ? tocValue : null);
    final reverse = chapterRule is String && chapterRule.trim().endsWith('-');
    if (reverse) {
      chapterRule = chapterRule.trim().substring(
        0,
        chapterRule.trim().length - 1,
      );
    }
    final tocPages = <(String, Uri)>[(tocBody, tocUri)];
    final nextTocRule = toc['nextTocUrl'] ?? info['nextTocUrl'];
    if (nextTocRule != null) {
      for (var page = 0; page < 20; page++) {
        final next = _textValue(tocPages.last.$1, nextTocRule);
        if (next.isEmpty) break;
        final nextUri = Uri.tryParse(_resolve(tocPages.last.$2, next));
        if (nextUri == null || nextUri == tocPages.last.$2) break;
        final nextBody = await _fetch(
          nextUri,
          cookie: cookie,
          authorization: authorization,
          allowHttp: useHttp,
          extraHeaders: _headers(rules['header']),
        );
        tocPages.add((nextBody, nextUri));
      }
    }
    final chapters = <WebNovelChapter>[];
    for (final page in tocPages) {
      final chapterList = _list(page.$1, chapterRule, page.$2);
      for (final item in chapterList) {
        if (chapters.length >= 10000) break;
        final name = _textValue(item, toc['chapterName'] ?? toc['name']);
        final link = _textValue(item, toc['chapterUrl'] ?? toc['url']);
        if (name.isEmpty) continue;
        final resolved = link.isEmpty ? bookUrl : _resolve(page.$2, link);
        if (resolved.isEmpty) continue;
        chapters.add(WebNovelChapter(name, resolved));
      }
      if (chapters.length >= 10000) break;
    }
    if (reverse) {
      final reversed = chapters.reversed.toList(growable: false);
      chapters
        ..clear()
        ..addAll(reversed);
    }
    if (chapters.isEmpty) {
      // 规则没有给出目录时，最后再用通用网页目录识别兜底一次。
      final doc = await WebNovelReader.inspect(bookUrl, allowHttp: useHttp);
      if (doc.chapters.isNotEmpty) return (document: doc, rules: rules);
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
    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null) throw const CloudSourceFailure('Legado 章节地址无效');
    var currentUri = parsedUri;
    var currentBody = await _fetch(
      currentUri,
      cookie: cookie,
      authorization: authorization,
      allowHttp: useHttp,
      extraHeaders: _headers(rules['header']),
    );
    final contentMap = _ruleMap(rules['ruleContent']);
    final selector =
        contentMap['content'] ??
        contentMap['text'] ??
        _stringRule(rules['ruleContent']);
    final nextRule = contentMap['nextContentUrl'];
    final parts = <String>[_contentText(currentBody, selector)];
    if (nextRule != null) {
      for (var page = 0; page < 20; page++) {
        final next = _textValue(currentBody, nextRule);
        if (next.isEmpty) break;
        final nextUri = Uri.tryParse(_resolve(currentUri, next));
        if (nextUri == null || nextUri == currentUri) break;
        currentUri = nextUri;
        currentBody = await _fetch(
          currentUri,
          cookie: cookie,
          authorization: authorization,
          allowHttp: useHttp,
          extraHeaders: _headers(rules['header']),
        );
        final part = _contentText(currentBody, selector);
        if (part.trim().isNotEmpty) parts.add(part);
      }
    }
    final value = parts.join('\n\n').trim();
    if (value.isEmpty) throw const CloudSourceFailure('Legado 章节没有正文');
    return value;
  }

  static String? _stringRule(Object? value) => value is String ? value : null;

  static String _contentText(String body, Object? selector) {
    if (selector == null) return _plain(body);
    final value = _textValue(body, selector);
    if (value.trim().isEmpty) return _plain(body);
    return value.contains('<') ? _plain(value) : value;
  }

  static Future<String> _fetch(
    Uri uri, {
    required String cookie,
    required String authorization,
    required bool allowHttp,
    String method = 'GET',
    String body = '',
    Map<String, String> extraHeaders = const {},
  }) async {
    CloudHttp.validateUrl(uri, allowHttp: allowHttp);
    final http = CloudHttp();
    final upper = method.toUpperCase();
    try {
      final response = await http.request(
        upper,
        uri,
        body: upper == 'POST' ? utf8.encode(body) : null,
        headers: (requested) => {
          'accept':
              'text/html,application/xhtml+xml,application/json,application/xml,text/xml,*/*',
          if (upper == 'POST')
            'content-type':
                extraHeaders['content-type'] ??
                'application/x-www-form-urlencoded',
          for (final entry in extraHeaders.entries)
            if (entry.key.toLowerCase() != 'content-type')
              entry.key: entry.value,
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

  static _LegadoRequest _searchRequest(
    CloudBookSource source,
    String query,
    int page,
  ) {
    final raw = (source.rules['searchUrl'] ?? source.url).toString().trim();
    final config = RegExp(r',\s*(\{.*\})\s*$', dotAll: true).firstMatch(raw);
    final address = config == null ? raw : raw.substring(0, config.start);
    var map = <String, dynamic>{};
    if (config != null) {
      try {
        final decoded = jsonDecode(config[1]!);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {
        map = <String, dynamic>{};
      }
    }
    final target = _applyUrl(address, query, page);
    final uri = Uri.tryParse(target);
    if (uri == null) throw const CloudSourceFailure('书源搜索地址无效');
    final method = (map['method'] ?? map['Method'] ?? 'GET').toString();
    final rawBody = map['body'] ?? map['Body'] ?? '';
    final body = rawBody is Map
        ? [
            for (final entry in rawBody.entries)
              '${Uri.encodeQueryComponent('${entry.key}')}='
                  '${Uri.encodeQueryComponent(_fillText('${entry.value}', query, page))}',
          ].join('&')
        : _fillText('$rawBody', Uri.encodeQueryComponent(query), page);
    final headers = <String, String>{
      ..._headers(source.rules['header']),
      ..._headers(map['headers'] ?? map['header'] ?? const {}),
    };
    return _LegadoRequest(
      uri: uri,
      method: method.toUpperCase() == 'POST' ? 'POST' : 'GET',
      body: body,
      headers: headers,
    );
  }

  static String _fillText(String value, String query, int page) => value
      .replaceAll(RegExp(r'\{\{\s*key\s*\}\}'), query)
      .replaceAll(RegExp(r'\{\{\s*page\s*\}\}'), '$page')
      .replaceAll('{query}', query)
      .replaceAll('{page}', '$page');

  static Map<String, String> _headers(Object? raw) {
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          '${entry.key}'.trim(): '${entry.value}'.trim(),
      }..removeWhere((key, value) => key.isEmpty || value.isEmpty);
    }
    final text = '$raw'.trim();
    if (text.isEmpty || text == 'null') return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            '${entry.key}'.trim(): '${entry.value}'.trim(),
        }..removeWhere((key, value) => key.isEmpty || value.isEmpty);
      }
    } catch (_) {
      // 允许 Header: key:value 一行一个。
    }
    final result = <String, String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
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
    if (value.contains('&') && !value.contains('&&')) {
      final pieces = value
          .split('&')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty);
      final values = <Object>[];
      for (final piece in pieces) {
        final result = _extract(root, piece, base, list: list);
        if (result is List) {
          values.addAll(result.whereType<Object>());
        } else if (result != null) {
          values.add(result);
        }
      }
      if (list) return values;
      return values.whereType<String>().join(' ');
    }
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
    if (rule.contains('|') && !rule.contains('##')) {
      for (final alternative in rule.split('|')) {
        final value = _htmlChain(root, alternative.trim(), base, list: list);
        if (value != null) return value;
      }
      return null;
    }
    final parts = rule.split('@');
    var nodes = <Object>[root];
    for (var index = 0; index < parts.length; index++) {
      var part = parts[index].trim();
      if (part.isEmpty) continue;
      // 正则替换可以跟在任意一段后面：text##广告##、@href##...
      final hash = part.indexOf('##');
      final core = hash < 0 ? part : part.substring(0, hash).trim();
      final regex = hash < 0 ? null : part.substring(hash + 2);
      if (core.startsWith('!')) {
        final spec = core.substring(1);
        nodes = _drop(nodes, spec);
        continue;
      }
      final lower = core.toLowerCase();
      if (lower == 'children') {
        nodes = [
          for (final node in nodes)
            if (node is Element) ...node.children,
        ];
      } else if (lower == 'text' ||
          lower == 'textnodes' ||
          lower == 'owntext' ||
          lower == 'textnode') {
        nodes = [
          for (final node in nodes)
            if (node is Element)
              lower == 'owntext' || lower == 'textnodes' || lower == 'textnode'
                  ? node.nodes
                        .whereType<Text>()
                        .map((text) => text.text)
                        .join('\n')
                        .trim()
                  : node.text.trim()
            else
              '$node'.trim(),
        ];
      } else if (lower == 'html' || lower == 'innerhtml') {
        nodes = [
          for (final node in nodes)
            if (node is Element) node.innerHtml else '$node',
        ];
      } else if (lower == 'href' ||
          lower == 'src' ||
          lower == 'content' ||
          lower == 'title' ||
          lower == 'alt' ||
          lower == 'data-src') {
        nodes = [
          for (final node in nodes)
            if (node is Element) node.attributes[lower]?.trim() ?? '',
        ];
      } else {
        final parsed = _selectorPart(core);
        final selector = parsed.$1;
        nodes = [for (final node in nodes) ..._select(node, selector)];
        nodes = _position(nodes, parsed.$2);
      }
      if (regex != null) {
        nodes = [
          for (final node in nodes)
            if (node is Element)
              _replace(node.text.trim(), regex)
            else
              _replace('$node', regex),
        ];
      }
    }
    if (nodes.isEmpty) return null;
    if (list) return nodes;
    for (final node in nodes) {
      final value = node is Element ? node.text.trim() : '$node'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static Iterable<Element> _select(Object node, String selector) {
    if (selector.isEmpty) return const [];
    try {
      if (node is Document) return node.querySelectorAll(selector);
      if (node is Element) {
        return node.querySelectorAll(selector);
      }
    } catch (_) {
      // 无效选择器交给下一段规则，避免整条书源直接报错。
    }
    return const [];
  }

  /// 解析 `class.odd.0`、`tag.a.1`、`id.x` 和普通 CSS 选择器。
  static (String, String?) _selectorPart(String value) {
    var core = value.trim();
    var position = <String>[];
    final bang = RegExp(r'!([0-9%,:]+)$').firstMatch(core);
    if (bang != null) {
      position.add('!${bang.group(1)}');
      core = core.substring(0, bang.start).trim();
    }
    final tail = RegExp(r'\.([0-9]+)$').firstMatch(core);
    if (tail != null) {
      core = core.substring(0, tail.start).trim();
      position.add(tail.group(1)!);
    }
    core = core
        .replaceAllMapped(RegExp(r'^class\.(.+)$'), (m) => '.${m[1]}')
        .replaceAllMapped(RegExp(r'^id\.(.+)$'), (m) => '#${m[1]}')
        .replaceAllMapped(RegExp(r'^tag\.(.+)$'), (m) => m[1]!)
        .trim();
    if (core.startsWith('css:')) core = core.substring(4).trim();
    return (core, position.isEmpty ? null : position.join('!'));
  }

  static List<Object> _position(List<Object> nodes, String? spec) {
    if (spec == null || spec.isEmpty || nodes.isEmpty) return nodes;
    var result = nodes;
    final drops = <int>{};
    final takes = <int>[];
    for (final token in spec.split('!')) {
      if (token.isEmpty) continue;
      final drop = token.startsWith('!');
      final raw = drop ? token.substring(1) : token;
      if (raw == '%') {
        if (drop) {
          drops.add(result.length - 1);
        } else {
          takes.add(result.length - 1);
        }
        continue;
      }
      final range = RegExp(r'^([0-9]+):([0-9]+)$').firstMatch(raw);
      if (range != null) {
        final start = int.tryParse(range[1]!) ?? 0;
        final end = int.tryParse(range[2]!) ?? start;
        for (var i = start; i <= end && i < result.length; i++) {
          if (drop) {
            drops.add(i);
          } else {
            takes.add(i);
          }
        }
        continue;
      }
      final at = int.tryParse(raw);
      if (at == null || at < 0 || at >= result.length) continue;
      if (drop) {
        drops.add(at);
      } else {
        takes.add(at);
      }
    }
    if (drops.isNotEmpty) {
      result = [
        for (var i = 0; i < result.length; i++)
          if (!drops.contains(i)) result[i],
      ];
    }
    if (takes.isNotEmpty) {
      result = [
        for (final at in takes)
          if (at < result.length) result[at],
      ];
    }
    return result;
  }

  static List<Object> _drop(List<Object> nodes, String spec) =>
      _position(nodes, '!$spec');

  static String _replace(String value, String spec) {
    final parts = spec.split('##');
    try {
      final pattern = RegExp(parts.first, caseSensitive: false);
      if (parts.length > 1) {
        final replacement = parts.sublist(1).join('##');
        return value.replaceAllMapped(
          pattern,
          (match) =>
              replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (capture) {
                final at = int.tryParse(capture[1]!) ?? 0;
                return at < match.groupCount ? (match.group(at) ?? '') : '';
              }),
        );
      }
      final match = pattern.firstMatch(value);
      if (match == null) return value;
      return match.group(1) ?? match.group(0) ?? '';
    } catch (_) {
      return value;
    }
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
