import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/cloud_sources.dart';

void main() {
  test('Legado POST 搜索、目录分页、正文分页和 & 合并', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    var searchBody = '';
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.html;
      final path = request.uri.path;
      if (path == '/search') {
        searchBody = await utf8.decoder.bind(request).join();
        response.write('''
<html><body>
<div class="odd"><a href="/book/1">测试书</a><span class="author">作者甲</span></div>
<div class="even"><a href="/book/2">第二本</a><span class="author">作者乙</span></div>
</body></html>''');
      } else if (path == '/book/1') {
        response.write('''
<html><body><h1>测试书</h1><span class="writer">作者甲</span>
<div class="intro">简介</div><a class="toc" href="/book/1/toc">目录</a>
<img class="cover" src="/cover.jpg"></body></html>''');
      } else if (path == '/book/1/toc') {
        response.write('''
<html><body><ul class="chapters">
<li><a href="/book/1/chapter/1">第一章</a></li>
<li><a href="/book/1/chapter/2">第二章</a></li>
</ul><a class="next" href="/book/1/toc/2">下一页</a></body></html>''');
      } else if (path == '/book/1/toc/2') {
        response.write('''
<html><body><ul class="chapters">
<li><a href="/book/1/chapter/3">第三章</a></li>
</ul></body></html>''');
      } else if (path == '/book/1/chapter/1') {
        response.write('''
<html><body><div id="content"><p>正文1第一段</p></div>
<a class="next-page" href="/book/1/chapter/1/2">下一段</a></body></html>''');
      } else if (path == '/book/1/chapter/1/2') {
        response.write('''
<html><body><div id="content"><p>正文2第一段</p></div></body></html>''');
      } else {
        response.statusCode = 404;
        response.write('not found');
      }
      await response.close();
    });
    addTearDown(() => server.close(force: true));

    final rules = <String, dynamic>{
      'searchUrl': '$base/search,{"method":"post","body":"keyboard={{key}}"}',
      'header': {'referer': '$base/'},
      'ruleSearch': {
        'bookList': 'class.odd&class.even',
        'name': 'tag.a.0@text',
        'bookUrl': 'tag.a.0@href',
        'author': 'class.author@text',
      },
      'ruleBookInfo': {
        'name': 'tag.h1.0@text',
        'author': 'class.writer@text',
        'intro': 'class.intro@text',
        'tocUrl': 'class.toc@href',
        'coverUrl': 'class.cover@src',
      },
      'ruleToc': {
        'chapterList': 'class.chapters@tag.li',
        'chapterName': 'tag.a.0@text',
        'chapterUrl': 'tag.a.0@href',
        'nextTocUrl': 'class.next@href',
      },
      'ruleContent': {
        'content': 'id.content@text',
        'nextContentUrl': 'class.next-page@href',
      },
    };
    final source = CloudBookSource(url: base, rules: rules);
    final listing = await LegadoReader.search(source, '测试 书', allowHttp: true);
    expect(Uri.splitQueryString(searchBody)['keyboard'], '测试 书');
    expect(listing.entries.length, 2);
    final payload = listing.entries.first.id;
    final detail = await LegadoReader.detail(payload, allowHttp: true);
    expect(detail.document.title, '测试书');
    expect(detail.document.author, '作者甲');
    expect(detail.document.coverUrl, '$base/cover.jpg');
    expect(detail.document.chapters.length, 3);
    expect(detail.document.chapters.last.title, '第三章');
    final chapterUrl = detail.document.chapters.first.url;
    final content = await LegadoReader.content(
      chapterUrl,
      payload: payload,
      allowHttp: true,
    );
    expect(content, contains('正文1第一段'));
    expect(content, contains('正文2第一段'));
  });

  test('Legado 多段落正文不会只返回第一段', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/chapter/1') {
        request.response.write('''
<html><body><div class="article">
<p class="line">第一段正文</p>
<p class="line">第二段正文</p>
<p class="line">第三段正文</p>
</div></body></html>''');
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final rules = <String, dynamic>{
      'ruleContent': {'content': 'class.line'},
    };
    final payload = LegadoReader.encodePayload(
      base: base,
      bookUrl: '$base/book/1',
      rules: rules,
    );
    final text = await LegadoReader.content(
      '$base/chapter/1',
      payload: payload,
      allowHttp: true,
    );
    expect(text, contains('第一段正文'));
    expect(text, contains('第二段正文'));
    expect(text, contains('第三段正文'));
  });

  test('Legado 多页目录去重并按章节号排序', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.html;
      if (request.uri.path == '/book') {
        response.write("""
<html><body><h1>乱序书</h1><ul class="chapters">
<li><a href="/c/1918">第1918章 吞下</a></li>
<li><a href="/c/1917">第1917章 十七</a></li>
<li><a href="/c/1">第1章 开端</a></li>
<li><a href="/c/2">第2章 继续</a></li>
<li><a href="/c/1">第1章 开端</a></li>
</ul><a class="next" href="/book/2">下一页</a></body></html>""");
      } else if (request.uri.path == '/book/2') {
        response.write("""
<html><body><ul class="chapters">
<li><a href="/c/1916">第1916章 十六</a></li>
<li><a href="/c/1915">第1915章 十五</a></li>
<li><a href="/c/1914">第1914章 十四</a></li>
<li><a href="/c/1913">第1913章 十三</a></li>
<li><a href="/c/1912">第1912章 十二</a></li>
</ul></body></html>""");
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
    addTearDown(() => server.close(force: true));
    final rules = <String, dynamic>{
      'ruleBookInfo': {'name': 'tag.h1.0@text'},
      'ruleToc': {
        'chapterList': 'class.chapters@tag.li',
        'chapterName': 'tag.a.0@text',
        'chapterUrl': 'tag.a.0@href',
        'nextTocUrl': 'class.next@href',
      },
    };
    final payload = LegadoReader.encodePayload(
      base: base,
      bookUrl: '$base/book',
      rules: rules,
    );
    final detail = await LegadoReader.detail(payload, allowHttp: true);
    expect(detail.document.title, '乱序书');
    expect(detail.document.chapters.length, 9);
    expect(detail.document.chapters.map((chapter) => chapter.title).toList(), [
      '第1章 开端',
      '第2章 继续',
      '第1912章 十二',
      '第1913章 十三',
      '第1914章 十四',
      '第1915章 十五',
      '第1916章 十六',
      '第1917章 十七',
      '第1918章 吞下',
    ]);
  });
}
