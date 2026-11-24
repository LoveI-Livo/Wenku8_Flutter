import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_text_cleaner.dart';

void main() {
  test('过滤正文中的网址、域名和推广行', () {
    final text = cleanReadingText(
      '他推开门，雨声灌了进来。\n'
      '本书首发来自 www.example.com，请记住本站域名。\n'
      '第二段正文，访问 https://bad.example.com/read 看最新章节。\n'
      '手机版阅读网址：m.example.com\n'
      '第三段正文。\n',
    );
    expect(text, contains('他推开门，雨声灌了进来。'));
    expect(text, contains('第三段正文。'));
    expect(text, isNot(contains('example.com')));
    expect(text, isNot(contains('http')));
    expect(text, isNot(contains('最新章节')));
  });

  test('保留插画标记和正常英文', () {
    final marker =
        '<!--image-->https://cdn.example.com/a.jpg<!--image--> 0.5 1.0';
    final text = cleanReadingText('Hello world.\n$marker\n结尾。');
    expect(text, contains(marker));
    expect(text, contains('Hello world.'));
  });
}
