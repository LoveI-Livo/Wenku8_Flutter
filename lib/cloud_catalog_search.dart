import 'dart:async';

import 'package:flutter/foundation.dart';

import 'book_search.dart';
import 'builtin_book_sources.dart';
import 'catalog.dart';
import 'cloud_document_service.dart';
import 'cloud_parse_service.dart';
import 'cloud_sources.dart';

enum CloudSearchScope { all, netDisks, sources }

/// 搜索页顶部的确定性进度。total 按“单个书源/单个网盘连接”计算，
/// 500 个书源 + 再导入 500 个时进度是 1..1000，而不是 1..2。
class CloudSearchProgress extends ChangeNotifier {
  int done = 0, total = 0;
  bool get active => total > 0;

  void begin(int value) {
    done = 0;
    total = value < 0 ? 0 : value;
    notifyListeners();
  }

  void advance() {
    if (done >= total) return;
    done++;
    // 1000 个书源逐个 notify 会让进度条和列表一起重建上千次。
    // 每 1% 或最后一项刷新一次即可。
    final step = total > 20 ? (total / 100).ceil() : 1;
    if (done != total && done % step != 0) return;
    notifyListeners();
  }

  void close() {
    if (total == 0 && done == 0) return;
    total = 0;
    done = 0;
    notifyListeners();
  }
}

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

  static const _walkBudget = Duration(seconds: 9);
  static const _indexBudget = Duration(seconds: 7);
  static const _folderBudget = Duration(seconds: 5);
  static const _probeBudget = Duration(seconds: 5);
  static const _folderWorkers = 4;
  static const _indexLifetime = Duration(minutes: 10);
  static const _maxProbeBytes = 4 * 1024 * 1024;
  static const _maxProbeFiles = 6;
  static const _maxResults = 500;
  static const _cacheLifetime = Duration(minutes: 1);
  final Map<String, _CloudSearchIndex> _indexes = {};
  String? _cacheQuery;
  CloudSearchScope? _cacheScope;
  String? _cacheTarget;
  DateTime? _cacheAt;
  List<Novel>? _cache;

  /// 最近一次搜索中被跳过的来源错误，页面可用来提示“不是没书，而是源没连上”。
  String? lastFailure;

  /// 当前搜索进度；页面监听它绘制 1..N 的进度条。
  final progress = CloudSearchProgress();

  /// 每次搜索都重新读取当前已连接来源，新添加的网盘会自动进入搜索，
  /// 不需要重启 App，也不依赖固定列表。
  Future<void> reload() async {
    _cache = null;
    _cacheAt = null;
    _indexes.clear();
    await settings.load();
  }

  /// 当前范围可用于搜索的来源。网盘按连接区分，书源按单个地址区分。
  Future<List<CloudSearchTarget>> targets(CloudSearchScope scope) async {
    await BuiltInBookSources.ensure(settings);
    await settings.ensureLoaded();
    final result = <CloudSearchTarget>[];
    for (final config in settings.activeConfigs) {
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
              key: 'rss:${source.key}',
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

  final Map<String, Future<List<Novel>>> _activeSearches = {};
  final StreamController<CloudPartialResult> _partialController =
      StreamController<CloudPartialResult>.broadcast();

  /// 单个书源结束就推送一次，页面可以先展示已返回的结果。
  Stream<CloudPartialResult> get partialResults => _partialController.stream;

  void _emitPartial(String query, List<Novel> items) {
    if (items.isEmpty || _partialController.isClosed) return;
    _partialController.add(CloudPartialResult(query: query, items: items));
  }

  /// 同一批来源的并行搜索只真正跑一次。搜索页会按书名/作者/标签/ID
  /// 分四组同时查询，不能让它们各自把 276 个来源重扫一遍。
  Future<List<Novel>> search(
    String query, {
    CloudSearchScope scope = CloudSearchScope.all,
    String? sourceKey,
    Set<String>? sourceKeys,
    bool refresh = false,
  }) {
    final value = query.trim();
    if (value.isEmpty) return Future.value(const []);
    final keys = sourceKeys ?? {if (sourceKey != null) sourceKey};
    final key = '$value|${scope.name}|${(keys.toList()..sort()).join('\n')}';
    if (!refresh) {
      final running = _activeSearches[key];
      if (running != null) return running;
    }
    final future = _searchOnce(
      value,
      scope: scope,
      sourceKey: sourceKey,
      sourceKeys: sourceKeys,
      refresh: refresh,
    );
    if (!refresh) {
      _activeSearches[key] = future;
      return future.whenComplete(() {
        if (identical(_activeSearches[key], future)) {
          _activeSearches.remove(key);
        }
      });
    }
    return future;
  }

  Future<List<Novel>> _searchOnce(
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
    await BuiltInBookSources.ensure(settings);
    await settings.ensureLoaded();
    lastFailure = null;
    final failures = <String>[];
    final configs = settings.activeConfigs
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
                                      'rss:${source.key}' == key,
                                )
                              : config.effectiveSources.any(
                                  (source) => 'rss:${source.key}' == key,
                                )),
                    )
                  : keys.contains(config.kind.name) ||
                        keys.contains(
                          '${config.kind.name}:${config.connectionId}',
                        )),
        )
        .toList();
    if (configs.isEmpty) {
      progress.close();
      return const [];
    }

    final sourcePlan = <CloudSourceConfig, List<CloudBookSource>>{};
    var total = 0;
    for (final config in configs) {
      if (config.kind == CloudSourceKind.rss) {
        final selected = config.effectiveSources
            .where((source) => keys.contains('rss:${source.key}'))
            .toList(growable: false);
        sourcePlan[config] = selected;
        total += selected.isEmpty
            ? config.effectiveSources.length
            : selected.length;
      } else {
        sourcePlan[config] = const [];
        total++;
      }
    }
    progress.begin(total);
    final parseSettings = CloudParseSettings.instance;
    await parseSettings.load();
    final results = <Novel>[];
    try {
      await Future.wait(
        configs.map((config) async {
          CloudBookClient? client;
          try {
            final selectedSources =
                sourcePlan[config] ?? const <CloudBookSource>[];
            final partial = <Novel>[];
            client = config.kind == CloudSourceKind.rss
                ? RssBookClient(
                    config,
                    sourceEntries: selectedSources.isEmpty
                        ? null
                        : selectedSources,
                    onSourceDone: progress.advance,
                    onSourceEntries: (entries) {
                      final novels = <Novel>[];
                      for (final entry in entries) {
                        if (novels.length >= _maxResults) break;
                        final novel = _novelFor(entry, config);
                        if (_matches(value, novel)) novels.add(novel);
                      }
                      for (final novel in novels) {
                        if (!results.any(
                          (existing) => existing.id == novel.id,
                        )) {
                          results.add(novel);
                        }
                      }
                      _emitPartial(value, novels);
                    },
                  )
                : CloudBookClient(config, settings: settings);
            final walk =
                await _searchClient(
                  client,
                  value,
                  config: config,
                  refresh: refresh,
                ).timeout(
                  client is RssBookClient
                      ? client.searchBudget + const Duration(seconds: 1)
                      : _walkBudget,
                );
            // 让进度条等到单源任务完成/超时，不因首批结果提前出现而收起。
            if (client is RssBookClient) {
              try {
                await client.sourcesDone.timeout(
                  client.searchBudget + const Duration(seconds: 1),
                );
              } catch (_) {
                // 超时由 client 内部的 8 秒计时器结束，不阻塞结果展示。
              }
            }

            if (walk.matches.isNotEmpty) {
              for (final entry in walk.matches) {
                if (results.length >= _maxResults) return;
                final novel = _novelFor(entry, config);
                if (!results.any((existing) => existing.id == novel.id)) {
                  results.add(novel);
                  if (client is! RssBookClient) partial.add(novel);
                }
              }
              return;
            }

            if (partial.isNotEmpty) _emitPartial(value, partial);
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
                .take(2);
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
            if (config.kind != CloudSourceKind.rss) progress.advance();
          }
        }),
      );
    } finally {
      progress.close();
    }
    // 已经在本机识别过的网盘书也参与搜索。在线目录偶尔超时、分页或
    // 站点改版时，书架里已有的书不能从搜索里消失。
    if (results.length < _maxResults) {
      for (final known in CloudDocumentService.instance.knownBooks) {
        final kind = known.remoteKind;
        // 网盘页不能把书源缓存书混进来，书源页也不能混入网盘书。
        final inScope = switch (scope) {
          CloudSearchScope.netDisks =>
            kind != null && kind != CloudSourceKind.rss.name,
          CloudSearchScope.sources => kind == CloudSourceKind.rss.name,
          CloudSearchScope.all => kind != null,
        };
        if (!inScope) continue;
        if (results.any((existing) => existing.id == known.id)) continue;
        if (_matches(value, known)) results.add(known);
        if (results.length >= _maxResults) break;
      }
    }
    lastFailure = failures.isEmpty ? null : failures.take(2).join('；');
    final cached = List<Novel>.unmodifiable(results);
    if (cached.isEmpty) return cached;
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
    String query, {
    required CloudSourceConfig config,
    required bool refresh,
  }) async {
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

    final indexKey =
        '${config.kind.name}|${config.connectionId}|${config.address}';
    final cached = _indexes[indexKey];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _indexLifetime) {
      return _matchIndex(cached, pattern);
    }

    final index = await _buildIndex(client);
    if (index.complete) _indexes[indexKey] = index;
    return _matchIndex(index, pattern);
  }

  Future<_CloudSearchIndex> _buildIndex(CloudBookClient client) async {
    final files = <String, CloudBookEntry>{};
    final folders = <String, CloudBookEntry>{};
    final entries = <String, CloudBookEntry>{};
    final children = <String, List<String>>{};
    final failures = <String>[];
    final queue = <String>[client.root];
    final queued = <String>{client.root};
    final visited = <String>{};
    final stopwatch = Stopwatch()..start();
    var folderCount = 0;

    while (queue.isNotEmpty &&
        folderCount < 400 &&
        files.length < 3000 &&
        stopwatch.elapsed < _indexBudget) {
      final batch = <String>[];
      while (queue.isNotEmpty &&
          batch.length < _folderWorkers &&
          folderCount + batch.length < 400) {
        final folder = queue.removeAt(0);
        if (visited.add(folder)) batch.add(folder);
      }
      if (batch.isEmpty) continue;
      final listings = await Future.wait(
        batch.map((folder) async {
          try {
            final listing = await client.list(folder).timeout(_folderBudget);
            return (folder: folder, listing: listing);
          } catch (error) {
            failures.add(cloudFailureMessage(error));
            return null;
          }
        }),
      );
      for (final item
          in listings
              .whereType<({String folder, CloudBookListing listing})>()) {
        folderCount++;
        final folder = item.folder;
        children.putIfAbsent(folder, () => <String>[]);
        for (final entry in item.listing.entries) {
          if (entries.containsKey(entry.id)) continue;
          entries[entry.id] = entry;
          children[folder]!.add(entry.id);
          if (entry.folder) {
            folders[entry.id] = entry;
            if (queued.add(entry.id)) queue.add(entry.id);
          } else if (entry.isBook) {
            files[entry.id] = entry;
          }
          if (files.length >= 3000) break;
        }
        if (files.length >= 3000) break;
      }
      // 每个批次主动让出一帧，避免长目录搜索把输入和滚动完全卡住。
      await Future<void>.delayed(Duration.zero);
    }
    if (files.isEmpty && folders.isEmpty && failures.isNotEmpty) {
      throw CloudSourceFailure(failures.first);
    }
    return _CloudSearchIndex(
      files: files.values.toList(growable: false),
      folders: folders.values.toList(growable: false),
      children: children,
      entries: entries,
      at: DateTime.now(),
      complete: queue.isEmpty && files.length < 3000,
    );
  }

  _CloudSearchWalk _matchIndex(_CloudSearchIndex index, BookSearch pattern) {
    final matches = <String, CloudBookEntry>{};
    final selectedFolders = <String>{};
    for (final folder in index.folders) {
      if (pattern.matches(
        title: folder.name,
        author: folder.author,
        tags: '',
        summary: folder.summary,
        id: folder.id,
      )) {
        selectedFolders.add(folder.id);
      }
    }
    final folderFiles = <String>{};
    void visit(String folder) {
      for (final id in index.children[folder] ?? const <String>[]) {
        final entry = index.entries[id];
        if (entry == null) continue;
        if (entry.folder) {
          visit(id);
        } else if (entry.isBook) {
          folderFiles.add(id);
        }
      }
    }

    for (final folder in selectedFolders) {
      visit(folder);
    }
    for (final entry in index.files) {
      if (folderFiles.contains(entry.id) ||
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
    return _CloudSearchWalk(
      matches: matches.values.toList(),
      files: index.files,
    );
  }
}

class _CloudSearchIndex {
  const _CloudSearchIndex({
    required this.files,
    required this.folders,
    required this.children,
    required this.entries,
    required this.at,
    required this.complete,
  });
  final List<CloudBookEntry> files;
  final List<CloudBookEntry> folders;
  final Map<String, List<String>> children;
  final Map<String, CloudBookEntry> entries;
  final DateTime at;
  final bool complete;
}

class CloudPartialResult {
  const CloudPartialResult({required this.query, required this.items});
  final String query;
  final List<Novel> items;
}

class _CloudSearchWalk {
  const _CloudSearchWalk({required this.matches, required this.files});
  final List<CloudBookEntry> matches;
  final List<CloudBookEntry> files;
}
