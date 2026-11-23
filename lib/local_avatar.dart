import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 本地头像独立于文库登录状态，保存在应用支持目录而不是缓存目录，
/// 因此退出账号或清理缓存都不会丢。
final class LocalAvatar extends ValueNotifier<Uint8List?> {
  LocalAvatar._() : super(null);
  static final instance = LocalAvatar._();
  static bool _loaded = false;

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/profile/avatar.bin');
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) value = bytes;
      }
    } catch (_) {
      // 首次启动或平台不支持支持目录时保持默认图标。
    }
  }

  Future<void> save(Uint8List bytes) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    value = bytes;
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
    value = null;
  }
}
