import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'legacy_transport.dart';

/// Bounded cover cache. Source previews use local seeds only.
abstract final class LegacyCover {
  static final _cache = LegacyCoverCache(request: _request);
  static final _customUrls = <int, String>{};
  static String urlFor(int aid) =>
      'https://img.wenku8.com/image/${aid ~/ 1000}/$aid/${aid}s.jpg';

  static final bool _diskEnabled = !Platform.environment.containsKey(
    'FLUTTER_TEST',
  );
  static Future<Directory?>? _directoryFuture;

  static Future<Directory?> _directory() => _directoryFuture ??= () async {
    if (!_diskEnabled) return null;
    try {
      final root = await getApplicationCacheDirectory();
      final directory = Directory('${root.path}/legacy-covers');
      if (!await directory.exists()) await directory.create(recursive: true);
      return directory;
    } catch (_) {
      return null;
    }
  }();

  static Future<File?> _diskFile(String url) async {
    final directory = await _directory();
    if (directory == null) return null;
    final name = sha256.convert(utf8.encode(url)).toString();
    return File('${directory.path}/$name.img');
  }

  static Future<Uint8List?> _readDisk(String url) async {
    try {
      final file = await _diskFile(url);
      if (file == null || !await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) return null;
      return bytes.asUnmodifiableView();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDisk(String url, Uint8List bytes) async {
    try {
      final file = await _diskFile(url);
      if (file == null) return;
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // Cache writes are best-effort; the memory cache still works.
    }
  }

  static Future<Uint8List?> _remote(String url) async {
    final cached = await _readDisk(url);
    if (cached != null) return cached;
    try {
      final bytes = await LegacyTransport.illustration(
        url,
        cacheForViewing: false,
      );
      if (bytes.isNotEmpty) unawaited(_writeDisk(url, bytes));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _request(int aid) async {
    final custom = _customUrls[aid];
    if (custom != null && custom.isNotEmpty) {
      if (custom.startsWith('data:')) {
        try {
          final comma = custom.indexOf(',');
          if (comma < 0) return null;
          final header = custom.substring(0, comma),
              data = custom.substring(comma + 1);
          if (!header.contains(';base64')) return null;
          return base64Decode(data);
        } catch (_) {
          return null;
        }
      }
      return _remote(custom);
    }
    return _remote(urlFor(aid));
  }

  static void clear() {
    _cache.clear();
    _customUrls.clear();
    unawaited(_clearDisk());
  }

  static void forget(int aid) {
    final custom = _customUrls.remove(aid);
    _cache.forget(aid);
    unawaited(_deleteDisk(custom ?? urlFor(aid)));
  }

  static Future<void> _clearDisk() async {
    try {
      final directory = await _directory();
      if (directory == null) return;
      for (final entity in directory.listSync()) {
        if (entity is File) await entity.delete();
      }
    } catch (_) {}
  }

  static Future<void> _deleteDisk(String url) async {
    try {
      final file = await _diskFile(url);
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  static int get encodedBytes => _cache.encodedBytes;
  static Uint8List? peek(int aid, {String? url}) {
    if (url != null && url.isNotEmpty) _customUrls[aid] = url;
    return _cache.peek(aid);
  }

  static Future<Uint8List> bytes(int aid, {String? url}) {
    if (url != null && url.isNotEmpty) _customUrls[aid] = url;
    return _cache.load(aid);
  }

  /// Explicit local fixtures never query a remote cover endpoint.
  static void seedLocalBytes(int aid, Uint8List bytes) =>
      _cache.seed(aid, bytes);
}

class LegacyCoverCache {
  LegacyCoverCache({
    required this.request,
    this.maxBytes = 16 * 1024 * 1024,
    this.maxEntries = 256,
    this.retryDelay = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       assert(maxBytes > 0 && maxEntries > 0);
  final Future<Uint8List?> Function(int) request;
  final int maxBytes, maxEntries;
  final Duration retryDelay;
  final DateTime Function() now;
  final _entries = <int, _CoverEntry>{};
  final _pending = <int, Future<Uint8List>>{};
  final _failures = <int, (DateTime, Future<Uint8List>)>{};
  int _encodedBytes = 0;
  int get encodedBytes => _encodedBytes;
  int get cachedEntries => _entries.length;
  int get pendingRequests => _pending.length;
  int get cachedFailures => _failures.length;
  void clear() {
    _entries.clear();
    _pending.clear();
    _failures.clear();
    _encodedBytes = 0;
  }

  void forget(int aid) {
    final entry = _entries.remove(aid);
    if (entry != null) _encodedBytes -= entry.bytes.length;
    _pending.remove(aid);
    _failures.remove(aid);
  }

  _CoverEntry? _touch(int aid) {
    final entry = _entries.remove(aid);
    if (entry != null) _entries[aid] = entry;
    return entry;
  }

  Uint8List? peek(int aid) => _touch(aid)?.bytes;

  void seed(int aid, Uint8List bytes) {
    if (aid <= 0 || bytes.isEmpty) throw ArgumentError('Invalid local cover');
    final local = Uint8List.fromList(bytes).asUnmodifiableView();
    // A delayed older network response must not overwrite an explicit seed.
    _pending.remove(aid);
    _failures.remove(aid);
    _store(aid, _CoverEntry(local, Future.value(local)));
  }

  void _store(int aid, _CoverEntry entry) {
    final previous = _entries.remove(aid);
    if (previous != null) _encodedBytes -= previous.bytes.length;
    if (entry.bytes.length > maxBytes) return;
    _entries[aid] = entry;
    _encodedBytes += entry.bytes.length;
    while (_encodedBytes > maxBytes || _entries.length > maxEntries) {
      final removed = _entries.remove(_entries.keys.first)!;
      _encodedBytes -= removed.bytes.length;
    }
  }

  Future<Uint8List> load(int aid) {
    if (aid <= 0) return Future.error(ArgumentError('Invalid cover ID'));
    final entry = _touch(aid);
    if (entry != null) return entry.future;
    final failure = _failures[aid];
    if (failure != null && now().isBefore(failure.$1)) return failure.$2;
    _failures.remove(aid);
    final pending = _pending[aid];
    if (pending != null) return pending;
    final completer = Completer<Uint8List>();
    final future = completer.future;
    _pending[aid] = future;
    unawaited(() async {
      try {
        final image = await request(aid);
        if (image == null || image.isEmpty) throw const FormatException('封面为空');
        final bytes = image.asUnmodifiableView();
        if (identical(_pending[aid], future)) {
          _store(aid, _CoverEntry(bytes, future));
        }
        completer.complete(bytes);
      } catch (error, stack) {
        if (identical(_pending[aid], future)) {
          _failures[aid] = (now().add(retryDelay), future);
          // Failed IDs must not grow forever while browsing offline either.
          while (_failures.length > maxEntries) {
            _failures.remove(_failures.keys.first);
          }
        }
        completer.completeError(error, stack);
      } finally {
        if (identical(_pending[aid], future)) _pending.remove(aid);
      }
    }());
    return future;
  }
}

class _CoverEntry {
  const _CoverEntry(this.bytes, this.future);
  final Uint8List bytes;
  final Future<Uint8List> future;
}
