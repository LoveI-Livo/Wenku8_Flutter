import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cloud_sources.dart';

/// 书源/网盘搜索结果封面的轻量读取器。
///
/// 轻小说文库的封面走 `LegacyCover`，但书源封面经常在另一个域名，而且
/// 需要书源自己的 Cookie、Authorization 或 Referer。直接交给
/// `Image.network` 会因为缺少请求头变成 403，用户看到的就是一排无封面。
/// 这里用书源请求同一套 `CloudHttp` 取图，并在内存里按书 ID 缓存。
abstract final class CloudCoverMedia {
  static const _maxBytes = 4 * 1024 * 1024;
  static const _maxEntries = 96;
  static final _memory = <int, Uint8List>{};
  static final _urls = <int, String>{};
  static final _pending = <int, Future<Uint8List?>>{};
  static final _failedAt = <int, DateTime>{};
  static final _http = CloudHttp();

  static Uint8List? peek(int id, {String? url}) {
    if (url != null && url.isNotEmpty && _urls[id] != url) return null;
    final bytes = _memory[id];
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  static void forget(int id) {
    _memory.remove(id);
    _urls.remove(id);
    _pending.remove(id);
    _failedAt.remove(id);
  }

  static void clearMemory() {
    _memory.clear();
    _urls.clear();
    _pending.clear();
    _failedAt.clear();
  }

  /// [sourceUrl] 是书详情/章节页地址，用来判断 Cookie 是否同源，并作为
  /// Referer。封面在 CDN 域名时不会把登录 Cookie 发过去。
  static Future<Uint8List?> load(
    int id,
    String coverUrl, {
    String cookie = '',
    String authorization = '',
    String? sourceUrl,
  }) {
    final cached = peek(id, url: coverUrl);
    if (cached != null) return Future.value(cached);
    final failed = _failedAt[id];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(seconds: 30)) {
      return Future.value(null);
    }
    final pending = _pending[id];
    if (pending != null) return pending;
    final future = _guarded(id, coverUrl, cookie, authorization, sourceUrl);
    _pending[id] = future;
    return future.whenComplete(() => _pending.remove(id));
  }

  static Future<Uint8List?> _guarded(
    int id,
    String coverUrl,
    String cookie,
    String authorization,
    String? sourceUrl,
  ) async {
    try {
      final bytes = await _load(id, coverUrl, cookie, authorization, sourceUrl);
      if (bytes != null) _failedAt.remove(id);
      return bytes;
    } catch (_) {
      _failedAt[id] = DateTime.now();
      rethrow;
    }
  }

  static Future<Uint8List?> _load(
    int id,
    String coverUrl,
    String cookie,
    String authorization,
    String? sourceUrl,
  ) async {
    final raw = coverUrl.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('data:')) {
      final comma = raw.indexOf(',');
      if (comma < 0) return null;
      final bytes = base64Decode(raw.substring(comma + 1));
      return _remember(id, raw, bytes);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    var rawSource = Uri.tryParse((sourceUrl ?? '').trim());
    if (sourceUrl != null && sourceUrl.startsWith('legado://')) {
      final decoded = LegadoReader.decodePayload(sourceUrl);
      final book = decoded?['book']?.toString() ?? '';
      rawSource = Uri.tryParse(book);
    }
    final source = rawSource;
    final referer = source != null && source.hasScheme && source.host.isNotEmpty
        ? source.toString()
        : '${uri.scheme}://${uri.host}/';
    final allowHttp = uri.scheme.toLowerCase() == 'http';
    CloudHttp.validateUrl(uri, allowHttp: allowHttp);
    final response = await _http.request(
      'GET',
      uri,
      headers: (requested) => {
        'accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'user-agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'referer': referer,
        if (source != null &&
            CloudHttp.sameOrigin(requested, source) &&
            cookie.trim().isNotEmpty)
          'cookie': cookie.trim(),
        if (source != null &&
            CloudHttp.sameOrigin(requested, source) &&
            authorization.trim().isNotEmpty)
          'authorization': authorization.trim(),
      },
      redirects: true,
      allowHttp: allowHttp,
      redirectMessage: '封面地址发生跳转',
    );
    final bytes = await _http.bytes(response, limit: _maxBytes);
    return _remember(id, raw, bytes);
  }

  static Uint8List? _remember(int id, String url, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxBytes) return null;
    if (_memory.length >= _maxEntries && !_memory.containsKey(id)) {
      _memory.remove(_memory.keys.first);
      _urls.remove(_urls.keys.first);
    }
    final value = Uint8List.fromList(bytes).asUnmodifiableView();
    _memory[id] = value;
    _urls[id] = url;
    return value;
  }
}
