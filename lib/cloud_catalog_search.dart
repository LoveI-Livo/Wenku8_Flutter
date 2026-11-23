import 'dart:async';

import 'book_search.dart';
import 'catalog.dart';
import 'cloud_document_service.dart';
import 'cloud_parse_service.dart';
import 'cloud_sources.dart';

enum CloudSearchScope { all, netDisks, sources }

/// 搜索页可选的单一来源。
class CloudSearchTarget {
  const CloudSearchTarget({required this.key, required this.label, this.url});
  final String key, label;
  final String? url;
}

/// 全局搜索里的网盘 / 书源索引。
///
/// 先按文件名、作者和书源简介匹配；没有命中时，再对体积较小的文件做一次
/// 主机/内存元数据识别，读取书名、作者、简介。只读取元数据，不把原文件
/// 保存到本机，也不会对每个网盘文件都发起解析。
class CloudCatalogSearch {
  CloudCatalogSearch._();
  static final instance = CloudCatalogSearch._();
  final CloudSourceSettings settings = CloudSourceSettings();

  static const _walkBudget = Duration(seconds: 12);
  static const _probeBudget = Duration(seconds: 12);
  static const _maxProbeBytes = 8 * 1024 * 1024;
  static const _maxProbeFiles = 12;
  static const _maxResults = 500;
  static const _cacheLifetime = Duration(minutes: 10);
  String? _cacheQuery;
  CloudSearchScope? _cacheScope;
  String? _cacheTarget;
  DateTime? _cacheAt;
  List<Novel>? _cache;

  /// 最近一次搜索中被跳过的来源错误，页面可用来提示“不是没书，而是源没连上”。
  String? lastFailure;

  /// 每次搜索都重新读取当前已连接来源，新添加的网盘会自动进入搜索，
  /// 不需要重启 App，也不依赖固定列表。
  Future<void> reload() async {
    _cache = null;
    _cacheAt = null;
    await settings.load();
  }

  /// 当前范围可用于搜索的来源。网盘按连接区分，书源按单个地址区分。
  Future<List<CloudSearchTarget>> targets(CloudSearchScope scope) async {
    await settings.load();
    final result = <CloudSearchTarget>[];
    for (final config in settings.configs) {
      final allowed = switch (scope) {
        CloudSearchScope.all =>
          config.kind.isDirectLink || config.kind.isAccount,
        CloudSearchScope.netDisks => config.kind != CloudSourceKind.rss,
        CloudSearchScope.sources => config.kind == CloudSourceKind.rss,
      };
      if (!allowed) continue;
      if (config.kind == CloudSourceKind.rss) {
        for (final source
            in config.sources.isNotEmpty
                ? config.sources.where((value) => value.enabled)
                : config.effectiveSources) {
          result.add(
            CloudSearchTarget(
              key: 'rss:${source.url}',
              label:
                  '${source.label} · ${Uri.tryParse(source.url)?.host ?? ''}',
              url: source.url,
            ),
          );
        }
      } else {
        final host = Uri.tryParse(config.address)?.host;
        result.add(
          CloudSearchTarget(
            key: config.connectionId.isEmpty
                ? config.kind.name
                : '${config.kind.name}:${config.connectionId}',
            label: host == null || host.isEmpty
                ? config.label
                : '${config.label} · $host',
          ),
        );
      }
    }
    return result;
  }

  Future<List<Novel>> search(
    String query, {
    CloudSearchScope scope = CloudSearchScope.all,
    String? sourceKey,
    Set<String>? sourceKeys,
    bool refresh = false,
  }) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final keys = sourceKeys ?? {if (sourceKey != null) sourceKey};
    final cacheKey = keys.isEmpty ? '' : (keys.toList()..sort()).join('\n');
    if (!refresh &&
        _cache != null &&
        _cacheQuery == value &&
        _cacheScope == scope &&
        _cacheTarget == cacheKey &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheLifetime) {
      return _cache!;
    }
    await settings.load();
    lastFailure = null;
    final failures = <String>[];
    final configs = settings.configs
        .where(
          (config) => switch (scope) {
            CloudSearchScope.all =>
              config.kind.isDirectLink || config.kind.isAccount,
            CloudSearchScope.netDisks => config.kind != CloudSourceKind.rss,
            CloudSearchScope.sources => config.kind == CloudSourceKind.rss,
          },
        )
        .where(
          (config) =>
              keys.isEmpty ||
              (config.kind == CloudSourceKind.rss
                  ? keys.any(
                      (key) =>
                          key.startsWith('rss:') &&
                          (config.sources.isNotEmpty
                              ? config.sources.any(
                                  (source) =>
                                      source.enabled &&
                                      'rss:${source.url}' == key,
                                )
                              : config.effectiveSources.any(
                                  (source) => 'rss:${source.url}' == key,
                                )),
                    )
                  : keys.contains(config.kind.name) ||
                        keys.contains(
                          '${config.kind.name}:${config.connectionId}',
                        )),
        )
        .toList();
    if (configs.isEmpty) return const [];

    final parseSettings = CloudParseSettings.instance;
    await parseSettings.load();
    final results = <Novel>[];
    await Future.wait(
      configs.map((config) async {
        CloudBookClient? client;
        try {
          final selectedUrls = config.kind == CloudSourceKind.rss
              ? [
                  for (final key in keys)
                    if (key.startsWith('rss:')) key.substring(4),
                ]
              : const <String>[];
          client = config.kind == CloudSourceKind.rss && selectedUrls.isNotEmpty
              ? RssBookClient(config, sources: selectedUrls)
              : CloudBookClient(config);
          final walk = await _searchClient(client, value).timeout(_walkBudget);

          if (walk.matches.isNotEmpty) {
            for (final entry in walk.matches) {
              if (results.length >= _maxResults) return;
              final novel = _novelFor(entry, config);
              if (!results.any((existing) => existing.id == novel.id)) {
                results.add(novel);
              }
            }
            return;
          }

          // 文件名、作者、RSS 简介都没有命中时，只对少量小文件做元数据识别。
          // 这样可以搜到 TXT/EPUB 内部写的书名、作者和简介，同时避免把整个
          // 网盘的大文件都拉一遍。
          if (!parseSettings.enabled || walk.files.isEmpty) return;
          final candidates = _probeCandidates(walk.files);
          for (var start = 0; start < candidates.length; start += 3) {
            final batch = candidates.skip(start).take(3);
            final probed = await Future.wait<Novel?>(
              batch.map((entry) async {
                try {
                  return await CloudDocumentService.instance
                      .enrich(_novelFor(entry, config), cloudOnly: true)
                      .timeout(_probeBudget);
                } catch (_) {
                  return null;
                }
              }),
            );
            for (final novel in probed.whereType<Novel>()) {
              if (_matches(value, novel) &&
                  !results.any((existing) => existing.id == novel.id)) {
                results.add(novel);
              }
            }
            if (results.length >= _maxResults) return;
          }
          // 正文兜底：只对最小的几个文本文件解析正文，避免为了搜索把整个
          // 网盘都下载下来。搜“妹妹”这类只出现在正文里的词也能命中。
          final textCandidates = candidates
              .where(
                (entry) =>
                    entry.size > 0 &&
                    entry.size <= 2 * 1024 * 1024 &&
                    RegExp(
                      r'\.(?:txt|md|markdown|html?|xhtml)$',
                      caseSensitive: false,
                    ).hasMatch(entry.name),
              )
              .take(4);
          for (final entry in textCandidates) {
            if (results.length >= _maxResults) return;
            final novel = _novelFor(entry, config);
            if (results.any((existing) => existing.id == novel.id)) continue;
            if (await CloudDocumentService.instance.containsText(
              novel,
              value,
            )) {
              results.add(novel);
            }
          }
        } catch (failure) {
          // 单个来源超时、未登录或格式不支持不影响其他来源，但要记录原因。
          failures.add('${config.label}：${cloudFailureMessage(failure)}');
        } finally {
          client?.close();
        }
      }),
    );
    lastFailure = failures.isEmpty ? null : failures.take(2).join('；');
    final cached = List<Novel>.unmodifiable(results);
    _cache = cached;
    _cacheQuery = value;
    _cacheScope = scope;
    _cacheTarget = cacheKey;
    _cacheAt = DateTime.now();
    return cached;
  }

  Novel _novelFor(CloudBookEntry entry, CloudSourceConfig config) =>
      CloudDocumentService.instance.cloudBook(entry, config);

  Iterable<CloudBookEntry> _probeCandidates(List<CloudBookEntry> files) {
    final small = files.where(
      (entry) =>
          entry.isBook &&
          entry.size > 0 &&
          entry.size <= _maxProbeBytes &&
          !entry.folder,
    );
    final ordered = small.toList()
      ..sort((a, b) {
        final priority = _probePriority(a.name) - _probePriority(b.name);
        return priority != 0 ? priority : a.size.compareTo(b.size);
      });
    return ordered.take(_maxProbeFiles);
  }

  int _probePriority(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.xhtml')) {
      return 0;
    }
    if (lower.endsWith('.epub') ||
        lower.endsWith('.fb2') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.odt')) {
      return 1;
    }
    return 2;
  }

  bool _matches(String query, Novel novel) => BookSearch(query).matches(
    title: novel.title,
    author: novel.author,
    tags: novel.genre,
    summary: novel.summary,
    id: '${novel.remoteEntryId ?? novel.id}',
  );

  Future<_CloudSearchWalk> _searchClient(
    CloudBookClient client,
    String query,
  ) async {
    final pattern = BookSearch(query);
    if (client is RssBookClient) {
      final listing = await client.search(query);
      final matches = <String, CloudBookEntry>{};
      for (final entry in listing.entries) {
        if (pattern.matches(
          title: entry.name,
          author: entry.author,
          tags: '',
          summary: entry.summary,
          id: entry.id,
        )) {
          matches[entry.id] = entry;
        }
      }
      return _CloudSearchWalk(
        matches: matches.values.toList(),
        files: const [],
      );
    }
    final matches = <String, CloudBookEntry>{};
    final files = <String, CloudBookEntry>{};
    final pending = <String>[client.root];
    final matchedFolders = <String>{};
    final visited = <String>{};
    var folders = 0;
    // OpenList/NAS 的书常按文件夹分组。除了匹配文件名，也要匹配文件夹名，
    // 命中文件夹后把里面的书都算作结果；否则“妹妹”这种目录名明明存在，
    // 却因为里面的文件名不含关键词而搜不到。
    while (pending.isNotEmpty && folders < 500 && files.length < 3000) {
      final folder = pending.removeAt(0);
      if (!visited.add(folder)) continue;
      folders++;
      final includeFolder = matchedFolders.contains(folder);
      final listing = await client.list(folder);
      for (final entry in listing.entries) {
        if (entry.folder) {
          pending.add(entry.id);
          if (pattern.matches(
            title: entry.name,
            author: entry.author,
            tags: '',
            summary: entry.summary,
            id: entry.id,
          )) {
            matchedFolders.add(entry.id);
          }
        } else if (entry.isBook) {
          files[entry.id] = entry;
          if (includeFolder ||
              pattern.matches(
                title: entry.name,
                author: entry.author,
                tags: '',
                summary: entry.summary,
                id: entry.id,
              )) {
            matches[entry.id] = entry;
          }
        }
      }
    }
    return _CloudSearchWalk(
      matches: matches.values.toList(),
      files: files.values.toList(),
    );
  }
}

class _CloudSearchWalk {
  const _CloudSearchWalk({required this.matches, required this.files});
  final List<CloudBookEntry> matches;
  final List<CloudBookEntry> files;
}
