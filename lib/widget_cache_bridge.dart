import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Native widget artwork lives outside Flutter's temp directory, especially on
/// iOS (App Group) and Android (`filesDir/reading-cards`).
class WidgetCacheBridge {
  static const _channel = MethodChannel('org.mewx.wenku8/reading_widgets');

  static Future<int> nativeBytes() async {
    try {
      return await _channel.invokeMethod<int>('cacheUsage') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<void> clearNative() async {
    try {
      await _channel.invokeMethod<void>('clearWidgetCache');
    } on MissingPluginException {
      // Desktop/test hosts have no home-screen extension.
    } on PlatformException {
      // A failed native clear leaves the files for the next attempt.
    }
  }

  /// Flutter-side copies that some hosts keep under Application Support.
  static Future<Directory?> flutterDirectory() async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}/reading-cards');
      return directory.existsSync() ? directory : null;
    } catch (_) {
      return null;
    }
  }

  static Future<int> flutterBytes() async {
    final directory = await flutterDirectory();
    if (directory == null) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<void> clearFlutter() async {
    final directory = await flutterDirectory();
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }
}
