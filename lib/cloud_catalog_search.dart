import 'dart:async';
import 'dart:convert';

import 'catalog.dart';
import 'cloud_document_service.dart';
import 'cloud_sources.dart';

enum CloudSearchScope { all, netDisks, sources }

/// 全局搜索里的网盘 / 书源索引。
///
/// 搜索已登录的网盘账号目录和直链书源，不下载文件；
/// 命中的条目以远程书元数据返回，可直接加入书单并在线阅读。
class CloudCatalogSearch {
  CloudCatalogSearch._();
  static final instance = CloudCatalogSearch._();
  final CloudSourceSettings settings = CloudSourceSettings();

  /// 每次搜索都重新读取当前已连接来源，新添加的网盘会自动进入搜索，
  /// 不需要重启 App，也不依赖固定列表。
  Future<void> reload() => settings.load();

  Future<List<Novel>> search(
    String query, {
    CloudSearchScope scope = CloudSearchScope.all,
  }) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    await settings.load();
    final configs = settings.configs
        .where(
          (config) => switch (scope) {
            CloudSearchScope.all =>
              config.kind.isDirectLink || config.kind.isAccount,
            CloudSearchScope.netDisks => config.kind != CloudSourceKind.rss,
            CloudSearchScope.sources => config.kind == CloudSourceKind.rss,
          },
        )
        .toList();
    if (configs.isEmpty) return const [];
    final results = <Novel>[];
    await Future.wait(
      configs.map((config) async {
        CloudBookClient? client;
        try {
          client = CloudBookClient(config);
          final matches = await _searchClient(
            client,
            value,
          ).timeout(const Duration(seconds: 10));
          for (final entry in matches.take(40)) {
            // Account providers resolve the real download address only when
            // the book is opened. Resolving every search hit here would send
            // hundreds of requests and make full-disk search unusable.
            final lazy =
                config.kind == CloudSourceKind.quark ||
                config.kind == CloudSourceKind.lanzou;
            final url = lazy
                ? Uri(
                    scheme: 'cloud',
                    host: config.kind.name,
                    pathSegments: [entry.id],
                  ).toString()
                : await client.directLink(entry);
            if (url == null || url.isEmpty) continue;
            results.add(
              CloudDocumentService.instance.metadata(
                entry.name,
                url,
                author: entry.author.isEmpty
                    ? '${config.kind.label} · 全盘搜索'
                    : entry.author,
                cookie: config.cookie,
                authorization: config.username.trim().isEmpty
                    ? null
                    : 'Basic ' +
                          base64Encode(
                            utf8.encode(
                              '${config.username.trim()}:${config.password}',
                            ),
                          ),
                sourceLabel: config.kind.label,
                remoteEntryId: entry.id,
                remoteKind: config.kind.name,
              ),
            );
          }
        } catch (_) {
          // 单个来源超时或未登录不影响其他来源。
        } finally {
          client?.close();
        }
      }),
    );
    return results;
  }

  Future<List<CloudBookEntry>> _searchClient(
    CloudBookClient client,
    String query,
  ) async {
    final value = query.toLowerCase();
    final matches = <String, CloudBookEntry>{};
    final pending = <String>[client.root];
    final visited = <String>{};
    var folders = 0;
    while (pending.isNotEmpty && folders < 60 && matches.length < 100) {
      final folder = pending.removeAt(0);
      if (!visited.add(folder)) continue;
      folders++;
      final listing = await client.list(folder);
      for (final entry in listing.entries) {
        if (entry.folder) {
          pending.add(entry.id);
        } else if (entry.isBook &&
            (entry.name.toLowerCase().contains(value) ||
                entry.author.toLowerCase().contains(value) ||
                entry.id.toLowerCase().contains(value))) {
          matches[entry.id] = entry;
        }
      }
    }
    return matches.values.toList();
  }
}
