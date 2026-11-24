import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/cloud_sources.dart';

void main() {
  test('Legado {{source.key}} 相对搜索地址会解析到书源域名', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = <String>[];
    server.listen((request) async {
      requested.add(request.uri.toString());
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': [
            {
              'name': '仙逆',
              'author': '耳根',
              'url': '/book/1',
              'cover': '/covers/xianni.jpg',
            },
          ],
        }),
      );
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/qd';
    final source = CloudBookSource(
      url: base,
      name: '测试书源',
      rules: {
        'searchUrl': r'{{source.key}}/api/search?q={{key}}&page={{page}}',
        'ruleSearch': {
          'bookList': r'$.data[*]',
          'name': r'$.name',
          'author': r'$.author',
          'bookUrl': r'$.url',
        },
      },
    );
    try {
      final listing = await LegadoReader.search(source, '仙逆');
      expect(listing.entries, hasLength(1));
      expect(listing.entries.first.name, '仙逆');
      expect(listing.entries.first.author, '耳根');
      expect(
        listing.entries.first.coverUrl,
        'http://127.0.0.1:${server.port}/covers/xianni.jpg',
      );
      expect(requested.single, contains('/qd/api/search'));
      expect(requested.single, contains('q=%E4%BB%99%E9%80%86'));
    } finally {
      await server.close(force: true);
    }
  });
}
