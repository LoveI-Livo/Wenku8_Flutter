import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cover cache for books that are read directly from a cloud drive.
///
/// Only the cover thumbnail is cached, never the book file. The cache lets the
/// shelf keep showing a cover after restart without downloading the whole book.
abstract final class CloudBookMedia {
  static const scheme = 'wenku-cloud-cover:';
  static const mediaScheme = 'wenku-cloud-media:';
  static const _maxBytes = 4 * 1024 * 1024;
  static const _coverDirectoryName = 'cloud-book-covers-v1';
  static const _mediaDirectoryName = 'cloud-book-media-v1';
  static const _maxMemoryBytes = 48 * 1024 * 1024;
  static final _memory = <int, Uint8List>{};
  static final _mediaMemory = <String, Uint8List>{};

  static int get memoryBytes {
    var total = 0;
    for (final bytes in _memory.values) {
      total += bytes.length;
    }
    for (final bytes in _mediaMemory.values) {
      total += bytes.length;
    }
    return total;
  }

  /// 网盘书产生的封面与正文插图缓存。原书文件不会写入这里。
  /// 旧版会把整本书的插图写进缓存目录，一本插图多的 EPUB 可能上百 MB。
  /// 新版只在内存里保留缩略图，启动时清理一次旧磁盘插图。
  static Future<void> pruneLegacyDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('cloud_media_disk_migrated_v1') == true) return;
      final directory = await mediaDirectory();
      if (await directory.exists()) await directory.delete(recursive: true);
      await prefs.setBool('cloud_media_disk_migrated_v1', true);
    } catch (_) {
      // 缓存目录被占用时下次启动再清理。
    }
  }

  static void _trimMemory() {
    while (_mediaMemory.length > 1 &&
        _mediaMemory.values.fold<int>(0, (sum, item) => sum + item.length) >
            _maxMemoryBytes) {
      _mediaMemory.remove(_mediaMemory.keys.first);
    }
  }

  static Future<Directory> cacheDirectory() async => Directory(
    '${(await getApplicationCacheDirectory()).path}/$_coverDirectoryName',
  );

  static Future<Directory> mediaDirectory() async => Directory(
    '${(await getApplicationCacheDirectory()).path}/$_mediaDirectoryName',
  );

  static Future<int> diskBytes() async {
    var total = 0;
    for (final directory in [await cacheDirectory(), await mediaDirectory()]) {
      try {
        if (!await directory.exists()) continue;
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) total += await entity.length();
        }
      } catch (_) {
        // 单个缓存目录不可读时跳过。
      }
    }
    return total;
  }

  /// 只释放运行期图片内存，保留磁盘缓存。
  static void clearMemory() {
    _memory.clear();
    _mediaMemory.clear();
  }

  /// 释放内存并删除全部网盘封面/插图缓存，不涉及网盘原书。
  static Future<void> clear() async {
    clearMemory();
    for (final directory in [await cacheDirectory(), await mediaDirectory()]) {
      try {
        if (await directory.exists()) await directory.delete(recursive: true);
      } catch (_) {
        // 被占用的缓存保留，下次清理再尝试。
      }
    }
  }

  static bool handles(String? url) => url?.startsWith(scheme) == true;

  static String marker(int id) => '$scheme$id';

  static int? idOf(String? url) {
    if (!handles(url)) return null;
    return int.tryParse(url!.substring(scheme.length));
  }

  static Uint8List? peek(String? url) {
    final id = idOf(url);
    if (id == null) return null;
    final bytes = _memory[id];
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  static Future<Uint8List> loadCover(String url) async {
    final id = idOf(url);
    if (id == null) throw const FormatException('网盘封面地址无效');
    final memory = _memory[id];
    if (memory != null && memory.isNotEmpty) return memory;
    final file = await _file(id);
    if (!await file.exists()) throw const FormatException('网盘封面缓存不存在');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxBytes) {
      throw const FormatException('网盘封面缓存无效');
    }
    final value = bytes.asUnmodifiableView();
    _memory[id] = value;
    return value;
  }

  static Future<void> saveCover(int id, Uint8List bytes) async {
    if (id <= 0 || bytes.isEmpty) return;
    if (bytes.length > _maxBytes) {
      throw const FormatException('网盘封面超过 4 MiB，已忽略');
    }
    final value = Uint8List.fromList(bytes).asUnmodifiableView();
    _memory[id] = value;
    final file = await _file(id);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(value, flush: true);
    await temporary.rename(file.path);
  }

  static bool handlesMedia(String? url) => url?.startsWith(mediaScheme) == true;

  static String mediaMarker(int bookId, String key) =>
      '$mediaScheme$bookId/$key';

  static Uint8List? peekMedia(String? url) {
    if (!handlesMedia(url)) return null;
    final bytes = _mediaMemory[url!];
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  static Future<Uint8List> loadMedia(String url) async {
    if (!handlesMedia(url)) throw const FormatException('网盘图片地址无效');
    final memory = _mediaMemory[url];
    if (memory != null && memory.isNotEmpty) return memory;
    final file = await _mediaFile(url);
    if (!await file.exists()) throw const FormatException('网盘图片缓存不存在');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxBytes) {
      throw const FormatException('网盘图片缓存无效');
    }
    final value = bytes.asUnmodifiableView();
    _mediaMemory[url] = value;
    return value;
  }

  /// 插图只放当前运行期内存，不写磁盘。打开在线书不会再让缓存暴涨；
  /// 重新打开时会重新解析原书，最多短暂占用当前阅读所需的图片内存。
  static String cacheMedia(int bookId, String key, Uint8List bytes) {
    if (bookId <= 0 || key.isEmpty || bytes.isEmpty) return '';
    if (bytes.length > _maxBytes) return '';
    final url = mediaMarker(bookId, key);
    _mediaMemory[url] = Uint8List.fromList(bytes).asUnmodifiableView();
    _trimMemory();
    return url;
  }

  /// 兼容旧调用；新代码使用 [cacheMedia]，不再写磁盘。
  static Future<String> saveMedia(
    int bookId,
    String key,
    Uint8List bytes,
  ) async => cacheMedia(bookId, key, bytes);

  static Future<File> _mediaFile(String url) async {
    final raw = url.substring(mediaScheme.length);
    final slash = raw.indexOf('/');
    if (slash <= 0 || slash >= raw.length - 1) {
      throw const FormatException('网盘图片地址无效');
    }
    final book = int.tryParse(raw.substring(0, slash));
    final key = raw.substring(slash + 1);
    if (book == null || book <= 0) throw const FormatException('网盘图片地址无效');
    final directory = Directory(
      '${(await getApplicationCacheDirectory()).path}/$_mediaDirectoryName/$book',
    );
    return File('${directory.path}/$key.img');
  }

  static Future<File> _file(int id) async {
    final directory = Directory(
      '${(await getApplicationCacheDirectory()).path}/$_coverDirectoryName',
    );
    return File('${directory.path}/$id.img');
  }
}
