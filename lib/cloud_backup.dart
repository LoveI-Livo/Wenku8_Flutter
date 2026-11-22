import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'cloud_sources.dart';

/// Receipt returned after a cloud backup write. The path is deliberately shown
/// in the UI so the user can find the file in their own WebDAV or bucket.
class CloudBackupReceipt {
  const CloudBackupReceipt({
    required this.kind,
    required this.fileName,
    required this.remotePath,
    required this.bytes,
  });

  final CloudSourceKind kind;
  final String fileName, remotePath;
  final int bytes;
}

/// Writes the same `wenku8-local-backup` JSON produced by the local export
/// button into a connected WebDAV directory or S3 bucket. It never includes
/// credentials: the cloud config is read from the encrypted native vault.
class CloudBackupService {
  static const folder = 'wenku8-backups';
  static const _maxBytes = 4 * 1024 * 1024;
  static const _webDavUserAgent = 'Wenku8/0.7.0 WebDAV backup';

  Future<CloudBackupReceipt> backup(
    CloudSourceConfig config,
    String text, {
    DateTime? now,
  }) async {
    config.validate();
    if (utf8.encode(text).length > _maxBytes) {
      throw const CloudSourceFailure('备份超过 4 MiB，无法上传到云端');
    }
    return switch (config.kind) {
      CloudSourceKind.webdav => _webDavBackup(
        config,
        text,
        now ?? DateTime.now(),
      ),
      CloudSourceKind.s3 => _s3Backup(config, text),
      _ => throw const CloudSourceFailure(
        '这个网盘目前只支持阅读，不支持写入备份；请连接 WebDAV 或 S3',
      ),
    };
  }

  Future<String?> restoreLatest(CloudSourceConfig config) async {
    config.validate();
    return switch (config.kind) {
      CloudSourceKind.webdav => _webDavRestore(config),
      CloudSourceKind.s3 => _s3Restore(config),
      _ => throw const CloudSourceFailure(
        '这个网盘目前只支持阅读，不支持读取备份；请连接 WebDAV 或 S3',
      ),
    };
  }

  String _backupName(DateTime now) {
    String two(int value) => '$value'.padLeft(2, '0');
    return 'wenku8-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  Uri _webDavBase(CloudSourceConfig config) => config.endpoint.normalizePath();

  Uri _webDavFolder(CloudSourceConfig config) {
    final base = _webDavBase(config);
    final path =
        '${base.path.endsWith('/') ? base.path : '${base.path}/'}$folder/';
    return base.replace(path: path, query: null, fragment: null);
  }

  Uri _webDavFile(CloudSourceConfig config, String name) {
    final directory = _webDavFolder(config);
    return directory.replace(
      path: '${directory.path}$name',
      query: null,
      fragment: null,
    );
  }

  Map<String, String> _webDavHeaders(CloudSourceConfig config, Uri uri) => {
    'User-Agent': _webDavUserAgent,
    if (CloudHttp.sameOrigin(uri, _webDavBase(config)) &&
        (config.username.isNotEmpty || config.password.isNotEmpty))
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
  };

  Future<void> _discard(HttpClientResponse response) async {
    await response.listen((_) {}).cancel();
  }

  Future<CloudBackupReceipt> _webDavBackup(
    CloudSourceConfig config,
    String text,
    DateTime now,
  ) async {
    final http = CloudHttp();
    try {
      final folder = _webDavFolder(config);
      final mkcol = await http.request(
        'MKCOL',
        folder,
        headers: (uri) => _webDavHeaders(config, uri),
        allowHttp: config.allowHttp,
        allowedStatuses: const {405},
      );
      await _discard(mkcol);
      final name = _backupName(now);
      final file = _webDavFile(config, name);
      final put = await http.request(
        'PUT',
        file,
        headers: (uri) => {
          ..._webDavHeaders(config, uri),
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: utf8.encode(text),
        allowHttp: config.allowHttp,
      );
      await _discard(put);
      return CloudBackupReceipt(
        kind: config.kind,
        fileName: name,
        remotePath: '${folder.path}$name',
        bytes: utf8.encode(text).length,
      );
    } finally {
      http.close();
    }
  }

  Future<String?> _webDavRestore(CloudSourceConfig config) async {
    final http = CloudHttp();
    try {
      final folder = _webDavFolder(config);
      final listing = await http.request(
        'PROPFIND',
        folder,
        headers: (uri) => {
          ..._webDavHeaders(config, uri),
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: utf8.encode(
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
          '<d:displayname/><d:resourcetype/><d:getcontentlength/>'
          '</d:prop></d:propfind>',
        ),
        allowHttp: config.allowHttp,
        allowedStatuses: const {404},
      );
      if (listing.statusCode == 404) {
        await _discard(listing);
        return null;
      }
      final document = XmlDocument.parse(
        utf8.decode(await http.bytes(listing, limit: 64 * 1024)),
      );
      final candidates = <String>[];
      for (final node in document.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'response',
      )) {
        final href = node.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'href')
            .firstOrNull
            ?.innerText;
        if (href == null) continue;
        final candidate = folder.resolve(href);
        if (!CloudHttp.sameOrigin(candidate, folder) ||
            candidate.pathSegments.any((s) => s == '..' || s == '.')) {
          continue;
        }
        final name =
            candidate.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
        if (!name.startsWith('wenku8-backup-') || !name.endsWith('.json'))
          continue;
        candidates.add(name);
      }
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => b.compareTo(a));
      final latest = _webDavFile(config, candidates.first);
      final response = await http.request(
        'GET',
        latest,
        headers: (uri) => _webDavHeaders(config, uri),
        allowHttp: config.allowHttp,
        allowedStatuses: const {404},
      );
      if (response.statusCode == 404) {
        await _discard(response);
        return null;
      }
      final bytes = await http.bytes(response, limit: _maxBytes);
      return utf8.decode(bytes);
    } finally {
      http.close();
    }
  }

  Future<CloudBackupReceipt> _s3Backup(
    CloudSourceConfig config,
    String text,
  ) async {
    final http = CloudHttp();
    try {
      final bytes = utf8.encode(text);
      final key = '$folder/latest.json';
      final uri = s3UriForObject(config, key);
      final payload = sha256.convert(bytes).toString();
      final response = await http.request(
        'PUT',
        uri,
        headers: (u) => s3SignedHeaders(
          config,
          u,
          method: 'PUT',
          payloadHash: payload,
          extra: {'content-type': 'application/json; charset=utf-8'},
        ),
        body: bytes,
        allowHttp: config.allowHttp,
      );
      await _discard(response);
      return CloudBackupReceipt(
        kind: config.kind,
        fileName: 'latest.json',
        remotePath: '${config.prefix.isEmpty ? '' : '${config.prefix}/'}$key',
        bytes: bytes.length,
      );
    } finally {
      http.close();
    }
  }

  Future<String?> _s3Restore(CloudSourceConfig config) async {
    final http = CloudHttp();
    try {
      final uri = s3UriForObject(config, '$folder/latest.json');
      final response = await http.request(
        'GET',
        uri,
        headers: (u) => s3SignedHeaders(config, u),
        allowHttp: config.allowHttp,
        allowedStatuses: const {404},
      );
      if (response.statusCode == 404) {
        await _discard(response);
        return null;
      }
      return utf8.decode(await http.bytes(response, limit: _maxBytes));
    } finally {
      http.close();
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
