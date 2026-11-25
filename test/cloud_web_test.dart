import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/cloud_sources.dart';

void main() {
  test('网页目录能识别多本书', () {
    final listing = WebNovelReader.catalogFromHtml('''
      <html><body>
        <nav><a href="/">首页</a><a href="/login">登录</a></nav>
        <div class="book-list">
          <a href="/book/100.html">第一本书</a>
          <a href="/book/101.html">第二本书</a>
          <a href="/book/102.html">第三本书</a>
        </div>
      </body></html>
    ''', Uri.parse('https://example.com/list'));
    expect(listing.entries.length, 3);
    expect(listing.entries.first.name, '第一本书');
    expect(listing.entries.first.id, 'https://example.com/book/100.html');
  });

  test('网页书籍能识别书名、作者、简介和目录', () {
    final listing = WebNovelReader.catalogFromHtml('''
      <html><head>
        <meta name="description" content="一本测试小说的简介">
      </head><body>
        <h1>测试小说</h1>
        <span>作者：张三</span>
        <a href="/book/100/1.html">第一章 开始</a>
        <a href="/book/100/2.html">第二章 继续</a>
        <a href="/book/100/3.html">第三章 结束</a>
      </body></html>
    ''', Uri.parse('https://example.com/book/100.html'));
    expect(listing.entries.single.name, '测试小说');
    expect(listing.entries.single.author, '张三');
    expect(listing.entries.single.summary, '一本测试小说的简介');
  });

  test('没有 meta description 时从“简介：”正文提取完整简介', () {
    final listing = WebNovelReader.catalogFromHtml('''
      <html><body>
        <h1>无 Meta 小说</h1>
        <div class="bookinfo">
          <p>作者：李四</p>
          <p>简介：这是一段没有 meta 标签的完整简介，包含第一卷的故事背景、
          主要人物和冲突，不应因为页面没有 description 就留空。</p>
          <p>最新章节：第一章</p>
        </div>
        <a href="/book/200/1.html">第一章</a>
        <a href="/book/200/2.html">第二章</a>
      </body></html>
    ''', Uri.parse('https://example.com/book/200.html'));
    final summary = listing.entries.single.summary;
    expect(summary, contains('没有 meta 标签的完整简介'));
    expect(summary, isNot(contains('最新章节')));
  });

  test('搜索结果每页固定五十条', () {
    final items = [
      for (var index = 0; index < 120; index++)
        Novel(
          id: index + 1,
          title: '书 $index',
          author: '作者',
          genre: '测试',
          summary: '简介',
          colors: const [],
        ),
    ];
    final first = NovelPage.fromItems(items, 1);
    expect(first.items.length, 50);
    expect(first.totalPages, 3);
    expect(first.hasMore, isTrue);
    final last = NovelPage.fromItems(items, 3);
    expect(last.items.length, 20);
    expect(last.hasMore, isFalse);
  });
}
