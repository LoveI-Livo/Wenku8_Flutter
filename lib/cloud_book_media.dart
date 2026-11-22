import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Cover cache for books that are read directly from a cloud drive.
///
/// Only the cover thumbnail is cached, never the book file. The cache lets the
/// shelf keep showing a cover after restart without downloading the whole book.
abstract final class CloudBookMedia {
  static const scheme = 'wenku-cloud-cover:';
  static const mediaScheme = 'wenku-cloud-media:';
  static const _maxBytes = 4 * 1024 * 1024;
  static final _memory = <int, Uint8List>{};
  static final _mediaMemory = <String, Uint8List>{};

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
    final file = await _mediaFile(url!);
    if (!await file.exists()) throw const FormatException('网盘图片缓存不存在');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxBytes) {
      throw const FormatException('网盘图片缓存无效');
    }
    final value = bytes.asUnmodifiableView();
    _mediaMemory[url] = value;
    return value;
  }

  static Future<String> saveMedia(
    int bookId,
    String key,
    Uint8List bytes,
  ) async {
    if (bookId <= 0 || key.isEmpty || bytes.isEmpty) {
      throw const FormatException('网盘图片为空');
    }
    if (bytes.length > _maxBytes) {
      throw const FormatException('网盘单张图片超过 4 MiB，已忽略');
    }
    final url = mediaMarker(bookId, key);
    final value = Uint8List.fromList(bytes).asUnmodifiableView();
    _mediaMemory[url] = value;
    final file = await _mediaFile(url);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(value, flush: true);
    await temporary.rename(file.path);
    return url;
  }

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
      '${(await getApplicationCacheDirectory()).path}/cloud-book-media-v1/$book',
    );
    return File('${directory.path}/$key.img');
  }

  static Future<File> _file(int id) async {
    final directory = Directory(
      '${(await getApplicationCacheDirectory()).path}/cloud-book-covers-v1',
    );
    return File('${directory.path}/$id.img');
  }
}
