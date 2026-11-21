import 'dart:io';

import 'package:flutter/services.dart';

/// One file produced by [PortableBookPreparer.prepare].
///
/// A prepared document either carries a readable [path] or a reader facing
/// [error]; callers never receive both and never receive neither.
typedef PreparedBookDocument = ({String name, String? path, String? error});

/// Turns a picked document into files the importer can read.
///
/// The containers Flutter cannot open itself are unpacked by the host through
/// [extractKindle] and [extractPdf]; every other format is handed to [convert].
/// All files this class creates stay inside [directory], so [releasePaths] can
/// never delete a book the reader picked from disk.
class PortableBookPreparer {
  PortableBookPreparer({
    required this.directory,
    required this.textCodecToken,
    required this.decodeNames,
    required this.convert,
    this.extractKindle,
    this.extractPdf,
  });

  /// Scratch directory; [clearPreviousRuns] empties it between launches.
  final Directory directory;

  /// Token the platform channel needs when names are decoded away from the
  /// root isolate. Held for the host callbacks that use it.
  final RootIsolateToken textCodecToken;

  /// Decodes host supplied file names, for example GBK members of a ZIP.
  final Future<List<String>> Function(List<String> names) decodeNames;

  /// Native conversion for every container this file cannot open itself.
  final Future<List<PreparedBookDocument>> Function(String name, String path)
  convert;

  /// Unpacks a Kindle container into `output`; the file is verified afterwards.
  final Future<int> Function(String source, String output)? extractKindle;

  /// Unpacks a PDF into `output` (iOS and Harmony hosts only).
  final Future<void> Function(String name, String source, String output)?
  extractPdf;

  static const _readable = {'txt', 'epub'};
  static const _kindle = {'mobi', 'azw', 'azw3', 'prc'};
  static const _pdf = {'pdf'};

  int _sequence = 0;

  /// Deletes the scratch directory of an earlier run and recreates it empty.
  ///
  /// Best effort: a directory the host keeps locked is reused, because losing
  /// yesterday's cache is never a reason to refuse today's import.
  static Future<void> clearPreviousRuns(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Stale files are harmless; [prepare] never reads them back.
    }
    try {
      await directory.create(recursive: true);
    } catch (_) {
      // The first write reports the real problem with a readable message.
    }
  }

  /// Converts [name] at [path] into one or more readable documents.
  ///
  /// Never throws: a document that cannot be converted comes back as an entry
  /// with an [PreparedBookDocument.error] instead.
  Future<List<PreparedBookDocument>> prepare(String name, String path) async {
    final label = name.trim().isEmpty ? _fileName(path) : name;
    try {
      if (!await File(path).exists()) {
        return [(name: label, path: null, error: '找不到这本书的文件：$label')];
      }
      final extension = _extension(label.isEmpty ? path : label);
      if (_readable.contains(extension)) {
        return [(name: label, path: path, error: null)];
      }
      if (_kindle.contains(extension)) {
        return await _prepareKindle(label, path);
      }
      if (_pdf.contains(extension)) {
        return await _preparePdf(label, path);
      }
      final converted = await convert(label, path);
      if (converted.isNotEmpty) return converted;
      return [(name: label, path: null, error: '无法解析这本书：$label')];
    } catch (_) {
      return [(name: label, path: null, error: '无法解析这本书：$label')];
    }
  }

  /// Decodes [names] with the host codec, falling back to the raw names.
  Future<List<String>> decodeFileNames(List<String> names) async {
    if (names.isEmpty) return const [];
    try {
      return await decodeNames(names);
    } catch (_) {
      return names;
    }
  }

  /// Deletes only files this preparer created; originals are never touched.
  Future<void> releasePaths(Iterable<String> paths) async {
    final root = _root();
    for (final path in paths.toSet()) {
      final resolved = _normalize(path);
      if (resolved.length <= root.length || !resolved.startsWith(root)) {
        continue;
      }
      await _discard(resolved);
    }
  }

  Future<List<PreparedBookDocument>> _prepareKindle(
    String label,
    String path,
  ) async {
    final extract = extractKindle;
    if (extract == null) {
      return [(name: label, path: null, error: '当前设备无法转换 Kindle 格式：$label')];
    }
    final output = await _reserve();
    await extract(path, output);
    return _collect(label, output, 'Kindle');
  }

  Future<List<PreparedBookDocument>> _preparePdf(
    String label,
    String path,
  ) async {
    final extract = extractPdf;
    if (extract == null) {
      return [(name: label, path: null, error: '当前设备无法转换 PDF 格式：$label')];
    }
    final output = await _reserve();
    await extract(label, path, output);
    return _collect(label, output, 'PDF');
  }

  /// Accepts [output] only when the host actually wrote a non-empty file.
  Future<List<PreparedBookDocument>> _collect(
    String label,
    String output,
    String format,
  ) async {
    final produced = File(output);
    final size = await produced.exists() ? await produced.length() : 0;
    if (size > 0) {
      return [(name: _epubName(label), path: output, error: null)];
    }
    await _discard(output);
    return [(name: label, path: null, error: '无法从 $format 文件取出可读内容：$label')];
  }

  /// Reserves an unused path inside [directory] for a host produced EPUB.
  Future<String> _reserve() async {
    await directory.create(recursive: true);
    _sequence += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${_root()}$stamp-$_sequence.$_epubExtension';
  }

  Future<void> _discard(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Disposable cache: a locked file is retried on the next launch.
    }
  }

  /// [directory] as a slash terminated prefix every owned file shares.
  String _root() {
    final path = _normalize(directory.path);
    return path.endsWith('/') ? path : '$path/';
  }
}

String _normalize(String path) => path.replaceAll(r'\', '/');

String _fileName(String path) {
  final name = _normalize(path);
  final slash = name.lastIndexOf('/');
  return slash < 0 ? name : name.substring(slash + 1);
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

String _epubName(String label) {
  final dot = label.lastIndexOf('.');
  final base = dot > 0 ? label.substring(0, dot) : label;
  return '$base.$_epubExtension';
}

const _epubExtension = 'epub';
