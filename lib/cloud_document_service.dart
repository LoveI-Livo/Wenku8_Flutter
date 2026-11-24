import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart' as xml;

import 'book_documents.dart';
import 'book_identity.dart';
import 'catalog.dart';
import 'cloud_book_media.dart';
import 'cloud_cover_media.dart';
import 'cloud_parse_service.dart';
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
  final Map<int, Map<int, String>> _webChapterUrls = {};
  final Map<int, String> _legadoPayloads = {};
  final Map<int, Future<Uint8List?>> _coverPending = {};
  final Set<int> _coverMissed = {};

  /// 坏源或失效 CDN 不能让详情页无限转圈。业务异常保持原提示，超时统一
  /// 换成可操作的中文提示，用户至少能换源/重试。
  Future<T> _bounded<T>(
    Future<T> future,
    String timeoutMessage, {
    Duration after = const Duration(seconds: 18),
  }) async {
    try {
      return await future.timeout(after);
    } on TimeoutException {
      throw CloudSourceFailure(timeoutMessage);
    }
  }

  static int idForUrl(String url) {
    final digest = sha256.convert(utf8.encode(url)).bytes;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | digest[i];
    }
    // 0x40000000..0x5fffffff: stable and below localBookIdStart. The old
    // 2_000_000_000 range overlapped local-book backup/ID validation and made
    // cloud shelf records silently disappear.
    return cloudBookIdStart + (value & 0x1fffffff);
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
      genre: '',
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

  /// 书架在重启后先拿到持久化的 Novel，再调用目录/正文。这里把远程字段
  /// 重新挂回内存，避免 `chapters()` 在详情还没加载时误报“请从书架重新打开”。
  Novel adopt(Novel novel) {
    final url = novel.remoteUrl?.trim() ?? '';
    final source = _polishDisplay(novel);
    if (url.isNotEmpty) {
      _urls[novel.id] = url;
      _metadata.putIfAbsent(novel.id, () => source);
    }
    return source;
  }

  /// 网盘书不再在书架、详情页堆一长串“OpenList / WebDAV · 在线阅读”，
  /// 统一显示“在线阅读”。真实作者、书源书名仍保留。
  Novel _polishDisplay(Novel novel) {
    final kind = novel.remoteKind?.trim() ?? '';
    if (kind.isEmpty || kind == CloudSourceKind.rss.name) return novel;
    final author = novel.author.trim();
    final authorIsProvider =
        author.isEmpty ||
        author.contains('在线阅读') ||
        author.contains('网盘') ||
        author.contains('WebDAV') ||
        author.contains('OpenList') ||
        author == '网盘书源';
    return novel.withMetadata(
      author: authorIsProvider ? '在线阅读' : novel.author,
      sourceLabel: '在线阅读',
    );
  }

  /// Drops in-memory text after the user removes an online shelf record.
  void forget(int id) {
    _urls.remove(id);
    _metadata.remove(id);
    _documents.remove(id);
    _webChapterUrls.remove(id);
    _legadoPayloads.remove(id);
    _coverPending.remove(id);
    _coverMissed.remove(id);
    CloudCoverMedia.forget(id);
  }

  Novel? known(int id) => _metadata[id];

  /// 网盘搜索结果常常只有文件名，封面嵌在 EPUB/TXT 里。详情页打开时才
  /// 解析整本文件太慢，这里在列表可见时用解析主机做一次 metaOnly 探测；
  /// 没配置解析主机就直接返回 null，不偷偷下载整本书。
  Future<Uint8List?> coverBytes(Novel novel) {
    final cached = CloudCoverMedia.peek(novel.id, url: novel.coverUrl);
    if (cached != null) return Future.value(cached);
    if (_coverMissed.contains(novel.id)) return Future.value(null);
    final pending = _coverPending[novel.id];
    if (pending != null) return pending;
    final future = _loadCover(novel);
    _coverPending[novel.id] = future;
    return future.whenComplete(() => _coverPending.remove(novel.id));
  }

  Future<Uint8List?> _loadCover(Novel novel) async {
    try {
      final enriched = await enrich(
        novel,
        cloudOnly: true,
      ).timeout(const Duration(seconds: 9));
      final url = enriched.coverUrl;
      if (url == null || url.isEmpty) {
        _coverMissed.add(novel.id);
        return null;
      }
      if (CloudBookMedia.handles(url)) {
        return await CloudBookMedia.loadCover(url);
      }
      return await CloudCoverMedia.load(
        enriched.id,
        url,
        cookie: enriched.remoteCookie ?? '',
        authorization: enriched.remoteAuthorization ?? '',
        sourceUrl: enriched.remoteUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// 已识别过的网盘/书源书。搜索先查在线目录，目录暂时没返回时用它兜底，
  /// 已经加入书架的书仍然能被书名、作者和来源搜到。
  Iterable<Novel> get knownBooks => _metadata.values;

  /// Reads the cloud object once into memory to recognize embedded title,
  /// author, summary and cover. No original file is written to the device.
  /// Parsing failures keep the filename-based shelf record instead of
  /// preventing the book from being added. When [cloudOnly] is true (search
  /// indexing), failure returns the original metadata instead of downloading
  /// the book to the phone.
  Future<Novel> enrich(Novel novel, {bool cloudOnly = false}) async {
    final cached = _metadata[novel.id];
    if (cached != null && _enriched.contains(novel.id)) return cached;
    final url = novel.remoteUrl;
    if (url == null || !handles(novel.id)) return novel;
    if (url.startsWith('legado://')) {
      final full = await detail(novel);
      _enriched.add(novel.id);
      return full;
    }
    try {
      final resolved = await _resolveCloudUrl(url, novel);
      CloudRemoteDocument? remote;
      try {
        remote = await CloudParseService.instance
            .parse(novel, resolvedUrl: resolved, metaOnly: true)
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // 解析主机只是加速器；超时不能拖住搜索/详情，直接退回文件名元数据。
        remote = null;
      }
      if (remote != null) {
        final coverBytes = remote.coverBytes;
        String? coverUrl;
        if (coverBytes != null && coverBytes.isNotEmpty && !cloudOnly) {
          coverUrl = await _publishCover(novel.id, coverBytes);
          if (coverUrl == null) {
            try {
              await CloudBookMedia.saveCover(novel.id, coverBytes);
            } catch (_) {
              // 主机不可用时封面只在运行期内存中，不写本机磁盘。
            }
          }
        } else if (coverBytes != null && coverBytes.isNotEmpty) {
          try {
            await CloudBookMedia.saveCover(novel.id, coverBytes);
          } catch (_) {
            // 只做内存缓存，搜索阶段不写本机磁盘。
          }
        }
        final enriched = novel.withMetadata(
          title: remote.title,
          author: remote.author,
          summary: remote.summary,
          coverUrl:
              coverUrl ??
              (coverBytes == null || coverBytes.isEmpty
                  ? null
                  : CloudBookMedia.marker(novel.id)),
        );
        _metadata[novel.id] = enriched;
        _enriched.add(novel.id);
        return enriched;
      }
      if (cloudOnly) return novel;
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
          novel.remoteKind == 'lanzou' ||
          novel.remoteKind == 'guangya');

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
  /// 账号网盘的文件 ID 不是直链，先保存成可恢复的 cloud:// 标记；
  /// 打开书时再用当前登录凭证换取临时下载地址。旧版把阿里/迅雷/123 的
  /// 裸 file id 直接当 URL，导致“加入书架后目录加载失败”。
  String _cloudMarker(
    CloudSourceKind kind,
    String entryId, {
    String connectionId = '',
  }) => Uri(
    scheme: 'cloud',
    host: kind.name,
    pathSegments: [entryId],
    queryParameters: connectionId.trim().isEmpty
        ? null
        : {'connection': connectionId.trim()},
  ).toString();

  Novel cloudBook(CloudBookEntry entry, CloudSourceConfig config) {
    final url = switch (config.kind) {
      CloudSourceKind.webdav => entry.id,
      CloudSourceKind.s3 => s3PresignedUrl(config, entry.id),
      CloudSourceKind.quark ||
      CloudSourceKind.lanzou ||
      CloudSourceKind.lanzouPro ||
      CloudSourceKind.xunlei ||
      CloudSourceKind.guangya ||
      CloudSourceKind.aliyun ||
      CloudSourceKind.baidu ||
      CloudSourceKind.pan123 ||
      CloudSourceKind.uc => _cloudMarker(
        config.kind,
        entry.id,
        connectionId: config.connectionId,
      ),
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
      summary: entry.summary.isEmpty ? null : entry.summary,
      author: entry.author.isEmpty ? '在线阅读' : entry.author,
      coverUrl: entry.coverUrl,
      cookie: config.cookie,
      authorization: authorization,
      sourceLabel: config.kind == CloudSourceKind.rss
          ? config.kind.label
          : '在线阅读',
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
    if (url.startsWith('legado://')) {
      return _detailFromLegado(novel, url);
    }
    if (novel.remoteKind == CloudSourceKind.rss.name &&
        _looksLikeWebPage(url)) {
      return _detailFromWeb(novel, url);
    }
    final resolved = await _resolveCloudUrl(url, novel);
    CloudRemoteDocument? remote;
    try {
      remote = await CloudParseService.instance
          .parse(novel, resolvedUrl: resolved)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      // 解析主机超时后仍然尝试直接读文件，不把用户卡在无限加载里。
      remote = null;
    }
    if (remote != null) {
      final document = await _fromRemote(novel.id, novel, resolved, remote);
      _documents[novel.id] = document;
      _metadata[novel.id] = document.novel;
      _enriched.add(novel.id);
      return document.novel;
    }
    final bytes = await _bounded(
      _fetch(
        resolved,
        cookie: novel.remoteCookie,
        authorization: novel.remoteAuthorization,
      ),
      '网盘文件下载超时，请检查网络或换一个更小的文件',
      after: const Duration(seconds: 40),
    );
    final parsed = await _bounded(
      _parseAsync(novel.id, novel.title, resolved, bytes),
      '文件解析超时，请换一个文件重试',
      after: const Duration(seconds: 20),
    );
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

  bool _looksLikeWebPage(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.isEmpty || path.endsWith('/')) return true;
    return !RegExp(
      r'\.(?:txt|md|markdown|epub|mobi|azw3?|prc|fb2|pdf|docx|odt|rtf|xhtml|html?|zip)$',
    ).hasMatch(path);
  }

  Future<Novel> _detailFromWeb(Novel novel, String url) async {
    final document = await _bounded(
      WebNovelReader.inspect(
        url,
        cookie: novel.remoteCookie ?? '',
        authorization: novel.remoteAuthorization ?? '',
        allowHttp: url.startsWith('http://'),
      ),
      '书源网页加载超时，请换一个书源或稍后重试',
    );
    if (!document.hasContent) {
      throw const FormatException('这个书源网页没有可读取的目录或正文');
    }
    final chapters = <NovelChapter>[
      for (var index = 0; index < document.chapters.length; index++)
        NovelChapter(document.chapters[index].title, '', id: index + 1),
    ];
    final full = novel
        .withMetadata(
          title: document.title,
          author: document.author,
          summary: document.summary,
          coverUrl: document.coverUrl,
        )
        .withChapters(chapters);
    _documents[novel.id] = _CloudDocument(full, <int, String>{});
    _webChapterUrls[novel.id] = {
      for (var index = 0; index < document.chapters.length; index++)
        index + 1: document.chapters[index].url,
    };
    _metadata[novel.id] = full;
    _enriched.add(novel.id);
    return full;
  }

  Future<Novel> _detailFromLegado(Novel novel, String payload) async {
    WebNovelDocument? document;
    Object? primaryError;
    try {
      final parsed = await _bounded(
        LegadoReader.detail(
          payload,
          allowHttp: false,
          cookie: novel.remoteCookie ?? '',
          authorization: novel.remoteAuthorization ?? '',
        ),
        '书源详情加载超时，请换一个书源或稍后重试',
      );
      document = parsed.document;
    } catch (error) {
      primaryError = error;
      // 规则选择器失效时，仍然尝试把书源详情页当普通网页解析。
      final decoded = LegadoReader.decodePayload(payload);
      final bookUrl = (decoded?['book'] ?? '').toString().trim();
      if (bookUrl.isNotEmpty) {
        try {
          final generic = await _bounded(
            WebNovelReader.inspect(
              bookUrl,
              cookie: novel.remoteCookie ?? '',
              authorization: novel.remoteAuthorization ?? '',
              allowHttp: bookUrl.startsWith('http://'),
            ),
            '书源详情加载超时，请换一个书源或稍后重试',
          );
          if (generic.hasContent) document = generic;
        } catch (_) {
          // 保留原始错误，下面会换成可操作提示。
        }
      }
    }
    if (document == null) {
      throw CloudSourceFailure(
        '书源详情加载失败：${primaryError == null ? '目录为空' : primaryError.toString()}',
      );
    }
    final chapters = <NovelChapter>[
      for (var index = 0; index < document.chapters.length; index++)
        NovelChapter(document.chapters[index].title, '', id: index + 1),
    ];
    final full = novel
        .withMetadata(
          title: document.title,
          author: document.author,
          summary: document.summary,
          coverUrl: document.coverUrl,
        )
        .withChapters(chapters);
    _documents[novel.id] = _CloudDocument(full, <int, String>{});
    _legadoPayloads[novel.id] = payload;
    _webChapterUrls[novel.id] = {
      for (var index = 0; index < document.chapters.length; index++)
        index + 1: document.chapters[index].url,
    };
    _metadata[novel.id] = full;
    _enriched.add(novel.id);
    return full;
  }

  /// 网盘搜索的兜底：文件名/元数据都没命中时，检查已解析正文是否包含关键词。
  /// 只在少量小文件上调用，解析结果同时留给详情页复用。
  Future<bool> containsText(Novel novel, String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return false;
    try {
      await detail(novel);
      final document = _documents[novel.id];
      if (document == null) return false;
      for (final body in document.bodies.values) {
        if (body.toLowerCase().contains(needle)) return true;
      }
      for (final chapter in document.novel.chapters) {
        if (chapter.title.toLowerCase().contains(needle)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
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
    final cached = document.bodies[chapter.id];
    if (cached != null && cached.isNotEmpty) return cached;
    final url = _webChapterUrls[id]?[chapter.id];
    if (url == null) {
      return '本章正文暂时没有取到，请返回目录重新打开，或换一个来源重试。';
    }
    if (_legadoPayloads[id] case final payload?) {
      try {
        final text = await _bounded(
          LegadoReader.content(
            url,
            payload: payload,
            cookie: document.novel.remoteCookie ?? '',
            authorization: document.novel.remoteAuthorization ?? '',
          ),
          '书源正文加载超时，请重试',
        );
        document.bodies[chapter.id] = text;
        return text;
      } catch (_) {
        // 规则选择器失效或章节页结构变了时，不要让阅读页永远空着；
        // 再用通用网页正文识别兜底一次（这是同一章 URL，不会串章）。
        final fallback = await _bounded(
          WebNovelReader.content(
            url,
            cookie: document.novel.remoteCookie ?? '',
            authorization: document.novel.remoteAuthorization ?? '',
            allowHttp: url.startsWith('http://'),
          ),
          '书源正文加载超时，请重试',
        );
        document.bodies[chapter.id] = fallback;
        return fallback;
      }
    }
    final novel = document.novel;
    final text = await _bounded(
      WebNovelReader.content(
        url,
        cookie: novel.remoteCookie ?? '',
        authorization: novel.remoteAuthorization ?? '',
        allowHttp: url.startsWith('http://'),
      ),
      '书源正文加载超时，请重试',
    );
    document.bodies[chapter.id] = text;
    return text;
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

  /// 账号网盘的书只保存文件 ID，打开时用当前登录凭证换取临时直链。
  /// 兼容两类记录：新版 `cloud://kind/id`，以及旧版直接保存的裸文件 ID。
  Future<String> _resolveCloudUrl(String url, Novel novel) async {
    final uri = Uri.tryParse(url);
    CloudSourceKind? kind;
    var id = '';
    var connectionId = '';
    if (uri != null && uri.scheme == 'cloud') {
      try {
        kind = CloudSourceKind.values.byName(uri.host);
      } on ArgumentError {
        throw const FormatException('网盘书源类型无法识别');
      }
      id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      connectionId = uri.queryParameters['connection'] ?? '';
    } else {
      final recorded = novel.remoteKind?.trim() ?? '';
      if (recorded.isNotEmpty) {
        for (final value in CloudSourceKind.values) {
          if (value.name == recorded) {
            kind = value;
            break;
          }
        }
      }
      // WebDAV / S3 / 直链 / RSS 保存的本来就是可用地址。
      if (kind == null ||
          kind == CloudSourceKind.webdav ||
          kind == CloudSourceKind.s3 ||
          kind == CloudSourceKind.direct ||
          kind == CloudSourceKind.rss) {
        return url;
      }
      id = url.trim();
    }
    if (kind == null || id.isEmpty) {
      throw const FormatException('网盘文件标识已丢失，请重新从网络书架添加');
    }
    final settings = CloudSourceSettings();
    await settings.ensureLoaded();
    var configs = settings.configsFor(kind).toList(growable: false);
    if (connectionId.isNotEmpty) {
      configs = configs
          .where((config) => config.connectionId == connectionId)
          .toList(growable: false);
    }
    if (configs.isEmpty) {
      // 配置可能被删除或换了连接；同类型还有账号时继续尝试，让用户
      // 重新登录后的连接可以直接接管旧书架记录。
      configs = settings.configsFor(kind).toList(growable: false);
    }
    if (configs.isEmpty) {
      throw FormatException('${kind.label}连接已失效，请到「网络 → 添加网盘」重新登录官网账号');
    }
    final failures = <String>[];
    for (final config in configs) {
      CloudBookClient? client;
      try {
        client = CloudBookClient(config, settings: settings);
        final link = await _bounded(
          client.directLink(
            CloudBookEntry(id: id, name: novel.title, folder: false),
          ),
          '网盘获取下载地址超时，请重新登录后再试',
          after: const Duration(seconds: 12),
        );
        if (link != null && link.trim().isNotEmpty) return link.trim();
        failures.add('${config.label}没有返回下载地址');
      } catch (error) {
        failures.add(cloudFailureMessage(error));
      } finally {
        client?.close();
      }
    }
    final detail = failures.isEmpty ? '' : '（${failures.first}）';
    throw FormatException('${kind.label}目录读取失败，请重新登录官网账号后重试$detail');
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
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
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
        await for (final part in response.timeout(
          const Duration(seconds: 30),
        )) {
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

  Future<_CloudDocument> _fromRemote(
    int id,
    Novel source,
    String url,
    CloudRemoteDocument remote,
  ) async {
    final coverBytes = remote.coverBytes;
    String? coverUrl;
    if (coverBytes != null && coverBytes.isNotEmpty) {
      coverUrl = await _publishCover(id, coverBytes);
      if (coverUrl == null) await CloudBookMedia.saveCover(id, coverBytes);
    }
    final media = <String, Uint8List>{};
    for (final entry in remote.media.entries) {
      final marker = CloudBookMedia.cacheMedia(id, entry.key, entry.value);
      if (marker.isEmpty) continue;
      media[entry.key] = Uint8List(0);
    }
    final mediaMarkers = media.map(
      (key, _) => MapEntry(
        '[[CLOUD_MEDIA:$key]]',
        '<!--image-->${CloudBookMedia.mediaMarker(id, key)}<!--image-->',
      ),
    );
    String body(String value) {
      var text = value;
      for (final entry in mediaMarkers.entries) {
        text = text.replaceAll(entry.key, entry.value);
      }
      return text.trim();
    }

    final chapters = <NovelChapter>[];
    final bodies = <int, String>{};
    for (final item in remote.chapters) {
      final content = body(item.content);
      final cid = chapters.length + 1;
      chapters.add(NovelChapter(_limit(item.title, 80), '', id: cid));
      // 目录必须完整；部分章节正文为空时仍保留标题，阅读器可以重试，
      // 而不是整章从目录里消失。
      if (content.isNotEmpty) bodies[cid] = content;
    }
    if (chapters.isEmpty) throw const FormatException('云端解析没有返回可读章节');
    final parsed = _novel(
      id,
      source.title,
      url,
      chapters,
      title: remote.title,
      author: remote.author,
      summary: remote.summary,
      coverBytes: coverBytes,
      coverUrl: coverUrl,
    );
    final full = _withSource(parsed, source);
    return _CloudDocument(full, bodies, coverBytes: coverBytes);
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
    var published = parsed.novel;
    if (parsed.coverBytes != null) {
      final coverUrl = await _publishCover(id, parsed.coverBytes!);
      if (coverUrl != null) {
        published = published.withMetadata(coverUrl: coverUrl);
      } else {
        await CloudBookMedia.saveCover(id, parsed.coverBytes!);
      }
    }
    for (final entry in parsed.media.entries) {
      CloudBookMedia.cacheMedia(id, entry.key, entry.value);
    }
    return _CloudDocument(
      published,
      parsed.bodies,
      coverBytes: parsed.coverBytes,
    );
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
    var text = PortableBookText.decodeText(bytes);
    final head = text.substring(0, text.length.clamp(0, 4000));
    author ??= RegExp(
      r'(?:作者|作\s*者|Author)\s*[:：]\s*([^\n\r]{1,40})',
      caseSensitive: false,
    ).firstMatch(head)?.group(1)?.trim();
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
      final bodyText = document.body?.text.trim() ?? '';
      final textLength = blocks
          .where((block) => !block.contains('<!--image-->'))
          .fold<int>(0, (sum, block) => sum + block.length);
      // 有些 EPUB 的正文放在 div 里，只有少量 p。若只收集 p 会像丢章；
      // 当整页纯文本明显多于块级文本时，直接采用整页文本。
      final flatText = blocks
          .where((block) => !block.contains('<!--image-->'))
          .join('\n\n');
      final body = blocks.isEmpty
          ? bodyText
          : (bodyText.length > textLength + 20 &&
                    bodyText.length > flatText.length
                ? bodyText
                : blocks.join('\n\n'));
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

  Future<String?> _publishCover(int id, Uint8List bytes) async {
    try {
      return await CloudParseService.instance.uploadCover(id, bytes);
    } catch (_) {
      return null;
    }
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
    String? coverUrl,
  }) => Novel(
    id: id,
    title: _cleanName(title?.trim().isNotEmpty == true ? title! : name),
    author: author?.trim().isNotEmpty == true ? author! : '网盘书源',
    genre: '',
    summary: summary?.trim().isNotEmpty == true
        ? _limit(summary!.trim(), 500)
        : '来自网盘直链，在线阅读，不下载原文件。',
    colors: const [Color(0xFF225577), Color(0xFF44AACC)],
    chapters: chapters,
    coverUrl:
        coverUrl ?? (coverBytes == null ? null : CloudBookMedia.marker(id)),
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
