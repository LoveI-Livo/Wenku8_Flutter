import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

/// 从互联网常见的书源文件里提取可用的书源地址。
///
/// 支持：纯文本一行一个、`名称 | 地址`、CSV、Legado 书源 JSON、
/// 自定义 `sources` JSON、OPML 订阅列表和含订阅链接的 HTML。
class ImportedBookSource {
  const ImportedBookSource(
    this.name,
    this.url, {
    this.group = '',
    this.rules = const {},
  });
  final String name, url, group;
  final Map<String, dynamic> rules;
  bool get isLegado => rules.isNotEmpty;
}

class BookSourceFileReader {
  BookSourceFileReader._();

  // 用户明确要求不限制书源包大小；真正由设备存储和系统选择器兜底。
  static const maxBytes = 1 << 30;

  static Future<List<ImportedBookSource>> read(
    String fileName,
    Uint8List bytes,
  ) async {
    if (bytes.length > maxBytes) {
      throw const FormatException('书源文件超过 4 MB，请拆分后再导入');
    }
    var text = _decode(bytes);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.json') || _looksJson(text)) {
      return _json(text);
    }
    if (lower.endsWith('.opml') || lower.endsWith('.xml') || _looksXml(text)) {
      final xml = _xml(text);
      if (xml.isNotEmpty) return xml;
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm') || _looksHtml(text)) {
      final links = _htmlLinks(text);
      if (links.isNotEmpty) return links;
    }
    return _lines(text);
  }

  static String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // 部分旧书源文件是 GBK；调用 charset 太重，先按 Latin-1 保留可读字节，
      // URL 和 ASCII 字段仍能正确解析。
      return latin1.decode(bytes);
    }
  }

  static bool _looksJson(String text) {
    final value = text.trimLeft();
    return value.startsWith('{') || value.startsWith('[');
  }

  static bool _looksXml(String text) {
    final value = text.trimLeft();
    return value.startsWith('<?xml') ||
        value.startsWith('<opml') ||
        value.startsWith('<rss');
  }

  static bool _looksHtml(String text) {
    final value = text.trimLeft().toLowerCase();
    return value.startsWith('<!doctype html') || value.startsWith('<html');
  }

  static List<ImportedBookSource> _json(String text) {
    Object? value;
    try {
      value = jsonDecode(text);
    } catch (_) {
      throw const FormatException('JSON 书源文件格式无法识别');
    }
    final result = <ImportedBookSource>[];
    void add(
      String? name,
      String? url, {
      Map<String, dynamic> rules = const {},
      String group = '',
    }) {
      final clean = _url(url);
      if (clean == null) return;
      final label = (name ?? '').trim();
      final identity = rules.isEmpty
          ? clean
          : '$clean|$label|${jsonEncode(rules)}';
      for (final source in result) {
        final existing = source.rules.isEmpty
            ? source.url
            : '${source.url}|${source.name}|${jsonEncode(source.rules)}';
        if (existing == identity) return;
      }
      result.add(
        ImportedBookSource(
          label.isEmpty ? _host(clean) : label,
          clean,
          group: group,
          rules: rules,
        ),
      );
    }

    void walk(Object? value, {String group = ''}) {
      if (value is String) {
        add(null, value);
        return;
      }
      if (value is List) {
        for (final item in value) {
          walk(item, group: group);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final name = (map['bookSourceName'] ?? map['name'] ?? map['title'] ?? '')
          .toString();
      final sourceGroup = (map['bookSourceGroup'] ?? group).toString();
      var base = (map['bookSourceUrl'] ?? map['url'] ?? map['link'] ?? '')
          .toString()
          .trim();
      final search = (map['searchUrl'] ?? '').toString().trim();
      final ruleKeys = const [
        'ruleSearch',
        'ruleBookInfo',
        'ruleToc',
        'ruleContent',
        'ruleExplore',
        'ruleReview',
        'header',
        'loginUrl',
        'coverDecodeJs',
        'bookUrlPattern',
      ];
      final rules = <String, dynamic>{};
      for (final key in ruleKeys) {
        final rule = map[key];
        if (rule == null || (rule is String && rule.trim().isEmpty)) continue;
        rules[key] = rule;
      }
      // 少数 Legado 书源把 bookSourceUrl 写成 App 名、emoji 或裸域名；
      // 只要搜索地址是完整 HTTP 地址仍应导入，用搜索域名作为基准地址。
      if (_url(base) == null && (rules.isNotEmpty || search.isNotEmpty)) {
        base = _derivedBase(base, search);
      }
      if (base.isNotEmpty && map['enabled'] != false) {
        if (rules.isNotEmpty) {
          var searchUrl = search.isEmpty ? base : search;
          // Legado 允许相对地址；保存前解析成绝对地址，导入后即可直接搜索。
          // data: / @js: / <js> / {{...}} 是脚本构造的地址，不能交给
          // Uri.resolve，否则 data URI 里的模板会被当成 base64 解码并整包失败。
          if (searchUrl.isNotEmpty) {
            searchUrl = _absoluteSearch(base, searchUrl);
          }
          rules['searchUrl'] = _legadoSearch(base, searchUrl);
          add(name, base, rules: rules, group: sourceGroup);
        } else if (search.isNotEmpty) {
          add(name, _legadoSearch(base, search), group: sourceGroup);
        } else {
          add(name, base, group: sourceGroup);
        }
      }
      for (final key in const [
        'sources',
        'books',
        'items',
        'data',
        'list',
        'results',
        'bookSources',
      ]) {
        if (map[key] case final Object nested) walk(nested, group: sourceGroup);
      }
    }

    walk(value);
    if (result.isEmpty) throw const FormatException('这个 JSON 里没有找到书源地址');
    return result;
  }

  /// 把不规范的 bookSourceUrl 变成可保存的 HTTPS 基地址。
  /// - 搜索地址以 http 开头：直接用它的 origin；
  /// - bookSourceUrl 是裸域名：补 https://；
  /// - 其余（App 名称、emoji、#）：用稳定的本地占位地址，规则仍完整保留。
  static String _derivedBase(String base, String search) {
    final query = search.trim();
    if (query.startsWith('http://') || query.startsWith('https://')) {
      final uri = Uri.tryParse(query);
      if (uri != null && uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}';
      }
    }
    if (RegExp(
      r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$',
      caseSensitive: false,
    ).hasMatch(base)) {
      return 'https://$base';
    }
    final token = base64Url
        .encode(utf8.encode(base.isEmpty ? 'source' : base))
        .replaceAll('=', '');
    return 'https://legado.local/source/$token';
  }

  static bool _scriptedAddress(String value) {
    final text = value.trim().toLowerCase();
    return text.startsWith('data:') ||
        text.startsWith('@js:') ||
        text.startsWith('<js>') ||
        text.startsWith('js:') ||
        text.startsWith('{{');
  }

  /// 把 Legado 的相对搜索地址拼到书源地址上；脚本类地址原样保留。
  static String _absoluteSearch(String base, String search) {
    final raw = search.trim();
    if (raw.isEmpty || _scriptedAddress(raw)) return raw;
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    try {
      final root = Uri.parse(base);
      return root.resolve(raw).toString();
    } catch (_) {
      return raw;
    }
  }

  static String _legadoSearch(String base, String search) {
    var raw = search.trim();
    if (raw.isEmpty) return base;
    // 先展开最常见的 source.key / baseUrl；否则脚本判断会把整段原样保留，
    // 运行时会得到 /search.php 这种缺少域名的地址。
    final cleanBase = base.trim().replaceFirst(RegExp(r'/+$'), '');
    raw = raw
        .replaceAll(
          RegExp(r'\{\{\s*source\.key\s*\}\}', caseSensitive: false),
          cleanBase,
        )
        .replaceAll(
          RegExp(r'\{\{\s*source\.url\s*\}\}', caseSensitive: false),
          cleanBase,
        )
        .replaceAll(
          RegExp(r'\{\{\s*baseUrl\s*\}\}', caseSensitive: false),
          cleanBase,
        );
    // data: / @js: / <js> / {{...}} 由脚本运行时处理，导入阶段只保留原文。
    // 之前这里把 data: URI 交给 Uri.resolve，Dart 会解码其中未展开的
    // {{java.base64Encode(...)}}，一个坏书源就能让整包 276 条全部导入失败。
    if (_scriptedAddress(raw)) return raw;
    // 阅读书源的 searchUrl 支持在逗号后跟 JSON 请求配置，例如：
    // /search.php,{"method":"post","body":"key={{key}}"}
    // 只解析逗号前的地址，JSON 配置原样保留给请求层。
    final config = RegExp(r',\s*(\{.*\})\s*$', dotAll: true).firstMatch(raw);
    final address = config == null ? raw : raw.substring(0, config.start);
    final suffix = config == null ? '' : raw.substring(config.start);
    final Uri baseUri;
    try {
      baseUri = Uri.parse(base);
    } catch (_) {
      return raw;
    }
    String target;
    try {
      target = baseUri.resolve(address).toString();
    } catch (_) {
      target = address;
    }
    target = target
        .replaceAll(
          RegExp(r'\{\{\s*source\.key\s*\}\}', caseSensitive: false),
          base,
        )
        .replaceAll(
          RegExp(r'\{\{\s*source\.url\s*\}\}', caseSensitive: false),
          base,
        )
        .replaceAll(
          RegExp(r'\{\{\s*baseUrl\s*\}\}', caseSensitive: false),
          base,
        )
        .replaceAll(RegExp('%7b', caseSensitive: false), '{')
        .replaceAll(RegExp('%7d', caseSensitive: false), '}')
        .replaceAll(
          RegExp(r'\{\{?\s*key\s*\}\}?', caseSensitive: false),
          '{query}',
        )
        .replaceAll(
          RegExp(r'\{\{?\s*page\s*\}\}?', caseSensitive: false),
          '{page}',
        );
    final lowerSuffix = suffix.toLowerCase();
    final hasKeyword =
        target.contains('{query}') ||
        lowerSuffix.contains('{{key}}') ||
        lowerSuffix.contains('{query}');
    if (!hasKeyword) {
      // 没有关键词占位符的搜索地址不能用于按书名搜索；保留站点首页作为网页书源。
      return base;
    }
    return '$target$suffix';
  }

  static List<ImportedBookSource> _xml(String text) {
    XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } catch (_) {
      return const [];
    }
    final result = <ImportedBookSource>[];
    for (final outline in document.findAllElements('outline')) {
      final url = _url(
        outline.getAttribute('xmlUrl') ?? outline.getAttribute('url'),
      );
      if (url == null) continue;
      if (result.any((source) => source.url == url)) continue;
      final label =
          (outline.getAttribute('text') ??
                  outline.getAttribute('title') ??
                  _host(url))
              .trim();
      result.add(ImportedBookSource(label.isEmpty ? _host(url) : label, url));
    }
    return result;
  }

  static List<ImportedBookSource> _htmlLinks(String text) {
    final document = html.parse(text);
    final result = <ImportedBookSource>[];
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = _url(anchor.attributes['href']);
      if (href == null) continue;
      final lower = href.toLowerCase();
      if (!RegExp(
        r'(\.xml|\.rss|\.atom|\.json|feed|rss|atom)(?:$|[?#])',
      ).hasMatch(lower)) {
        continue;
      }
      if (result.any((source) => source.url == href)) continue;
      final label = anchor.text.trim();
      result.add(ImportedBookSource(label.isEmpty ? _host(href) : label, href));
    }
    return result;
  }

  static List<ImportedBookSource> _lines(String text) {
    final result = <ImportedBookSource>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//'))
        continue;
      final values = line.split(RegExp(r'\s*[|\t,]\s*'));
      final urlValue = values.firstWhere(
        (value) => value.trim().startsWith('http'),
        orElse: () => '',
      );
      final url = _url(urlValue);
      if (url == null) continue;
      final label = values
          .where((value) => value.trim() != urlValue.trim())
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (result.any((source) => source.url == url)) continue;
      result.add(ImportedBookSource(label.isEmpty ? _host(url) : label, url));
    }
    if (result.isEmpty) throw const FormatException('没有从书源文件里找到 HTTPS 地址');
    return result;
  }

  static String? _url(String? raw) {
    final value = (raw ?? '').trim().replaceAll('&amp;', '&');
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return value;
  }

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;
}
