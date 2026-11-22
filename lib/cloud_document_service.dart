import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart' as xml;

import 'book_documents.dart';
import 'catalog.dart';
import 'cloud_book_media.dart';
import 'cloud_sources.dart';
import 'portable_book_text.dart';

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
  final Set<int> _enriched = {};

  static int idForUrl(String url) {
    final digest = sha256.convert(utf8.encode(url)).bytes;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | digest[i];
    }
    return 2_000_000_000 + (value & 0x0FFFFFFF);
  }

  /// 只生成书架元数据，不联网、不下载。
  Novel metadata(
    String name,
    String url, {
    String? title,
    String? author,
    String? summary,
    String? coverUrl,
    String? cookie,
    String? authorization,
    String? sourceLabel,
    String? remoteEntryId,
    String? remoteKind,
  }) {
    final id = idForUrl(url);
    _urls[id] = url;
    final book = Novel(
      id: id,
      title: _cleanName(title?.trim().isNotEmpty == true ? title! : name),
      author: author?.trim().isNotEmpty == true ? author! : '网盘书源',
      genre: '在线读取',
      summary: summary?.trim().isNotEmpty == true
          ? summary!.trim()
          : '来自网盘直链，在线阅读，不下载原文件。',
      colors: const [Color(0xFF225577), Color(0xFF44AACC)],
      coverUrl: coverUrl,
      remoteUrl: url,
      remoteCookie: cookie,
      remoteAuthorization: authorization,
      sourceLabel: sourceLabel,
      remoteEntryId: remoteEntryId,
      remoteKind: remoteKind,
    );
    _metadata[id] = book;
    return book;
  }

  bool handles(int id) => _urls.containsKey(id);

  /// Drops in-memory text after the user removes an online shelf record.
  void forget(int id) {
    _urls.remove(id);
    _metadata.remove(id);
    _documents.remove(id);
  }

  Novel? known(int id) => _metadata[id];

  /// Reads the cloud object once into memory to recognize embedded title,
  /// author, summary and cover. No original file is written to the device.
  /// Parsing failures keep the filename-based shelf record instead of
  /// preventing the book from being added.
  Future<Novel> enrich(Novel novel) async {
    final cached = _metadata[novel.id];
    if (cached != null && _enriched.contains(novel.id)) return cached;
    final url = novel.remoteUrl;
    if (url == null || !handles(novel.id)) return novel;
    try {
      final resolved = await _resolveCloudUrl(url, novel);
      final bytes = await _fetch(
        resolved,
        cookie: novel.remoteCookie,
        authorization: novel.remoteAuthorization,
      );
      final parsed = await _parseAsync(novel.id, novel.title, resolved, bytes);
      final enriched = _withSource(parsed.novel, novel);
      _metadata[novel.id] = enriched;
      _enriched.add(novel.id);
      return enriched;
    } catch (_) {
      _metadata[novel.id] = novel;
      return novel;
    }
  }

  /// Deleting the real cloud object is an explicit opt-in. Account providers
  /// still keep the record if their APIs have not exposed a safe delete call.
  bool canDeleteRemote(Novel novel) =>
      novel.remoteEntryId != null &&
      (novel.remoteKind == 'webdav' ||
          novel.remoteKind == 's3' ||
          novel.remoteKind == 'quark' ||
          novel.remoteKind == 'lanzou');

  Future<void> deleteRemote(Novel novel) async {
    if (!canDeleteRemote(novel)) {
      throw const CloudSourceFailure('该网盘暂不支持 App 内删除，请到网盘网页端删除原文件');
    }
    final kind = CloudSourceKind.values.byName(novel.remoteKind!);
    final settings = CloudSourceSettings();
    await settings.load();
    final config = settings[kind];
    if (config == null) throw const CloudSourceFailure('网盘连接已失效，请重新配置');
    final client = CloudBookClient(config);
    try {
      await client.delete(
        CloudBookEntry(
          id: novel.remoteEntryId!,
          name: novel.title,
          folder: false,
        ),
      );
    } finally {
      client.close();
    }
  }

  /// Builds online-only shelf metadata for a file picked inside a cloud
  /// browser. Nothing is downloaded or written locally at this point.
  Novel cloudBook(CloudBookEntry entry, CloudSourceConfig config) {
    final url = switch (config.kind) {
      CloudSourceKind.quark || CloudSourceKind.lanzou => Uri(
        scheme: 'cloud',
        host: config.kind.name,
        pathSegments: [entry.id],
      ).toString(),
      CloudSourceKind.s3 => s3PresignedUrl(config, entry.id),
      _ => entry.id,
    };
    final authorization = config.username.trim().isEmpty
        ? null
        : 'Basic ' +
              base64Encode(
                utf8.encode('${config.username.trim()}:${config.password}'),
              );
    return metadata(
      entry.name,
      url,
      author: entry.author.isEmpty
          ? '${config.kind.label} · 在线阅读'
          : entry.author,
      cookie: config.cookie,
      authorization: authorization,
      sourceLabel: config.kind.label,
      remoteEntryId: entry.id,
      remoteKind: config.kind.name,
    );
  }

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
    final resolved = await _resolveCloudUrl(url, novel);
    final bytes = await _fetch(
      resolved,
      cookie: novel.remoteCookie,
      authorization: novel.remoteAuthorization,
    );
    final parsed = await _parseAsync(novel.id, novel.title, resolved, bytes);
    final full = _withSource(parsed.novel, novel);
    final document = _CloudDocument(
      full,
      parsed.bodies,
      coverBytes: parsed.coverBytes,
    );
    _documents[novel.id] = document;
    _metadata[novel.id] = full;
    _enriched.add(novel.id);
    return full;
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

  /// Resolution marker written by full-disk cloud search. The real short-lived
  /// download URL is obtained only when the reader opens the book.
  Future<String> _resolveCloudUrl(String url, Novel novel) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'cloud') return url;
    final kind = CloudSourceKind.values.byName(uri.host);
    if (kind != CloudSourceKind.quark && kind != CloudSourceKind.lanzou) {
      throw const FormatException('不支持的网盘书源');
    }
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    final cookie = novel.remoteCookie?.trim() ?? '';
    if (id.isEmpty || cookie.isEmpty) {
      throw const FormatException('网盘登录已失效，请重新登录账号');
    }
    CloudBookClient? client;
    try {
      client = CloudBookClient(CloudSourceConfig(kind: kind, cookie: cookie));
      final link = await client.directLink(
        CloudBookEntry(id: id, name: novel.title, folder: false),
      );
      if (link == null || link.isEmpty) {
        throw const FormatException('网盘没有返回下载地址');
      }
      return link;
    } finally {
      client?.close();
    }
  }

  Future<Uint8List> _fetch(
    String url, {
    String? cookie,
    String? authorization,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      var uri = Uri.parse(url);
      for (var hop = 0; hop < 6; hop++) {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        if (cookie != null && cookie.trim().isNotEmpty) {
          request.headers.set(HttpHeaders.cookieHeader, cookie.trim());
        }
        if (authorization != null && authorization.trim().isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            authorization.trim(),
          );
        }
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

  Future<_CloudDocument> _parseAsync(
    int id,
    String name,
    String url,
    Uint8List bytes,
  ) async {
    _CloudDocument parsed;
    if (name.toLowerCase().endsWith('.pdf')) {
      final text = await BookDocuments().extractPdfText(bytes);
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('PDF 没有可提取的文字');
      }
      parsed = _parseText(
        id,
        name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        url,
        Uint8List.fromList(utf8.encode(text)),
      );
    } else {
      parsed = _parse(id, name, url, bytes);
    }
    if (parsed.coverBytes != null) {
      try {
        await CloudBookMedia.saveCover(id, parsed.coverBytes!);
      } catch (_) {
        // Metadata stays usable even when the platform cache is unavailable.
      }
    }
    for (final entry in parsed.media.entries) {
      try {
        await CloudBookMedia.saveMedia(id, entry.key, entry.value);
      } catch (_) {
        // One broken illustration must not discard the readable text.
      }
    }
    return parsed;
  }

  _CloudDocument _parse(int id, String name, String url, Uint8List bytes) {
    final extension = name.split('.').last.toLowerCase();
    if (extension == 'html' || extension == 'htm' || extension == 'xhtml') {
      return _parseHtml(id, name, url, bytes);
    }
    if (PortableBookText.handles(name)) {
      try {
        final text = PortableBookText.extract(name, bytes);
        if (text != null && text.trim().isNotEmpty) {
          final meta = _portableMetadata(name, bytes);
          return _parseText(
            id,
            name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
            url,
            Uint8List.fromList(utf8.encode(text)),
            title: meta.title,
            author: meta.author,
            summary: meta.summary,
            coverBytes: meta.coverBytes,
          );
        }
      } catch (_) {
        // A malformed container falls through to the EPUB/text parser.
      }
    }
    final head = utf8
        .decode(bytes.take(512).toList(), allowMalformed: true)
        .toLowerCase();
    if (head.contains('<html') || head.contains('<!doctype html')) {
      return _parseHtml(id, name, url, bytes);
    }
    final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (isZip) {
      try {
        return _parseEpub(id, name, url, bytes);
      } catch (_) {
        // 不是 EPUB 的 ZIP 继续按文本处理。
      }
    }
    return _parseText(id, name, url, bytes);
  }

  _CloudDocument _parseText(
    int id,
    String name,
    String url,
    Uint8List bytes, {
    String? title,
    String? author,
    String? summary,
    Uint8List? coverBytes,
  }) {
    var text = utf8.decode(bytes, allowMalformed: true);
    final head = text.substring(0, text.length.clamp(0, 4000));
    author ??= RegExp(
      r'(?:作者|作\s*者|Author)\s*[:：]\s*([^\n\r]{1,40})',
      caseSensitive: false,
    ).firstMatch(head)?.group(1)?.trim();
    if (text.contains('\uFFFD')) {
      try {
        text = latin1.decode(bytes);
      } catch (_) {}
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n');
    if (title == null || title.trim().isEmpty) {
      for (final raw in lines.take(12)) {
        final line = raw.trim();
        if (line.isEmpty || line.length > 80) continue;
        if (RegExp(
          r'^(作者|作\s*者|Author|书名|简介|内容简介)\s*[:：]',
          caseSensitive: false,
        ).hasMatch(line)) {
          continue;
        }
        if (RegExp(r'^第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷篇]').hasMatch(line)) {
          continue;
        }
        title = line
            .replaceFirst(
              RegExp(r'^(书名|Title)\s*[:：]\s*', caseSensitive: false),
              '',
            )
            .trim();
        if (title.isNotEmpty) break;
      }
    }
    summary ??= _previewText(text, author: author, title: title);
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
    final novel = _novel(
      id,
      name,
      url,
      chapters,
      title: title,
      author: author,
      summary: summary,
      coverBytes: coverBytes,
    );
    return _CloudDocument(novel, bodies, coverBytes: coverBytes);
  }

  _CloudDocument _parseHtml(int id, String name, String url, Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final document = html.parse(text);
    final heading =
        (document
                    .querySelector('meta[property="og:title"]')
                    ?.attributes['content'] ??
                document.querySelector('h1')?.text ??
                document.querySelector('title')?.text ??
                name)
            .trim();
    final author =
        (document.querySelector('meta[name="author"]')?.attributes['content'] ??
                document
                    .querySelector('meta[property="article:author"]')
                    ?.attributes['content'] ??
                '')
            .trim();
    final paragraphs = document
        .querySelectorAll('p')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty && t.length > 1)
        .toList();
    final body = paragraphs.isEmpty
        ? (document.body?.text ?? '').trim()
        : paragraphs.join('\n\n');
    if (body.isEmpty) throw const FormatException('网页里没有可阅读的正文');
    final summary =
        (document
                    .querySelector('meta[property="og:description"]')
                    ?.attributes['content'] ??
                document
                    .querySelector('meta[name="description"]')
                    ?.attributes['content'] ??
                '')
            .trim();
    final chapters = [NovelChapter(_limit(heading, 80), '', id: 1)];
    final novel = _novel(
      id,
      name,
      url,
      chapters,
      title: heading,
      author: author,
      summary: summary.isEmpty ? _previewText(body) : summary,
    );
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
      final xml = utf8.decode(
        container.content as List<int>,
        allowMalformed: true,
      );
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
    String meta(String name) {
      final match = RegExp(
        '<dc:$name[^>]*>([^<]*)</dc:$name>',
        caseSensitive: false,
      ).firstMatch(opf);
      return match?.group(1)?.trim() ?? '';
    }

    final epubTitle = _plainText(meta('title'));
    final epubAuthors =
        RegExp('<dc:creator[^>]*>([^<]*)</dc:creator>', caseSensitive: false)
            .allMatches(opf)
            .map((m) => _plainText(m.group(1) ?? ''))
            .where((value) => value.isNotEmpty)
            .toList();
    final epubAuthor = epubAuthors.join('、');
    final epubSummary = _plainText(meta('description'));
    final base = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final manifest =
        <String, ({String href, String mediaType, String properties})>{};
    for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      final idMatch = RegExp(r'\bid="([^"]+)"').firstMatch(tag);
      final hrefMatch = RegExp(r'\bhref="([^"]+)"').firstMatch(tag);
      if (idMatch != null && hrefMatch != null) {
        manifest[idMatch.group(1)!] = (
          href: hrefMatch.group(1)!,
          mediaType:
              RegExp(r'\bmedia-type="([^"]+)"').firstMatch(tag)?.group(1) ?? '',
          properties:
              RegExp(r'\bproperties="([^"]+)"').firstMatch(tag)?.group(1) ?? '',
        );
      }
    }

    String? coverHref;
    final metaCover = RegExp(
      '<meta[^>]+name="cover"[^>]+content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(opf)?.group(1);
    if (metaCover != null && manifest[metaCover] != null) {
      coverHref = manifest[metaCover]!.href;
    }
    coverHref ??= manifest.values
        .firstWhere(
          (item) =>
              item.properties.split(RegExp(r'\s+')).contains('cover-image'),
          orElse: () => (href: '', mediaType: '', properties: ''),
        )
        .href;
    if (coverHref!.isEmpty) {
      coverHref = manifest.values
          .firstWhere(
            (item) =>
                item.mediaType.startsWith('image/') &&
                item.href.toLowerCase().contains('cover'),
            orElse: () => (href: '', mediaType: '', properties: ''),
          )
          .href;
    }
    Uint8List? coverBytes;
    if (coverHref!.isNotEmpty) {
      final coverFile = files[_normalize('$base${Uri.decodeFull(coverHref!)}')];
      if (coverFile != null) {
        final image = Uint8List.fromList(coverFile.content as List<int>);
        if (image.isNotEmpty && image.length <= 4 * 1024 * 1024) {
          coverBytes = image;
        }
      }
    }

    final ordered = <String>[];
    for (final m in RegExp(r'<itemref\b[^>]*>').allMatches(opf)) {
      final tag = m.group(0)!;
      final idref = RegExp(r'\bidref="([^"]+)"').firstMatch(tag)?.group(1);
      final href = idref == null ? null : manifest[idref]?.href;
      if (href != null) ordered.add(Uri.decodeFull(href));
    }
    if (ordered.isEmpty) ordered.addAll(manifest.values.map((e) => e.href));
    final chapters = <NovelChapter>[];
    final bodies = <int, String>{};
    final media = <String, Uint8List>{};
    var firstChapterText = '';
    for (final href in ordered) {
      final path = _normalize('$base$href');
      final file = files[path];
      if (file == null) continue;
      final markup = utf8.decode(
        file.content as List<int>,
        allowMalformed: true,
      );
      final document = html.parse(markup);
      final heading = (document.querySelector('h1, h2, title')?.text ?? '')
          .trim();
      final blocks = <String>[];
      for (final element in document.querySelectorAll('p, img')) {
        if (element.localName == 'img') {
          final src = (element.attributes['src'] ?? '').trim();
          if (src.isEmpty) continue;
          final imageFile = files[_normalize('$base${Uri.decodeFull(src)}')];
          if (imageFile == null) continue;
          final image = Uint8List.fromList(imageFile.content as List<int>);
          if (image.isEmpty || image.length > 4 * 1024 * 1024) continue;
          final key = sha1.convert(image).toString();
          media[key] = image;
          blocks.add(
            '<!--image-->${CloudBookMedia.mediaMarker(id, key)}<!--image-->',
          );
          continue;
        }
        final text = element.text.trim();
        if (text.isNotEmpty) blocks.add(text);
      }
      final body = blocks.isEmpty
          ? document.body?.text.trim() ?? ''
          : blocks.join('\n\n');
      if (body.trim().isEmpty) continue;
      if (firstChapterText.isEmpty) firstChapterText = body;
      final cid = chapters.length + 1;
      final title = heading.isNotEmpty
          ? _limit(heading, 80)
          : '第 ${chapters.length + 1} 章';
      chapters.add(NovelChapter(title, '', id: cid));
      bodies[cid] = body;
    }
    if (chapters.isEmpty) throw const FormatException('EPUB 没有可读章节');
    final novel = _novel(
      id,
      name,
      url,
      chapters,
      title: epubTitle.isEmpty ? null : epubTitle,
      author: epubAuthor.isEmpty ? null : epubAuthor,
      summary: epubSummary.isEmpty
          ? _previewText(firstChapterText)
          : epubSummary,
      coverBytes: coverBytes,
    );
    return _CloudDocument(novel, bodies, coverBytes: coverBytes, media: media);
  }

  Novel _withSource(Novel parsed, Novel source) {
    final fallbackAuthor =
        parsed.author == '网盘书源' || parsed.author.trim().isEmpty;
    final fallbackSummary = parsed.summary == '来自网盘直链，在线阅读，不下载原文件。';
    return Novel(
      id: parsed.id,
      title: parsed.title,
      author: fallbackAuthor && source.author.trim().isNotEmpty
          ? source.author
          : parsed.author,
      genre: parsed.genre,
      summary: fallbackSummary && source.summary.trim().isNotEmpty
          ? source.summary
          : parsed.summary,
      colors: parsed.colors,
      chapters: parsed.chapters,
      isComplete: parsed.isComplete,
      coverUrl: parsed.coverUrl ?? source.coverUrl,
      lastUpdate: parsed.lastUpdate,
      chapterCount: parsed.chapterCount,
      navigation: parsed.navigation,
      // Keep the cloud:// marker (or original direct URL), not the short-lived
      // download address resolved for this reading session.
      remoteUrl: source.remoteUrl ?? parsed.remoteUrl,
      remoteCookie: source.remoteCookie,
      remoteAuthorization: source.remoteAuthorization,
      sourceLabel: source.sourceLabel,
      remoteEntryId: source.remoteEntryId,
      remoteKind: source.remoteKind,
    );
  }

  Novel _novel(
    int id,
    String name,
    String url,
    List<NovelChapter> chapters, {
    String? title,
    String? author,
    String? summary,
    Uint8List? coverBytes,
  }) => Novel(
    id: id,
    title: _cleanName(title?.trim().isNotEmpty == true ? title! : name),
    author: author?.trim().isNotEmpty == true ? author! : '网盘书源',
    genre: '在线读取',
    summary: summary?.trim().isNotEmpty == true
        ? _limit(summary!.trim(), 500)
        : '来自网盘直链，在线阅读，不下载原文件。',
    colors: const [Color(0xFF225577), Color(0xFF44AACC)],
    chapters: chapters,
    coverUrl: coverBytes == null ? null : CloudBookMedia.marker(id),
    chapterCount: chapters.length,
    isComplete: true,
    remoteUrl: url,
  );

  String _normalize(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (part != '.' && part.isNotEmpty)
        parts.add(part);
    }
    return parts.join('/');
  }

  String _plainText(String value) {
    if (value.trim().isEmpty) return '';
    try {
      return html.parseFragment(value).text?.trim() ?? '';
    } catch (_) {
      return value.trim();
    }
  }

  String _previewText(String text, {String? author, String? title}) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) {
          if (line.isEmpty) return false;
          if (RegExp(
            r'^(作者|作\s*者|Author|书名|Title|简介|内容简介)\s*[:：]',
            caseSensitive: false,
          ).hasMatch(line)) {
            return false;
          }
          if (title != null && line == title.trim()) return false;
          if (author != null && line == author.trim()) return false;
          return true;
        })
        .join('\n');
    final flat = lines.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _limit(flat, 260);
  }

  ({String? title, String? author, String? summary, Uint8List? coverBytes})
  _portableMetadata(String name, Uint8List bytes) {
    final ext = name.split('.').last.toLowerCase();
    try {
      return switch (ext) {
        'docx' => _zipMetadata(
          bytes,
          coreName: 'docProps/core.xml',
          thumbnailNames: const [
            'docProps/thumbnail.jpeg',
            'docProps/thumbnail.jpg',
            'docProps/thumbnail.png',
          ],
        ),
        'odt' => _zipMetadata(
          bytes,
          coreName: 'meta.xml',
          thumbnailNames: const ['Thumbnails/thumbnail.png'],
        ),
        'fb2' => _fb2Metadata(bytes),
        _ => (title: null, author: null, summary: null, coverBytes: null),
      };
    } catch (_) {
      return (title: null, author: null, summary: null, coverBytes: null);
    }
  }

  ({String? title, String? author, String? summary, Uint8List? coverBytes})
  _zipMetadata(
    Uint8List bytes, {
    required String coreName,
    required List<String> thumbnailNames,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) files[file.name.replaceAll('\\', '/')] = file;
    }
    final core = files[coreName];
    String value(String tag) {
      if (core == null) return '';
      final source = utf8.decode(
        core.content as List<int>,
        allowMalformed: true,
      );
      return _plainText(
        RegExp(
              '<(?:(?:dc|meta):)?$tag[^>]*>([^<]*)</(?:(?:dc|meta):)?$tag>',
              caseSensitive: false,
            ).firstMatch(source)?.group(1) ??
            '',
      );
    }

    Uint8List? cover;
    for (final name in thumbnailNames) {
      final file = files[name];
      if (file == null) continue;
      final image = Uint8List.fromList(file.content as List<int>);
      if (image.isNotEmpty && image.length <= 4 * 1024 * 1024) {
        cover = image;
        break;
      }
    }
    return (
      title: value('title').isEmpty ? null : value('title'),
      author: value('creator').isEmpty ? null : value('creator'),
      summary: value('description').isEmpty ? null : value('description'),
      coverBytes: cover,
    );
  }

  ({String? title, String? author, String? summary, Uint8List? coverBytes})
  _fb2Metadata(Uint8List bytes) {
    final document = xml.XmlDocument.parse(
      utf8.decode(bytes, allowMalformed: true),
    );
    final elements = document.descendants.whereType<xml.XmlElement>().toList();
    String textOf(String name) {
      final element = elements.where((e) => e.name.local == name).firstOrNull;
      return element?.innerText.trim() ?? '';
    }

    final first = textOf('first-name');
    final middle = textOf('middle-name');
    final last = textOf('last-name');
    final author = [
      first,
      middle,
      last,
    ].where((part) => part.isNotEmpty).join(' ').trim();
    Uint8List? cover;
    final coverPage = elements
        .where((e) => e.name.local == 'coverpage')
        .firstOrNull;
    final image = coverPage?.descendants
        .whereType<xml.XmlElement>()
        .where((e) => e.name.local == 'image')
        .firstOrNull;
    final href =
        image?.getAttribute('href') ?? image?.getAttribute('xlink:href') ?? '';
    final id = href.contains('#') ? href.split('#').last : '';
    if (id.isNotEmpty) {
      final binary = elements
          .where((e) => e.name.local == 'binary' && e.getAttribute('id') == id)
          .firstOrNull;
      if (binary != null) {
        try {
          final decoded = base64Decode(binary.innerText.trim());
          if (decoded.isNotEmpty && decoded.length <= 4 * 1024 * 1024) {
            cover = decoded;
          }
        } catch (_) {}
      }
    }
    return (
      title: textOf('book-title').isEmpty ? null : textOf('book-title'),
      author: author.isEmpty ? null : author,
      summary: textOf('annotation').isEmpty ? null : textOf('annotation'),
      coverBytes: cover,
    );
  }

  String _cleanName(String name) {
    var value = name
        .replaceAll(
          RegExp(
            r'\.(txt|epub|mobi|prc|azw3?|pdf|docx|odt|rtf|fb2|html?|xhtml|md|markdown|zip)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (value.isEmpty) value = '网盘书籍';
    return _limit(value, 120);
  }

  String _limit(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}

class _CloudDocument {
  const _CloudDocument(
    this.novel,
    this.bodies, {
    this.coverBytes,
    this.media = const {},
  });
  final Novel novel;
  final Map<int, String> bodies;
  final Uint8List? coverBytes;
  final Map<String, Uint8List> media;
}
