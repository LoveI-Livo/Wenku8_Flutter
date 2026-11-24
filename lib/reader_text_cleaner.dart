/// 阅读正文清洗：书源网页经常在正文里塞自己的网址、域名和推广句。
/// 这里只在“进入阅读器”这一层处理，不改动书源、缓存原文件或下载文件。
library;

final _absoluteUrl = RegExp(
  r'(?:https?://|www\.)[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]+',
  caseSensitive: false,
);
final _bareDomain = RegExp(
  r'(?<![A-Za-z0-9])(?:[A-Za-z0-9-]{2,}\.)+(?:com|net|org|cc|cn|me|io|xyz|top|info|tv|la|us|uk|tw|jp|hk|mo|sg)(?:/[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]*)?',
  caseSensitive: false,
);
final _promo = RegExp(
  r'(?:笔趣阁|新笔趣|笔趣|顶点小说|无弹窗|最新章节|全文阅读|请记住本站|记住本站|本站域名|本站网址|最新网址|手机版阅读|手机阅读|手机用户|请收藏|加入书签|投推荐票|求月票|求收藏|章节错误|点此举报|内容严重缺失|请点击下一页|下一页继续|本章未完|广告|首发来自|本书首发|首发域名|防盗|阅读网址|网站地图|返回目录|上一章|下一章|天才一秒记住|一秒记住|永久免费|免费阅读|txt下载|TXT下载)',
  caseSensitive: false,
);
final _lineEdges = RegExp(
  r'^[\s\-—_=·•|/\\:：,，。;；!！?？~～*#]+|[\s\-—_=·•|/\\:：]+$',
);

String cleanReadingText(String source) {
  final input = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (input.trim().isEmpty) return '';
  final output = <String>[];
  for (final raw in input.split('\n')) {
    // 插画标记本身是 https 地址，必须原样保留给阅读器解码。
    if (raw.contains('<!--image-->')) {
      output.add(raw);
      continue;
    }
    var line = raw.replaceAll(_absoluteUrl, '');
    line = line.replaceAll(_bareDomain, '');
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      if (output.isNotEmpty && output.last.isNotEmpty) output.add('');
      continue;
    }
    final withoutEdges = trimmed.replaceAll(_lineEdges, '').trim();
    if (withoutEdges.length <= 1) continue;
    if (_promo.hasMatch(trimmed) && trimmed.length <= 180) continue;
    // 去掉网址后只剩“：”“、”等标点的碎片行，不送进阅读器。
    if (trimmed
        .replaceAll(RegExp(r'[\s\-—_=·•|/\\:：,，。;；!！?？~～*#（）()\[\]【】]'), '')
        .isEmpty) {
      continue;
    }
    output.add(line.trimRight());
  }
  final result = output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return result;
}
