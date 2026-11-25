import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sources.dart';

/// App 内置的 Legado 书源包。用户上传的番茄源在第一位，其余来自公开
/// GitHub 书源合集，统一放进独立的 `rss-builtin` 连接，不覆盖用户自己
/// 添加的书源。只执行一次，之后用户删除/停用内置源不会被重新塞回来。
abstract final class BuiltInBookSources {
  BuiltInBookSources._();

  static const asset = 'assets/book_sources/legado-pack.json';
  static const connectionId = 'rss-builtin';
  static const _seededFlag = 'builtinBookSourcesV1';
  static bool _done = false;
  static Future<void>? _installing;

  static Future<void> ensure(CloudSourceSettings settings) {
    if (_done) return Future.value();
    final running = _installing;
    if (running != null) return running;
    late final Future<void> future;
    future = _install(settings).whenComplete(() {
      if (identical(_installing, future)) _installing = null;
    });
    _installing = future;
    return future;
  }

  static Future<void> _install(CloudSourceSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_seededFlag) == true) {
        _done = true;
        return;
      }
      final raw = await rootBundle.loadString(asset);
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      final builtIns = <CloudBookSource>[];
      for (final value in decoded) {
        try {
          builtIns.add(CloudBookSource.fromRecord(value));
        } catch (_) {
          // 单个坏记录不拖垮整个内置包。
        }
      }
      if (builtIns.isEmpty) return;
      await settings.ensureLoaded();
      final existing = settings.byId(connectionId);
      final merged = <CloudBookSource>[
        ...?existing?.effectiveSources,
        ...builtIns,
      ];
      final seen = <String>{};
      final unique = <CloudBookSource>[];
      for (final source in merged) {
        final identity = source.isLegado ? source.key : source.url;
        if (seen.add(identity)) unique.add(source);
        if (unique.length >= maxBookSources) break;
      }
      final config =
          existing ??
          const CloudSourceConfig(
            kind: CloudSourceKind.rss,
            connectionId: connectionId,
            allowHttp: true,
          );
      await settings.save(
        CloudSourceKind.rss,
        config.withAllowHttp(true).withSources(unique),
      );
      await prefs.setBool(_seededFlag, true);
      _done = true;
    } catch (_) {
      // 内置书源失败不能影响启动和用户已有书源；下次启动会重试。
      _done = false;
    }
  }
}
