import 'dart:io';
import 'dart:typed_data';

/// Image-provider boundary shared by online covers and remote illustrations.
abstract final class LegacyTransport {
  /// Covers and illustrations share one keep-alive client. Creating a client
  /// per image used to open dozens of TLS connections on the home feed.
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 20)
    ..maxConnectionsPerHost = 12;
  static Future<Uint8List> Function(String) illustrationReader = _download;
  static Future<void> setUpdatePriority(bool enabled) async {}
  static Future<Uint8List> illustration(
    String url, {
    bool cacheForViewing = true,
  }) => illustrationReader(url);
  static Future<void> clearIllustrations() async {}

  static Future<Uint8List> _download(String url) async {
    final request = await _client.getUrl(Uri.parse(url));
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('图片请求失败（${response.statusCode}）');
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('图片为空或过大');
    }
    return Uint8List.fromList(bytes);
  }
}
