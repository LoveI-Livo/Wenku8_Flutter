import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_source_import.dart';

void main() {
  test('读取一行一个与名称竖线格式', () async {
    final values = await BookSourceFileReader.read(
      'sources.txt',
      Uint8List.fromList(
        utf8.encode('''
# 评论
阅读源 | https://example.com/feed.xml
https://example.com/search?q={query}&page={page}
'''),
      ),
    );
    expect(values.length, 2);
    expect(values.first.name, '阅读源');
    expect(values.last.url, contains('{query}'));
  });

  test('读取 Legado 书源 JSON 并转换搜索占位符', () async {
    final values = await BookSourceFileReader.read(
      'legado.json',
      Uint8List.fromList(
        utf8.encode(
          jsonEncode([
            {
              'bookSourceName': '测试站点',
              'bookSourceUrl': 'https://books.example.com',
              'searchUrl': '/search?key={{key}}&page={{page}}',
              'enabled': true,
            },
          ]),
        ),
      ),
    );
    expect(values.single.name, '测试站点');
    expect(
      values.single.url,
      'https://books.example.com/search?key={query}&page={page}',
    );
  });

  test('读取 OPML 订阅列表', () async {
    final values = await BookSourceFileReader.read(
      'feeds.opml',
      Uint8List.fromList(
        utf8.encode('''
<?xml version="1.0"?><opml version="2.0"><body>
<outline text="站点一" xmlUrl="https://example.com/rss.xml"/>
</body></opml>'''),
      ),
    );
    expect(values.single.name, '站点一');
    expect(values.single.url, 'https://example.com/rss.xml');
  });
}
