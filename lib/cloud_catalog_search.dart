import 'dart:async';
import 'dart:convert';

import 'catalog.dart';
import 'cloud_document_service.dart';
import 'cloud_sources.dart';

/// 全局搜索里的网盘 / 书源索引。
///
/// 搜索已登录的网盘账号目录和直链书源，不下载文件；
/// 命中的条目以远程书元数据返回，可直接加入书单并在线阅读。
class CloudCatalogSearch {
  CloudCatalogSearch._();
  static final instance = CloudCatalogSearch._();
  final CloudSourceSettings settings = CloudSourceSettings();
  DateTime? _loadedAt;
  Future<void>? _loading;

  Future<void> reload() async {
    _loadedAt = null;
    await _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 2)) {
      return;
    }
    _loading ??= settings.load().whenComplete(() {
      _loadedAt = DateTime.now();
      _loading = null;
    });
    await _loading;
  }

  Future<List<Novel>> search(String query) async {
    final value = query.trim();
    if (value.length < 2) return const [];
    await _ensureLoaded();
    final configs = settings.configs
        .where((config) => config.kind.isDirectLink || config.kind.isAccount)
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
        } else if (entry.isBook && entry.name.toLowerCase().contains(value)) {
          matches[entry.id] = entry;
        }
      }
    }
    return matches.values.toList();
  }
}
