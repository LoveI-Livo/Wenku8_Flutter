import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/cloud_book_media.dart';
import 'package:wenku8_flutter/cloud_document_service.dart';
import 'package:wenku8_flutter/cloud_sources.dart';

Uint8List _epub() {
  final zip = Archive();
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>''',
  );
  add('OEBPS/content.opf', '''<?xml version="1.0"?>
<package><metadata>
<dc:title>测试书名</dc:title>
<dc:creator>测试作者</dc:creator>
<dc:description>这是一段测试简介。</dc:description>
</metadata>
<manifest>
<item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine><itemref idref="chapter"/></spine></package>''');
  add(
    'OEBPS/chapter.xhtml',
    '''<html><body><h1>第一章</h1><p>正文内容。</p><img src="pic.png"/></body></html>''',
  );
  final cover = Uint8List.fromList(List<int>.filled(32, 0xAB));
  zip.addFile(ArchiveFile('OEBPS/cover.jpg', cover.length, cover));
  final image = Uint8List.fromList(List<int>.filled(24, 0xCD));
  zip.addFile(ArchiveFile('OEBPS/pic.png', image.length, image));
  return Uint8List.fromList(ZipEncoder().encode(zip)!);
}

void main() {
  test(
    'cloud EPUB metadata and cover are recognized without local files',
    () async {
      final bytes = _epub();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'epub',
        );
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final url = 'http://127.0.0.1:${server.port}/book.epub';
      final service = CloudDocumentService.instance;
      final initial = service.metadata('原文件名.epub', url);
      final enriched = await service.enrich(initial);

      expect(enriched.title, '测试书名');
      expect(enriched.author, '测试作者');
      expect(enriched.summary, contains('测试简介'));
      expect(enriched.coverUrl, startsWith(CloudBookMedia.scheme));

      final detail = await service.detail(enriched);
      final body = await service.chapterContent(
        detail.id,
        detail.chapters.first,
      );
      expect(body, contains(CloudBookMedia.mediaScheme));
    },
  );

  test('书源搜索结果封面会写入 Novel', () {
    const entry = CloudBookEntry(
      id: 'https://example.com/book/1',
      name: '封面测试书',
      folder: false,
      book: true,
      author: '作者',
      coverUrl: 'https://example.com/cover.jpg',
    );
    const config = CloudSourceConfig(kind: CloudSourceKind.rss);
    final novel = CloudDocumentService.instance.cloudBook(entry, config);
    expect(novel.coverUrl, 'https://example.com/cover.jpg');
  });
}
