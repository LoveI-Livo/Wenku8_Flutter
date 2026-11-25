import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
    this.multilingual = false,
  });
  final String id, label, locale;
  final ListeningSource source;
  final String? engine;
  final bool offline;
  final int quality;

  /// Multilingual neural voices can read Chinese even though their native
  /// locale is not Chinese. They are exposed with a Chinese locale so the
  /// narrator/character matching code can use them like any other voice.
  final bool multilingual;
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
    'multilingual': multilingual,
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
    multilingual: json['multilingual'] == true,
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
  // Microsoft multilingual neural voices. They are real Edge voices and have
  // been verified to synthesize Mandarin; giving each character one of these
  // avoids reusing the same six zh-CN voices for every speaker.
  SpeechVoice(
    id: 'en-US-AvaMultilingualNeural',
    label: '艾娃 · 多语真人女声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'en-US-EmmaMultilingualNeural',
    label: '艾玛 · 多语真人女声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'en-US-BrianMultilingualNeural',
    label: '布莱恩 · 多语真人男声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'en-AU-WilliamMultilingualNeural',
    label: '威廉 · 多语真人男声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'fr-FR-VivienneMultilingualNeural',
    label: '薇薇安 · 多语真人女声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'fr-FR-RemyMultilingualNeural',
    label: '雷米 · 多语真人男声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'it-IT-GiuseppeMultilingualNeural',
    label: '朱塞佩 · 多语真人男声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'ko-KR-HyunsuMultilingualNeural',
    label: '贤秀 · 多语真人男声',
    source: ListeningSource.edge,
    multilingual: true,
  ),
  SpeechVoice(
    id: 'pt-BR-ThalitaMultilingualNeural',
    label: '塔莉塔 · 多语真人女声',
    source: ListeningSource.edge,
    multilingual: true,
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
    this.speaker = '',
  });
  final int paragraph, start, end;
  final String text, language;
  final SpeechRole role;

  /// Detected character name for quoted dialogue. Empty means the narrator or
  /// a quote with no trustworthy attribution.
  final String speaker;
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
      forceSpeaker: segment.speaker,
    ))
      SpeechSegment(
        segment.paragraph,
        segment.start + part.start,
        segment.start + part.end,
        part.text,
        language: segment.language,
        role: part.role,
        speaker: segment.speaker,
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

const _speakerPronouns = {
  '他',
  '她',
  '它',
  '我',
  '你',
  '您',
  '他们',
  '她们',
  '它们',
  '我们',
  '你们',
  '大家',
  '众人',
  '有人',
  '那人',
  '这人',
  '对方',
  '两人',
  '三人',
  '所有人',
  '男子',
  '女子',
  '少年',
  '少女',
  '老人',
  '孩子',
  '声音',
  '心中',
  '心里',
};

const _speakerNoise = {
  '说道',
  '说',
  '问道',
  '问',
  '答道',
  '答',
  '笑道',
  '笑',
  '喊道',
  '喊',
  '叫道',
  '叫',
  '低声说',
  '高声说',
  '冷声说',
  '轻声说',
  '开口',
  '道',
  '只见',
  '这时',
  '此时',
  '随后',
  '于是',
  '忽然',
  '突然',
  '却见',
  '然后',
  '接着',
  '同时',
  '一旁',
  '身后',
  '门外',
  '床上',
  '心里',
  '心中',
};

/// Strip speech-tag adverbs and reject pronouns/generic descriptions. A false
/// positive is worse than no attribution: it permanently gives a line to the
/// wrong character voice.
String? _cleanSpeechSpeaker(String raw) {
  var value = raw.trim().replaceAll(
    RegExp(r'^[\s，,。！？!?：:；;、“”「」『』]+|[\s，,。！？!?：:；;、“”「」『』]+$'),
    '',
  );
  value = value.replaceAll(
    RegExp(r'^(?:只见|这时|此时|随后|于是|忽然|突然|却见|然后|接着|同时|而|但|却|又|便|就|也|才|只)+'),
    '',
  );
  value = value.replaceAll(
    RegExp(
      r'(?:冷冷地|轻轻地|低声道|高声地|沉声道|柔声地|轻声地|大声地|小声地|笑着|苦笑着|连忙|急忙|缓缓|慢慢|忽然|突然|又|才|也|却|就|便|地)+$',
    ),
    '',
  );
  // A greedy capture can leave the final character of “笑道/问道/说道”.
  value = value.replaceAll(RegExp(r'(?:说|问|答|笑|喊|叫|道|低声|高声|冷声|轻声|沉声)+$'), '');
  value = value.replaceAll(RegExp(r'[，,。！？!?：:；;、]+$'), '');
  if (value.length < 2) return null;
  if (_speakerPronouns.contains(value) || _speakerNoise.contains(value)) {
    return null;
  }
  if (value.contains(RegExp(r'[的了着过是在有和与跟对把被让给说问道喊叫笑哭想看听站坐走]'))) {
    return null;
  }
  if (value.length > 4 && !value.contains('·')) return null;
  if (value.length > 8) return null;
  return value;
}

const _speechVerb =
    r'(?:低声说|高声说|冷声说|轻声说|开口道|说道|问道|答道|笑道|喊道|叫道|开口|说|问|答|笑|喊|叫|道)';

String? _speakerBeforeQuote(String text) {
  final match = RegExp(
    r'([\u4e00-\u9fa5·A-Za-z]{2,8})(?:[^。！？\n“”「」『』]{0,10})?' +
        _speechVerb +
        r'\s*[：:]?\s*[“「『"]?\s*$',
  ).firstMatch(text);
  return match == null ? null : _cleanSpeechSpeaker(match.group(1)!);
}

String? _speakerAfterQuote(String text) {
  final match = RegExp(
    r'^\s*[，,。！？!?]?\s*([\u4e00-\u9fa5·A-Za-z]{2,8})(?:[^。！？\n“”「」『』]{0,10})?' +
        _speechVerb,
  ).firstMatch(text);
  return match == null ? null : _cleanSpeechSpeaker(match.group(1)!);
}

String? _speakerInsideQuote(String text) {
  final match = RegExp(
    r'^\s*([\u4e00-\u9fa5·A-Za-z]{2,6})\s*[：:]',
  ).firstMatch(text);
  return match == null ? null : _cleanSpeechSpeaker(match.group(1)!);
}

String? _speakerInNarration(String text) {
  final matches = RegExp(
    r'([\u4e00-\u9fa5·]{2,4})(?:推|走|站|坐|看|笑|叹|点|摇|转|抬|低|沉|把|将|从|向|对|和|跟)',
  ).allMatches(text).toList();
  for (final match in matches.reversed) {
    final speaker = _cleanSpeechSpeaker(match.group(1)!);
    if (speaker != null) return speaker;
  }
  return null;
}

bool _pronounAttribution(String text) {
  final match = RegExp(
    r'([他她它我你您他们她们])(?:[^。！？\n“”「」『』]{0,10})?' + _speechVerb,
  ).firstMatch(text);
  return match != null;
}

String? _speakerForRange(String text, _SpeechRange range, String? last) {
  final before = text.substring(math.max(0, range.start - 80), range.start);
  final after = text.substring(
    math.min(text.length, range.end + 1),
    math.min(text.length, range.end + 81),
  );
  final inside = _speakerInsideQuote(text.substring(range.start, range.end));
  final candidate =
      inside ?? _speakerBeforeQuote(before) ?? _speakerAfterQuote(after);
  if (candidate != null) return candidate;
  if (_pronounAttribution(before) || _pronounAttribution(after)) {
    return last ?? _speakerInNarration(before);
  }
  return null;
}

/// Original UTF-16 offsets remain valid for selection; paired illustration markers are never spoken.
List<SpeechSegment> speechSegments(
  List<String> paragraphs, {
  int maximum = 240,
  SpeechRole? forceRole,
  String forceSpeaker = '',
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
    var lastSpeaker = '';
    for (final range in _speechRanges(text)) {
      final role = forceRole ?? range.role;
      var speaker = forceSpeaker;
      if (speaker.isEmpty && role == SpeechRole.dialogue) {
        speaker =
            _speakerForRange(
              text,
              range,
              lastSpeaker.isEmpty ? null : lastSpeaker,
            ) ??
            '';
        if (speaker.isNotEmpty) lastSpeaker = speaker;
      }
      _appendSpeechRange(
        result,
        index,
        text,
        range.start,
        range.end,
        role,
        maximum,
        speaker,
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
  String speaker,
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
        SpeechSegment(
          paragraph,
          offset,
          chunkEnd,
          fragment,
          role: role,
          speaker: speaker,
        ),
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
