import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import 'catalog.dart';

/// 把网盘直链当作“远程书籍”读取：只在内存里解析，不落地保存原文件。
///
/// 书架只在 SharedPreferences 里保存书名、作者、远程地址和阅读进度；
/// 正文在打开书时按需拉取到内存，退出应用后不保留正文文件。
class CloudDocumentService {
  CloudDocumentService._();
  static final instance = CloudDocumentService._();

  final Map<int, _CloudDocument> _documents = {};
  final Map<int, String> _urls = {};
  final Map<int, Novel> _metadata = {};

  static int idForUrl(String url) {
    final digest = sha256.convert(utf8.encode(url)).bytes;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | digest[i];
    }
    return 2_000_000_000 + (value & 0x0FFFFFFF);
  }

  /// 只生成书架元数据，不联网、不下载。
  Novel metadata(String name, String url, {String? author}) {
    final id = idForUrl(url);
    _urls[id] = url;
    final book = Novel(
      id: id,
      title: _cleanName(name),
      author: author ?? '网盘书源',
      genre: '在线读取',
      summary: '来自网盘直链，在线阅读，不下载原文件。',
      colors: const [Color(0xFF225577), Color(0xFF44AACC)],
      coverUrl: null,
      remoteUrl: url,
    );
    _metadata[id] = book;
    return book;
  }

  bool handles(int id) => _urls.containsKey(id);

  Novel? known(int id) => _metadata[id];

  /// 打开书架里的网盘书时调用：拉取一次原文件，在内存里解析成章节。
  Future<Novel> detail(Novel novel) async {
    final url = novel.remoteUrl ?? _urls[novel.id];
    if (url == null) throw const FormatException('网盘书源地址已丢失，请重新添加');
    _urls[novel.id] = url;
    final cached = _documents[novel.id];
    if (cached != null) {
      _metadata[novel.id] = cached.novel;
      return cached.novel;
    }
    final bytes = await _fetch(url);
    final document = _parse(novel.id, novel.title, url, bytes);
    _documents[novel.id] = document;
    _metadata[novel.id] = document.novel;
    return document.novel;
  }

  Future<List<NovelChapter>> chapters(int id) async {
    final document = _documents[id];
    if (document != null) return document.novel.chapters;
    final meta = _metadata[id];
    if (meta == null) throw const FormatException('请从书架重新打开这本书');
    return (await detail(meta)).chapters;
  }

  Future<String> chapterContent(int id, NovelChapter chapter) async {
    final document = await _ensure(id);
    return document.bodies[chapter.id] ?? '';
  }

  Future<_CloudDocument> _ensure(int id) async {
    final cached = _documents[id];
    if (cached != null) return cached;
    final meta = _metadata[id];
    if (meta == null) throw const FormatException('请从书架重新打开这本书');
    await detail(meta);
    final document = _documents[id];
    if (document == null) throw const FormatException('网盘书籍解析失败');
    return document;
  }

  Future<Uint8List> _fetch(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      var uri = Uri.parse(url);
      for (var hop = 0; hop < 6; hop++) {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        final response = await request.close();
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) throw const FormatException('网盘直链跳转失败');
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200) {
          await response.drain<void>();
          throw FormatException('网盘读取失败（HTTP ${response.statusCode}）');
        }
        final builder = BytesBuilder(copy: false);
        await for (final part in response) {
          builder.add(part);
          if (builder.length > 128 * 1024 * 1024) {
            throw const FormatException('文件超过 128 MiB，暂不支持在线解析');
          }
        }
        return builder.takeBytes();
      }
      throw const FormatException('网盘直链跳转次数过多');
    } finally {
      client.close(force: true);
    }
  }

  _CloudDocument _parse(int id, String name, String url, Uint8List bytes) {
    final head = utf8.decode(bytes.take(512).toList(), allowMalformed: true).toLowerCase();
    if (head.contains('<html') || head.contains('<!doctype html')) {
      return _parseHtml(id, name, url, bytes);
    }
    final isZip = bytes.length > 4 &&
        bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (isZip) {
      try {
        return _parseEpub(id, name, url, bytes);
      } catch (_) {
        // 不是 EPUB 的 ZIP 继续按文本处理。
      }
    }
    return _parseText(id, name, url, bytes);
  }

  _CloudDocument _parseText(int id, String name, String url, Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.contains('\uFFFD')) {
      try { text = latin1.decode(bytes); } catch (_) {}
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final matches = RegExp(
      r'(?=(?:第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷篇][^\n]{0,40}))',
    ).allMatches(text).toList();
    final chapters = <NovelChapter>[];
    final bodies = <int, String>{};
    if (matches.length >= 3) {
      for (var i = 0; i < matches.length; i++) {
        final start = matches[i].start;
        final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
        final chunk = text.substring(start, end).trim();
        if (chunk.isEmpty) continue;
        final firstLine = chunk.split('\n').first.trim();
        final cid = chapters.length + 1;
        chapters.add(NovelChapter(_limit(firstLine, 80), '', id: cid));
        bodies[cid] = chunk;
      }
    }
    if (chapters.isEmpty) {
      final paragraphs = text.split(RegExp(r'\n\s*\n'));
      var buffer = StringBuffer();
      var index = 1;
      void flush() {
        final body = buffer.toString().trim();
        if (body.isEmpty) return;
        chapters.add(NovelChapter('第 $index 节', '', id: index));
        bodies[index] = body;
        index++;
        buffer = StringBuffer();
      }
      for (final p in paragraphs) {
        buffer.writeln(p);
        if (buffer.length > 120000) flush();
      }
      flush();
    }
    if (chapters.isEmpty) throw const FormatException('文件里没有可阅读的文字');
    final novel = _novel(id, name, url, chapters);
    return _CloudDocument(novel, bodies);
  }

  _CloudDocument _parseHtml(int id, String name, String url, Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final document = html.parse(text);
    final heading = (document.querySelector('h1')?.text ??
            document.querySelector('title')?.text ??
            name)
        .trim();
    final paragraphs = document.querySelectorAll('p')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty && t.length > 1)
        .toList();
    final body = paragraphs.isEmpty
        ? (document.body?.text ?? '').trim()
        : paragraphs.join('\n\n');
    if (body.isEmpty) throw const FormatException('网页里没有可阅读的正文');
    final chapters = [NovelChapter(_limit(heading, 80), '', id: 1)];
    final novel = _novel(id, name, url, chapters);
    return _CloudDocument(novel, {1: body});
  }

  _CloudDocument _parseEpub(int id, String name, String url, Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) files[file.name.replaceAll('\\', '/')] = file;
    }
    final container = files['META-INF/container.xml'];
    String opfPath = '';
    if (container != null) {
      final xml = utf8.decode(container.content as List<int>, allowMalformed: true);
      final match = RegExp(r'full-path="([^"]+)"').firstMatch(xml);
      if (match != null) opfPath = match.group(1)!;
    }
    opfPath = opfPath.isNotEmpty
        ? opfPath
        : files.keys.firstWhere(
            (k) => k.toLowerCase().endsWith('.opf'),
            orElse: () => '',
          );
    if (opfPath.isEmpty) throw const FormatException('EPUB 缺少 OPF 目录');
    final opfFile = files[opfPath];
    if (opfFile == null) throw const FormatException('EPUB OPF 文件不存在');
    final opf = utf8.decode(opfFile.content as List<int>, allowMalformed: true);
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final manifest = <String, String>{};
    for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      final idMatch = RegExp(r'\bid="([^"]+)"').firstMatch(tag);
      final hrefMatch = RegExp(r'\bhref="([^"]+)"').firstMatch(tag);
      if (idMatch != null && hrefMatch != null) {
        manifest[idMatch.group(1)!] = hrefMatch.group(1)!;
      }
    }
    final ordered = <String>[];
    for (final m in RegExp(r'<itemref\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      final idref = RegExp(r'\bidref="([^"]+)"').firstMatch(tag)?.group(1);
      final href = idref == null ? null : manifest[idref];
      if (href != null) ordered.add(Uri.decodeFull(href));
    }
    if (ordered.isEmpty) ordered.addAll(manifest.values);
    final chapters = <NovelChapter>[];
    final bodies = <int, String>{};
    for (final href in ordered) {
      final path = _normalize('$base$href');
      final file = files[path];
      if (file == null) continue;
      final markup = utf8.decode(file.content as List<int>, allowMalformed: true);
      final document = html.parse(markup);
      final heading = (document.querySelector('h1, h2, title')?.text ?? '').trim();
      final blocks = document.querySelectorAll('p, div')
          .map((e) => e.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      final body = blocks.isEmpty ? document.body?.text.trim() ?? '' : blocks.join('\n\n');
      if (body.trim().isEmpty) continue;
      final cid = chapters.length + 1;
      final title = heading.isNotEmpty
          ? _limit(heading, 80)
          : '第 ${chapters.length + 1} 章';
      chapters.add(NovelChapter(title, '', id: cid));
      bodies[cid] = body;
    }
    if (chapters.isEmpty) throw const FormatException('EPUB 没有可读章节');
    final novel = _novel(id, name, url, chapters);
    return _CloudDocument(novel, bodies);
  }

  Novel _novel(int id, String name, String url, List<NovelChapter> chapters) =>
      Novel(
        id: id,
        title: _cleanName(name),
        author: '网盘书源',
        genre: '在线读取',
        summary: '来自网盘直链，在线阅读，不下载原文件。',
        colors: const [Color(0xFF225577), Color(0xFF44AACC)],
        chapters: chapters,
        chapterCount: chapters.length,
        isComplete: true,
        remoteUrl: url,
      );

  String _normalize(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part == '..') { if (parts.isNotEmpty) parts.removeLast(); }
      else if (part != '.' && part.isNotEmpty) parts.add(part);
    }
    return parts.join('/');
  }

  String _cleanName(String name) {
    var value = name.replaceAll(RegExp(r'\.(txt|epub|mobi|azw3?|pdf)$', caseSensitive: false), '').trim();
    if (value.isEmpty) value = '网盘书籍';
    return _limit(value, 120);
  }

  String _limit(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}

class _CloudDocument {
  const _CloudDocument(this.novel, this.bodies);
  final Novel novel;
  final Map<int, String> bodies;
}
