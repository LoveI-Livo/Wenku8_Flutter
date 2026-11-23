import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/cloud_parse_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cloud parse client accepts chapters, cover and media', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data['token'], 'test-token');
      expect(data['name'], 'book.epub');
      expect(data['apiVersion'], CloudParseService.contractVersion);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'ok': true,
          'title': '云端书名',
          'author': '云端作者',
          'summary': '云端简介',
          'cover': base64Encode([1, 2, 3]),
          'chapters': [
            {'title': '第一章', 'content': '正文 [[CLOUD_MEDIA:pic1]]'},
          ],
          'media': [
            {
              'key': 'pic1',
              'data': base64Encode([4, 5, 6]),
            },
          ],
        }),
      );
      await request.response.close();
    });
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'wenku8-cloud-parse-endpoint-v1':
          'http://127.0.0.1:${server.port}/index.php',
      'wenku8-cloud-parse-token-v1': 'test-token',
    });
    final novel = Novel(
      id: 7,
      title: '书名',
      author: '',
      genre: '在线读取',
      summary: '',
      colors: const [Colors.blue, Colors.cyan],
    );
    final document = await CloudParseService.instance.parse(
      novel,
      resolvedUrl: 'http://127.0.0.1:${server.port}/book.epub',
    );
    expect(document, isNotNull);
    expect(document!.title, '云端书名');
    expect(document.author, '云端作者');
    expect(document.chapters.single.title, '第一章');
    expect(document.media.keys, contains('pic1'));
    await server.close(force: true);
  });
}
