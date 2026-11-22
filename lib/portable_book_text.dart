import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:xml/xml.dart';

import 'book_import_limits.dart';

typedef PreparedTextDocument = ({String name, String? path, String? error});

/// Converts the readable document formats that the public build can parse
/// without a platform converter. Everything stays in memory or in the
/// disposable import cache; originals are never modified.
class PortableBookText {
  PortableBookText._();

  static const convertible = {
    'html',
    'htm',
    'xhtml',
    'md',
    'markdown',
    'fb2',
    'rtf',
    'docx',
    'odt',
    'zip',
    'mobi',
    'prc',
    'azw',
    'azw3',
  };

  static bool handles(String name) => convertible.contains(_extension(name));

  static Future<List<PreparedTextDocument>> prepare(
    String name,
    String path,
    Directory directory,
  ) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return [(name: name, path: null, error: '找不到这本书的文件：$name')];
      }
      final size = await file.length();
      if (size <= 0) return [(name: name, path: null, error: '文件为空：$name')];
      if (size > localBookByteLimit(name)) {
        return [(name: name, path: null, error: localBookSizeMessage(name))];
      }
      final bytes = await file.readAsBytes();
      final ext = _extension(name);
      if (ext == 'zip') return _prepareZip(name, bytes, directory);
      final text = extract(name, bytes);
      if (text == null || text.trim().isEmpty) {
        return [
          (name: name, path: null, error: '无法从 ${ext.toUpperCase()} 取出可读正文'),
        ];
      }
      return [_writeText(name, text, directory)];
    } catch (_) {
      return [(name: name, path: null, error: '无法解析这本书：$name')];
    }
  }

  /// Used by the cloud reader. Returns null when the file needs the EPUB/PDF
  /// parser instead of the text converter.
  static String? extract(String name, Uint8List bytes) {
    final ext = _extension(name);
    return switch (ext) {
      'txt' => decodeText(bytes),
      'html' || 'htm' || 'xhtml' => _htmlText(decodeText(bytes)),
      'md' || 'markdown' => _markdownText(decodeText(bytes)),
      'fb2' => _fb2Text(bytes),
      'rtf' => _rtfText(decodeText(bytes)),
      'docx' => _docxText(bytes),
      'odt' => _odtText(bytes),
      'zip' => _zipText(bytes),
      'mobi' || 'prc' || 'azw' || 'azw3' => _kindleText(bytes),
      _ => null,
    };
  }

  static String decodeText(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes.sublist(2), littleEndian: false);
    }
    var source = bytes;
    if (source.isNotEmpty &&
        source[0] == 0xEF &&
        source.length >= 3 &&
        source[1] == 0xBB &&
        source[2] == 0xBF) {
      source = source.sublist(3);
    }
    final value = utf8.decode(source, allowMalformed: true);
    if (!value.contains('\uFFFD')) return value;
    try {
      final legacy = gbk.decode(source, allowMalformed: true);
      if (!legacy.contains('\uFFFD')) return legacy;
    } catch (_) {}
    return value;
  }

  static String _utf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? (bytes[i] | bytes[i + 1] << 8)
            : (bytes[i] << 8 | bytes[i + 1]),
      );
    }
    try {
      return String.fromCharCodes(units);
    } catch (_) {
      return '';
    }
  }

  static String _htmlText(String source) {
    final document = html.parse(source);
    for (final node in document.querySelectorAll('script,style,noscript')) {
      node.remove();
    }
    final blocks = document
        .querySelectorAll('p,h1,h2,h3,h4,h5,h6,li,blockquote,pre')
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final text = blocks.isEmpty
        ? (document.body?.text ?? document.documentElement?.text ?? '').trim()
        : blocks.join('\n\n');
    return _normalizeText(text);
  }

  static String _markdownText(String source) {
    try {
      return _htmlText(
        md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubWeb),
      );
    } catch (_) {
      return _normalizeText(source);
    }
  }

  static String _fb2Text(Uint8List bytes) {
    final document = XmlDocument.parse(decodeText(bytes));
    final blocks = <String>[];
    for (final element
        in document.findAllElements('body').expand((e) => e.descendants)) {
      if (element is! XmlElement) continue;
      switch (element.name.local) {
        case 'p':
        case 'subtitle':
        case 'title':
        case 'annotation':
        case 'empty-line':
          final text = element.innerText.trim();
          if (text.isNotEmpty) blocks.add(text);
      }
    }
    if (blocks.isEmpty) {
      return _normalizeText(document.rootElement.innerText);
    }
    return _normalizeText(blocks.join('\n\n'));
  }

  static String _rtfText(String source) {
    var value = _stripRtfGroups(source, const {
      'fonttbl',
      'colortbl',
      'stylesheet',
      'info',
      'pict',
      'object',
      'header',
      'footer',
    });
    value = value
        .replaceAllMapped(RegExp(r'\\u(-?\d+)\s*[?]?'), (m) {
          final code = int.tryParse(m.group(1) ?? '');
          return code == null ? '' : String.fromCharCode(code);
        })
        .replaceAllMapped(
          RegExp(r"\\'([0-9a-fA-F]{2})"),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAll(r'\par', '\n')
        .replaceAll(r'\line', '\n')
        .replaceAll(r'\tab', '\t')
        .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
        .replaceAll(RegExp(r'\\[\\{}\\]'), '')
        .replaceAll(RegExp(r'[{}]'), '');
    return _normalizeText(value);
  }

  static String _stripRtfGroups(String source, Set<String> names) {
    final out = StringBuffer();
    var i = 0;
    while (i < source.length) {
      final startGroup = source.indexOf('{\\', i);
      if (startGroup < 0) {
        out.write(source.substring(i));
        break;
      }
      out.write(source.substring(i, startGroup));
      var cursor = startGroup + 2;
      final word = StringBuffer();
      while (cursor < source.length &&
          RegExp(r'[a-zA-Z]').hasMatch(source[cursor])) {
        word.write(source[cursor]);
        cursor++;
      }
      if (!names.contains(word.toString())) {
        out.write(source.substring(startGroup, cursor));
        i = cursor;
        continue;
      }
      var depth = 1;
      while (cursor < source.length && depth > 0) {
        final c = source[cursor++];
        if (c == '{') depth++;
        if (c == '}') depth--;
      }
      i = cursor;
    }
    return out.toString();
  }

  static String _docxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final entry = archive.files
        .where(
          (f) =>
              f.isFile &&
              (f.name == 'word/document.xml' ||
                  f.name.endsWith('/document.xml')),
        )
        .firstOrNull;
    if (entry == null) throw const FormatException('DOCX 缺少正文');
    final document = XmlDocument.parse(
      decodeText(Uint8List.fromList(entry.content as List<int>)),
    );
    final blocks = <String>[];
    for (final paragraph in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'p',
    )) {
      final buffer = StringBuffer();
      for (final node in paragraph.descendants) {
        if (node is! XmlElement) continue;
        if (node.name.local == 't') buffer.write(node.innerText);
        if (node.name.local == 'tab') buffer.write('\t');
        if (node.name.local == 'br') buffer.write('\n');
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) blocks.add(text);
    }
    if (blocks.isEmpty) throw const FormatException('DOCX 没有可读正文');
    return _normalizeText(blocks.join('\n\n'));
  }

  static String _odtText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final entry = archive.files
        .where((f) => f.isFile && f.name == 'content.xml')
        .firstOrNull;
    if (entry == null) throw const FormatException('ODT 缺少正文');
    final document = XmlDocument.parse(
      decodeText(Uint8List.fromList(entry.content as List<int>)),
    );
    final blocks = <String>[];
    for (final paragraph in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'p',
    )) {
      final text = paragraph.innerText.trim();
      if (text.isNotEmpty) blocks.add(text);
    }
    for (final heading in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'h',
    )) {
      final text = heading.innerText.trim();
      if (text.isNotEmpty && !blocks.contains(text)) blocks.insert(0, text);
    }
    if (blocks.isEmpty) throw const FormatException('ODT 没有可读正文');
    return _normalizeText(blocks.join('\n\n'));
  }

  static String? _kindleText(Uint8List bytes) {
    if (bytes.length < 100) return null;
    final records = _u16(bytes, 76);
    if (records < 2) return null;
    final first = _u32(bytes, 78);
    if (first < 0 || first + 16 > bytes.length) return null;
    final compression = _u16(bytes, first);
    if (compression == 2) {
      throw const FormatException('Kindle Huffman 压缩暂不支持');
    }
    final textLength = _u32(bytes, first + 2);
    final textRecords = _u16(bytes, first + 6);
    if (textRecords <= 0 || textRecords >= records || textLength == 0) {
      return _kindleKf8(bytes, records, first, compression);
    }
    final parts = <int>[];
    for (var i = 1; i <= textRecords; i++) {
      final start = _u32(bytes, 78 + i * 8);
      final end = i + 1 < records
          ? _u32(bytes, 78 + (i + 1) * 8)
          : bytes.length;
      if (start < 0 || start >= end || end > bytes.length) continue;
      final chunk = Uint8List.sublistView(bytes, start, end);
      if (compression == 0) {
        parts.addAll(chunk);
      } else if (compression == 1) {
        parts.addAll(_palmDoc(chunk));
      } else {
        return null;
      }
      if (textLength > 0 && parts.length >= textLength) break;
    }
    var source = Uint8List.fromList(
      textLength > 0 && parts.length > textLength
          ? parts.sublist(0, textLength)
          : parts,
    );
    final hasMobi =
        first + 28 <= bytes.length &&
        String.fromCharCodes(bytes.sublist(first + 16, first + 20)) == 'MOBI';
    final encoding = hasMobi ? _u32(bytes, first + 28) : 0;
    if (encoding == 1252) {
      return _normalizeText(
        latin1
            .decode(source, allowInvalid: true)
            .replaceAll('\u0000', '')
            .replaceAll('\u0001', ''),
      );
    }
    final text = decodeText(
      source,
    ).replaceAll('\u0000', '').replaceAll('\u0001', '').trim();
    return text.isEmpty ? null : _normalizeText(text);
  }

  /// KF8/AZW3 keeps HTML fragments in records after a BOUNDARY marker. Older
  /// builds also use the same Palm database wrapper, so this fallback lets the
  /// online reader open those files without a platform Kindle converter.
  static String? _kindleKf8(
    Uint8List bytes,
    int records,
    int first,
    int compression,
  ) {
    if (compression == 2 || records <= 1) return null;
    final out = <int>[];
    var hasBoundary = false;
    for (var i = 1; i < records; i++) {
      final start = _u32(bytes, 78 + i * 8);
      final end = i + 1 < records
          ? _u32(bytes, 78 + (i + 1) * 8)
          : bytes.length;
      if (start >= 0 &&
          start < end &&
          end <= bytes.length &&
          _indexOfAscii(Uint8List.sublistView(bytes, start, end), 'BOUNDARY') >=
              0) {
        hasBoundary = true;
        break;
      }
    }
    var afterBoundary = !hasBoundary;
    for (var i = 1; i < records; i++) {
      final start = _u32(bytes, 78 + i * 8);
      final end = i + 1 < records
          ? _u32(bytes, 78 + (i + 1) * 8)
          : bytes.length;
      if (start < 0 || start >= end || end > bytes.length) continue;
      final chunk = Uint8List.sublistView(bytes, start, end);
      final marker = _indexOfAscii(chunk, 'BOUNDARY');
      final data = marker >= 0 ? chunk.sublist(marker + 8) : chunk;
      if (marker >= 0) afterBoundary = true;
      if (!afterBoundary && marker < 0) continue;
      if (compression == 1) {
        out.addAll(_palmDoc(data));
      } else {
        out.addAll(data);
      }
      if (out.length > 64 * 1024 * 1024) break;
    }
    final source = decodeText(
      Uint8List.fromList(out),
    ).replaceAll('\u0000', '').replaceAll('\u0001', '');
    if (!source.contains('<')) return null;
    final text = _htmlText(source);
    return text.isEmpty ? null : text;
  }

  static int _indexOfAscii(Uint8List bytes, String value) {
    final needle = value.codeUnits;
    outer:
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static List<int> _palmDoc(Uint8List data) {
    final out = <int>[];
    var i = 0;
    while (i < data.length) {
      final c = data[i++];
      if (c == 0) {
        if (i >= data.length) break;
        out.add(data[i++]);
      } else if (c <= 8) {
        final count = c;
        for (var n = 0; n < count && i < data.length; n++) {
          out.add(data[i++]);
        }
      } else if (c <= 0x7f) {
        out.add(c);
      } else if (c <= 0xbf) {
        if (i >= data.length) break;
        final b = data[i++];
        final distance = ((c & 0x7f) << 5) | (b >> 3);
        final length = (b & 7) + 3;
        if (distance == 0 || distance > out.length) break;
        for (var n = 0; n < length; n++) {
          out.add(out[out.length - distance]);
        }
      } else {
        out.add(0x20);
        out.add(c ^ 0x80);
      }
    }
    return out;
  }

  static int _u16(Uint8List bytes, int offset) =>
      offset + 1 < bytes.length ? bytes[offset] | bytes[offset + 1] << 8 : 0;

  static int _u32(Uint8List bytes, int offset) => offset + 3 < bytes.length
      ? bytes[offset] |
            bytes[offset + 1] << 8 |
            bytes[offset + 2] << 16 |
            bytes[offset + 3] << 24
      : 0;

  static String? _zipText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    if (_isEpubArchive(archive)) return null;
    final parts = <String>[];
    var total = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final size = entry.size;
      if (size <= 0) continue;
      total += size;
      if (total > 160 * 1024 * 1024) break;
      final text = extract(
        entry.name,
        Uint8List.fromList(entry.content as List<int>),
      );
      if (text == null || text.trim().isEmpty) continue;
      parts.add('《${_stem(entry.name)}》\n\n$text');
    }
    if (parts.isEmpty) return null;
    return parts.join('\n\n\n');
  }

  static List<PreparedTextDocument> _prepareZip(
    String name,
    Uint8List bytes,
    Directory directory,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      if (_isEpubArchive(archive)) {
        final output = _reserve(directory, name, '.epub');
        File(output).writeAsBytesSync(bytes);
        return [(name: _stem(name) + '.epub', path: output, error: null)];
      }
      final result = <PreparedTextDocument>[];
      var total = 0;
      for (final entry in archive.files) {
        if (!entry.isFile || entry.size <= 0) continue;
        total += entry.size;
        if (total > 512 * 1024 * 1024 || result.length >= 120) break;
        final inner = entry.name;
        final ext = _extension(inner);
        if (!convertible.contains(ext) || ext == 'zip') continue;
        final data = Uint8List.fromList(entry.content as List<int>);
        if (ext == 'docx' || ext == 'odt') {
          final text = extract(inner, data);
          if (text != null && text.trim().isNotEmpty) {
            result.add(_writeText(_stem(inner) + '.txt', text, directory));
          }
          continue;
        }
        final text = extract(inner, data);
        if (text == null || text.trim().isEmpty) continue;
        result.add(_writeText(_stem(inner) + '.txt', text, directory));
      }
      if (result.isEmpty) {
        return [(name: name, path: null, error: 'ZIP 里没有可阅读的书籍文件')];
      }
      return result;
    } catch (_) {
      return [(name: name, path: null, error: '无法解析这个 ZIP 文件')];
    }
  }

  static bool _isEpubArchive(Archive archive) {
    final mimetype = archive.files
        .where((f) => f.isFile && f.name == 'mimetype')
        .firstOrNull;
    if (mimetype == null) return false;
    return utf8
        .decode(mimetype.content as List<int>, allowMalformed: true)
        .trim()
        .toLowerCase()
        .startsWith('application/epub+zip');
  }

  static PreparedTextDocument _writeText(
    String name,
    String text,
    Directory directory,
  ) {
    final output = _reserve(directory, _stem(name) + '.txt', '.txt');
    File(output).writeAsStringSync(_normalizeText(text));
    return (name: _stem(name) + '.txt', path: output, error: null);
  }

  static String _reserve(Directory directory, String name, String extension) {
    directory.createSync(recursive: true);
    final base = _safeStem(name);
    var index = 0;
    while (true) {
      final path =
          '${directory.path}/$base${index == 0 ? '' : '-$index'}$extension';
      if (!File(path).existsSync()) return path;
      index++;
    }
  }

  static String _safeStem(String name) {
    final stem = _stem(name)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stem.isEmpty ? '网盘书籍' : stem;
  }

  static String _stem(String name) {
    final slash = name.lastIndexOf('/');
    final base = slash >= 0 ? name.substring(slash + 1) : name;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String _normalizeText(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
