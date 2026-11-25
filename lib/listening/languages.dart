import '../reader_content.dart';
import '../reader_languages.dart';
import 'models.dart';

final _kana = RegExp(r'[\u3041-\u3096\u30a1-\u30fa\uff66-\uff9f]');
final _han = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');
final _hangul = RegExp(r'[\uac00-\ud7a3\u1100-\u11ff]');

/// Primary language matching tolerates ISO metadata emitted by Android engines.
String speechLanguageCode(String value) => switch (readerLanguageCode(value)) {
  'chi' || 'zho' => 'zh',
  'jpn' => 'ja',
  'eng' => 'en',
  'kor' => 'ko',
  final code => code,
};

/// Explicit publication metadata wins. Without it, a Japanese quotation inside
/// substantial Han prose does not change the language of the entire paragraph.
/// Han-only text keeps the selected voice because Chinese/Japanese share it.
String speechParagraphLanguage(String tag, String text, String fallback) {
  final explicit = speechLanguageCode(tag);
  if (explicit.isNotEmpty && explicit != 'und') return explicit;
  final kana = _kana.allMatches(text).length;
  if (kana > 0) {
    final han = _han.allMatches(text).length;
    if (han < 32 || kana * 10 >= han) return 'ja';
  }
  if (_hangul.hasMatch(text)) return 'ko';
  return speechLanguageCode(fallback);
}

List<SpeechSegment> speechWithLanguages(
  List<SpeechSegment> segments,
  ReaderContent content,
  SpeechVoice preferred,
) {
  final languages = <int, String>{};
  return List.unmodifiable([
    for (final part in segments)
      SpeechSegment(
        part.paragraph,
        part.start,
        part.end,
        part.text,
        language: languages.putIfAbsent(
          part.paragraph,
          () => speechParagraphLanguage(
            content.formats[part.paragraph]?.language ?? '',
            content.paragraphs[part.paragraph],
            preferred.locale,
          ),
        ),
        role: part.role,
        speaker: part.speaker,
        gender: part.gender,
      ),
  ]);
}

const _femaleEdgeVoices = {
  'zh-CN-XiaoxiaoNeural',
  'zh-CN-XiaoyiNeural',
  'zh-CN-liaoning-XiaobeiNeural',
  'zh-CN-shaanxi-XiaoniNeural',
  'zh-HK-HiuGaaiNeural',
  'zh-HK-HiuMaanNeural',
  'zh-TW-HsiaoChenNeural',
  'zh-TW-HsiaoYuNeural',
  'en-US-AvaMultilingualNeural',
  'en-US-EmmaMultilingualNeural',
  'fr-FR-VivienneMultilingualNeural',
  'pt-BR-ThalitaMultilingualNeural',
};

const _maleEdgeVoices = {
  'zh-CN-YunxiNeural',
  'zh-CN-YunjianNeural',
  'zh-CN-YunxiaNeural',
  'zh-CN-YunyangNeural',
  'zh-HK-WanLungNeural',
  'zh-TW-YunJheNeural',
  'en-US-BrianMultilingualNeural',
  'en-AU-WilliamMultilingualNeural',
  'fr-FR-RemyMultilingualNeural',
  'it-IT-GiuseppeMultilingualNeural',
  'ko-KR-HyunsuMultilingualNeural',
};

/// Public gender lookup for character-voice assignment. Custom/system voices
/// expose no metadata, so an explicit 男声/女声 label is the only safe cue.
SpeechVoiceGender speechVoiceGender(SpeechVoice voice) {
  if (_femaleEdgeVoices.contains(voice.id)) return SpeechVoiceGender.female;
  if (_maleEdgeVoices.contains(voice.id)) return SpeechVoiceGender.male;
  final label = voice.label.toLowerCase();
  if (label.contains('女声') ||
      label.contains('女音') ||
      label.contains('female')) {
    return SpeechVoiceGender.female;
  }
  if (label.contains('男声') || label.contains('男音') || label.contains('male')) {
    return SpeechVoiceGender.male;
  }
  return SpeechVoiceGender.neutral;
}

/// A dialogue voice in the same provider, engine and language. Online Edge
/// voices prefer the opposite gender; installed engines keep the narrator
/// rather than pretending a second model exists.
SpeechVoice? speechDialogueVoiceForLanguage(
  String language,
  SpeechVoice preferred,
  List<SpeechVoice> available,
) {
  final code = speechLanguageCode(language);
  if (code.isEmpty || preferred.source != ListeningSource.edge) return null;
  final female = _femaleEdgeVoices.contains(preferred.id);
  final male = _maleEdgeVoices.contains(preferred.id);
  final matches = available
      .where(
        (voice) =>
            voice.availableForListening &&
            voice.id != preferred.id &&
            voice.source == preferred.source &&
            voice.engine == preferred.engine &&
            speechLanguageCode(voice.locale) == code,
      )
      .toList();
  if (matches.isEmpty) return null;
  bool opposite(SpeechVoice voice) =>
      (female && _maleEdgeVoices.contains(voice.id)) ||
      (male && _femaleEdgeVoices.contains(voice.id));
  matches.sort((a, b) {
    final aOpposite = opposite(a), bOpposite = opposite(b);
    if (aOpposite != bOpposite) return aOpposite ? -1 : 1;
    final aPreferred = a.id == defaultEdgeVoice.id;
    final bPreferred = b.id == defaultEdgeVoice.id;
    if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
    return a.id.compareTo(b.id);
  });
  return matches.first;
}

/// A language is never routed to another provider/engine or a different language.
/// Regional variants within the same language can use an installed model.
SpeechVoice? speechVoiceForLanguage(
  String language,
  SpeechVoice preferred,
  List<SpeechVoice> available, {
  SpeechVoice? selected,
}) {
  final code = speechLanguageCode(language);
  if (code.isEmpty) return null;
  final matches = available
      .where(
        (voice) =>
            voice.availableForListening &&
            voice.source == preferred.source &&
            voice.engine == preferred.engine &&
            speechLanguageCode(voice.locale) == code &&
            voice.id != '@default',
      )
      .toList();
  if (matches.isEmpty) return null;
  if (selected != null) {
    if (selected.source != preferred.source ||
        selected.engine != preferred.engine ||
        speechLanguageCode(selected.locale) != code) {
      return null;
    }
    for (final voice in matches) {
      if (voice.id == selected.id) return voice;
    }
    // An explicitly selected missing model must not be replaced by another voice.
    return null;
  }
  matches.sort((a, b) {
    final aPreferred = a.id == preferred.id;
    final bPreferred = b.id == preferred.id;
    if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
    if (a.offline != b.offline) return a.offline ? -1 : 1;
    final quality = b.quality.compareTo(a.quality);
    return quality != 0 ? quality : a.id.compareTo(b.id);
  });
  return matches.first;
}
