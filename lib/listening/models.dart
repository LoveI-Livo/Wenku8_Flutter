import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../reader_content.dart';

enum ListeningSource { edge, system, custom }

enum ListeningPhase { stopped, preparing, playing, paused, completed, failed }

const listeningMinimumSpeed = .5;
const listeningMaximumSpeed = 3.0;
const listeningMaximumParagraphGapMs = 3000;
int normalizeListeningParagraphGap(int value) =>
    (value.clamp(0, listeningMaximumParagraphGapMs) / 100).round() * 100;

class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.label,
    required this.source,
    this.locale = 'zh-CN',
    this.engine,
    this.offline = false,
    this.quality = 0,
  });
  final String id, label, locale;
  final ListeningSource source;
  final String? engine;
  final bool offline;
  final int quality;
  bool get supported =>
      source != ListeningSource.system || supportedSystemSpeechEngine(engine);
  bool get availableForListening => supported;
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'source': source.name,
    'locale': locale,
    'engine': engine,
    'offline': offline,
    'quality': quality,
    if (source == ListeningSource.system) 'systemApi': 1,
  };
  factory SpeechVoice.fromJson(Map<String, dynamic> json) => SpeechVoice(
    id: json['id'] as String,
    label: json['label'] as String,
    source: switch (json['source']) {
      'system' => ListeningSource.system,
      'custom' => ListeningSource.custom,
      _ => ListeningSource.edge,
    },
    locale: json['locale'] is String ? json['locale'] : 'zh-CN',
    engine: json['engine'] as String?,
    offline: json['offline'] == true,
    quality: json['quality'] is int ? json['quality'] : 0,
  );
}

const defaultEdgeVoice = SpeechVoice(
  id: 'zh-CN-XiaoxiaoNeural',
  label: '晓晓 · 温柔女声',
  source: ListeningSource.edge,
);
const alternateEdgeVoice = SpeechVoice(
  id: 'zh-CN-YunxiNeural',
  label: '云希 · 阳光男声',
  source: ListeningSource.edge,
);

/// Built-in Chinese Edge voices. The online catalogue can advertise hundreds
/// of locales, but these keep the picker useful when the voice-list request is
/// slow, blocked or offline. Every ID is a public Edge neural voice.
const builtinEdgeVoices = <SpeechVoice>[
  defaultEdgeVoice,
  SpeechVoice(
    id: 'zh-CN-XiaoyiNeural',
    label: '晓伊 · 少女甜声',
    source: ListeningSource.edge,
  ),
  alternateEdgeVoice,
  SpeechVoice(
    id: 'zh-CN-YunjianNeural',
    label: '云健 · 激情男声',
    source: ListeningSource.edge,
  ),
  SpeechVoice(
    id: 'zh-CN-YunxiaNeural',
    label: '云夏 · 少年男声',
    source: ListeningSource.edge,
  ),
  SpeechVoice(
    id: 'zh-CN-YunyangNeural',
    label: '云扬 · 沉稳播音',
    source: ListeningSource.edge,
  ),
  SpeechVoice(
    id: 'zh-CN-liaoning-XiaobeiNeural',
    label: '晓北 · 东北女声',
    source: ListeningSource.edge,
    locale: 'zh-CN-liaoning',
  ),
  SpeechVoice(
    id: 'zh-CN-shaanxi-XiaoniNeural',
    label: '晓妮 · 陕西女声',
    source: ListeningSource.edge,
    locale: 'zh-CN-shaanxi',
  ),
  SpeechVoice(
    id: 'zh-HK-HiuGaaiNeural',
    label: '慧佳 · 粤语女声',
    source: ListeningSource.edge,
    locale: 'zh-HK',
  ),
  SpeechVoice(
    id: 'zh-HK-HiuMaanNeural',
    label: '慧曼 · 粤语温柔女声',
    source: ListeningSource.edge,
    locale: 'zh-HK',
  ),
  SpeechVoice(
    id: 'zh-HK-WanLungNeural',
    label: '云龙 · 粤语男声',
    source: ListeningSource.edge,
    locale: 'zh-HK',
  ),
  SpeechVoice(
    id: 'zh-TW-HsiaoChenNeural',
    label: '晓陈 · 台湾女声',
    source: ListeningSource.edge,
    locale: 'zh-TW',
  ),
  SpeechVoice(
    id: 'zh-TW-HsiaoYuNeural',
    label: '晓雨 · 台湾甜声',
    source: ListeningSource.edge,
    locale: 'zh-TW',
  ),
  SpeechVoice(
    id: 'zh-TW-YunJheNeural',
    label: '云哲 · 台湾男声',
    source: ListeningSource.edge,
    locale: 'zh-TW',
  ),
];

SpeechVoice? builtinEdgeVoiceById(String id) {
  for (final voice in builtinEdgeVoices) {
    if (voice.id == id) return voice;
  }
  return null;
}

/// Installed engines are used exclusively through the host's public TTS API.
bool supportedSystemSpeechEngine(String? engine) =>
    engine != null &&
    (engine == '@default' ||
        RegExp(r'^[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+$').hasMatch(engine));

/// Normalize ISO Chinese metadata without changing the native voice ID.
String? chineseSpeechLocale(String value) {
  final parts = value.trim().replaceAll('_', '-').split('-');
  if (parts.any((part) => part.isEmpty) ||
      !const {'zh', 'chi', 'zho'}.contains(parts.first.toLowerCase())) {
    return null;
  }
  if (parts.length == 1) return 'zh-CN';
  return [
    'zh',
    for (final part in parts.skip(1))
      if (part.length == 4)
        '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}'
      else if (part.length == 2)
        part.toUpperCase()
      else
        part,
  ].join('-');
}

enum SpeechRole { narration, dialogue }

class SpeechSegment {
  const SpeechSegment(
    this.paragraph,
    this.start,
    this.end,
    this.text, {
    this.language = '',
    this.role = SpeechRole.narration,
  });
  final int paragraph, start, end;
  final String text, language;
  final SpeechRole role;
  String key(SpeechVoice voice, {double gainDb = 0}) => sha256
      .convert(
        utf8.encode(
          'speech-v2|${voice.source.name}|${voice.engine}|${voice.id}'
          '${voice.id == '@default' || voice.source == ListeningSource.custom ? '|${voice.locale}' : ''}'
          '|${gainDb.toStringAsFixed(1)}|$text',
        ),
      )
      .toString();
}

final _speechLetters = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Keep UTF-16 offsets intact while removing characters that speech engines
/// reject. This changes the synthesis copy, never the reader's original text.
String speechText(String text) {
  final clean = StringBuffer();
  for (final rune in text.runes) {
    final xml =
        rune == 9 ||
        rune == 10 ||
        rune == 13 ||
        (rune >= 0x20 && rune <= 0xD7FF) ||
        (rune >= 0xE000 && rune <= 0xFFFD) ||
        (rune >= 0x10000 && rune <= 0x10FFFF);
    final invisible =
        (rune >= 0x7F && rune <= 0x9F) ||
        (rune >= 0x200B && rune <= 0x200F) ||
        (rune >= 0x202A && rune <= 0x202E) ||
        (rune >= 0x2060 && rune <= 0x2069) ||
        rune == 0xFEFF ||
        rune == 0xFFFD ||
        (rune >= 0xFDD0 && rune <= 0xFDEF) ||
        (rune & 0xFFFF) >= 0xFFFE;
    if (!xml || invisible) {
      clean.write(rune > 0xFFFF ? '  ' : ' ');
    } else {
      clean.writeCharCode(rune);
    }
  }
  return clean.toString();
}

bool hasSpeechText(String text) => _speechLetters.hasMatch(speechText(text));

/// A rejected long input gets one smaller-clause pass before anything is
/// skipped. Parts remain on the original paragraph and selection offsets.
List<SpeechSegment> speechRecoverySegments(SpeechSegment segment) {
  if (segment.text.length <= 100) return [segment];
  return [
    for (final part in speechSegments(
      [segment.text],
      maximum: 80,
      forceRole: segment.role,
    ))
      SpeechSegment(
        segment.paragraph,
        segment.start + part.start,
        segment.start + part.end,
        part.text,
        language: segment.language,
        role: part.role,
      ),
  ];
}

class _SpeechRange {
  const _SpeechRange(this.start, this.end, this.role);
  final int start, end;
  final SpeechRole role;
}

/// Split quoted speech away from narration without moving UTF-16 offsets.
/// Narrator and dialogue can then use different voices while tapping a line
/// still maps back to the same paragraph position.
List<_SpeechRange> _speechRanges(String text) {
  const pairs = {'“': '”', '「': '」', '『': '』', '"': '"'};
  final ranges = <_SpeechRange>[];
  var cursor = 0, index = 0;
  while (index < text.length) {
    final close = pairs[text[index]];
    if (close == null) {
      index++;
      continue;
    }
    final end = text.indexOf(close, index + 1);
    if (end <= index + 1) {
      index++;
      continue;
    }
    if (index > cursor) {
      ranges.add(_SpeechRange(cursor, index, SpeechRole.narration));
    }
    ranges.add(_SpeechRange(index + 1, end, SpeechRole.dialogue));
    cursor = end + 1;
    index = end + 1;
  }
  if (cursor < text.length) {
    ranges.add(_SpeechRange(cursor, text.length, SpeechRole.narration));
  }
  return ranges.isEmpty
      ? [_SpeechRange(0, text.length, SpeechRole.narration)]
      : ranges;
}

/// Original UTF-16 offsets remain valid for selection; paired illustration markers are never spoken.
List<SpeechSegment> speechSegments(
  List<String> paragraphs, {
  int maximum = 240,
  SpeechRole? forceRole,
}) {
  if (maximum < 20 || maximum > 1000) {
    throw ArgumentError.value(maximum, 'maximum');
  }
  final result = <SpeechSegment>[];
  for (var index = 0; index < paragraphs.length; index++) {
    final text = paragraphs[index];
    final trimmed = text.trim();
    if (readerIllustrationUrl(text) != null ||
        trimmed.isEmpty ||
        trimmed == '[插图]' ||
        (trimmed.startsWith('<!--image-->') &&
            trimmed.endsWith('<!--image-->'))) {
      continue;
    }
    for (final range in _speechRanges(text)) {
      _appendSpeechRange(
        result,
        index,
        text,
        range.start,
        range.end,
        forceRole ?? range.role,
        maximum,
      );
    }
  }
  return List.unmodifiable(result);
}

void _appendSpeechRange(
  List<SpeechSegment> result,
  int paragraph,
  String text,
  int rangeStart,
  int rangeEnd,
  SpeechRole role,
  int maximum,
) {
  var offset = rangeStart;
  while (offset < rangeEnd && text[offset].trim().isEmpty) {
    offset++;
  }
  var end = rangeEnd;
  while (end > offset && text[end - 1].trim().isEmpty) {
    end--;
  }
  while (offset < end) {
    var chunkEnd = (offset + maximum).clamp(0, end);
    if (chunkEnd < end) {
      // Keep surrogate pairs intact and prefer a complete clause over a chopped phrase.
      if (chunkEnd > offset &&
          text.codeUnitAt(chunkEnd - 1) >= 0xD800 &&
          text.codeUnitAt(chunkEnd - 1) <= 0xDBFF) {
        chunkEnd--;
      }
      final window = text.substring(offset, chunkEnd);
      final breaks = RegExp(r'[。！？!?；;\n]').allMatches(window).toList();
      if (breaks.isNotEmpty && breaks.last.end >= maximum ~/ 3) {
        chunkEnd = offset + breaks.last.end;
      } else {
        // A long sentence should pause at a clause or word boundary instead
        // of restarting the voice in the middle of a phrase, number or name.
        final clauses = RegExp(r'[，,：:、\s]').allMatches(window).where((m) {
          if (m.end < maximum ~/ 2) return false;
          final at = offset + m.start;
          final comma = text[at] == ',' || text[at] == '，';
          bool digit(int index) =>
              index >= 0 &&
              index < text.length &&
              text.codeUnitAt(index) >= 48 &&
              text.codeUnitAt(index) <= 57;
          return !comma || !(digit(at - 1) && digit(at + 1));
        }).toList();
        if (clauses.isNotEmpty) chunkEnd = offset + clauses.last.end;
      }
    }
    final fragment = speechText(text.substring(offset, chunkEnd));
    if (_speechLetters.hasMatch(fragment)) {
      result.add(
        SpeechSegment(paragraph, offset, chunkEnd, fragment, role: role),
      );
    }
    offset = chunkEnd;
  }
}

class SpeechCancelled implements Exception {
  const SpeechCancelled();
}

enum SpeechFailureKind { unavailable, missingLanguage, content, timeout }

class SpeechFailure implements Exception {
  const SpeechFailure(
    this.message, {
    this.kind = SpeechFailureKind.unavailable,
  });
  final String message;
  final SpeechFailureKind kind;
  bool get recoverable =>
      kind == SpeechFailureKind.content || kind == SpeechFailureKind.timeout;
  @override
  String toString() => message;
}

class SpeechCancellation {
  bool _cancelled = false;
  final List<void Function()> _handlers = [];
  bool get cancelled => _cancelled;
  void check() {
    if (_cancelled) throw const SpeechCancelled();
  }

  void Function() onCancel(void Function() handler) {
    if (_cancelled) {
      handler();
    } else {
      _handlers.add(handler);
    }
    return () => _handlers.remove(handler);
  }

  /// A cancelled seek must not wait for a stuck vendor/network Future. The
  /// original Future retains an error handler even if it finishes much later.
  Future<T> wait<T>(Future<T> future) {
    final result = Completer<T>();
    final remove = onCancel(() {
      if (!result.isCompleted) result.completeError(const SpeechCancelled());
    });
    future.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future.whenComplete(remove);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final handler in List.of(_handlers)) {
      handler();
    }
    _handlers.clear();
  }
}

class ListeningCursor {
  const ListeningCursor({
    required this.novelId,
    required this.chapterId,
    required this.chapter,
    required this.paragraph,
    required this.start,
    required this.positionMs,
    required this.segmentHash,
  });
  final int novelId, chapterId, chapter, paragraph, start, positionMs;
  final String segmentHash;
  Map<String, Object> toJson() => {
    'novelId': novelId,
    'chapterId': chapterId,
    'chapter': chapter,
    'paragraph': paragraph,
    'start': start,
    'positionMs': positionMs,
    'segmentHash': segmentHash,
  };
  factory ListeningCursor.fromJson(Map<String, dynamic> json) {
    int number(String key) =>
        json[key] is int ? (json[key] as int).clamp(0, 0x7fffffff) : 0;
    return ListeningCursor(
      novelId: number('novelId'),
      chapterId: number('chapterId'),
      chapter: number('chapter'),
      paragraph: number('paragraph'),
      start: number('start'),
      positionMs: number('positionMs'),
      segmentHash: json['segmentHash'] is String ? json['segmentHash'] : '',
    );
  }
}
