import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/listening/edge_tts.dart';
import 'package:wenku8_flutter/listening/enhancement.dart';
import 'package:wenku8_flutter/listening/languages.dart';
import 'package:wenku8_flutter/listening/models.dart';

void main() {
  test('引号对白与旁白拆成独立语段并保留正文偏移', () {
    final segments = speechSegments(['他抬头看向窗外。“现在就走。”她说。']);
    expect(segments.map((segment) => segment.role), [
      SpeechRole.narration,
      SpeechRole.dialogue,
      SpeechRole.narration,
    ]);
    expect(segments[1].text, '现在就走。');
    expect(segments[1].start, greaterThan(0));
    expect(segments[1].end, lessThan('他抬头看向窗外。“现在就走。”她说。'.length));
  });

  test('在线女声自动配男声对白，在线男声自动配女声对白', () {
    final female = speechDialogueVoiceForLanguage(
      'zh-CN',
      defaultEdgeVoice,
      builtinEdgeVoices,
    );
    expect(female, isNotNull);
    expect(female!.id, isNot(defaultEdgeVoice.id));

    final maleNarrator = builtinEdgeVoices.firstWhere(
      (voice) => voice.id == 'zh-CN-YunxiNeural',
    );
    final maleDialogue = speechDialogueVoiceForLanguage(
      'zh-CN',
      maleNarrator,
      builtinEdgeVoices,
    );
    expect(maleDialogue, isNotNull);
    expect(maleDialogue!.id, isNot(maleNarrator.id));
    expect(maleDialogue.id, contains('Xiao'));
  });

  test('系统音色没有第二音色时不伪造分角色', () {
    final system = SpeechVoice(
      id: 'com.example.voice',
      label: '系统音色',
      source: ListeningSource.system,
      engine: 'com.example.engine',
    );
    expect(speechDialogueVoiceForLanguage('zh-CN', system, [system]), isNull);
  });

  test('自动识别多个具名角色并保留各自声线', () {
    final segments = speechSegments(['张三说：“你来了。”李四笑道：“坐吧。”']);
    final dialogue = segments
        .where((segment) => segment.role == SpeechRole.dialogue)
        .toList();
    expect(dialogue.map((segment) => segment.text), ['你来了。', '坐吧。']);
    expect(dialogue.map((segment) => segment.speaker), ['张三', '李四']);
  });

  test('代词对白沿用上一句的具名角色，不会把新角色并成旁白', () {
    final segments = speechSegments(['张三推门进来。“你来了。”他说。']);
    final dialogue = segments.firstWhere(
      (segment) => segment.role == SpeechRole.dialogue,
    );
    expect(dialogue.speaker, '张三');
  });

  test('多语真人音色通过Edge中文合成校验', () {
    expect(
      EdgeSpeechClient.validVoice('en-US-AvaMultilingualNeural', 'zh-CN'),
      isTrue,
    );
    expect(
      EdgeSpeechClient.validVoice('zh-CN-XiaoxiaoNeural', 'zh-CN'),
      isTrue,
    );
    expect(
      EdgeSpeechClient.validVoice('en-US-AvaMultilingualNeural', 'en-US'),
      isTrue,
    );
  });

  test('在线中文音色池包含多语真人音色', () {
    final multilingual = builtinEdgeVoices
        .where((voice) => voice.multilingual)
        .toList();
    expect(multilingual.length, greaterThanOrEqualTo(9));
    expect(multilingual.every((voice) => voice.locale == 'zh-CN'), isTrue);
  });

  test('200% 音量是真实 +6 dB，并且可以持久化', () {
    const preference = ListeningEnhancementPreference(volumePercent: 200);
    expect(preference.volumeGainDb, closeTo(6.0206, .01));
    expect(preference.enabled, isTrue);
    expect(preference.summary, contains('200%'));

    final restored = ListeningEnhancementPreference.fromJson(
      preference.toJson(),
    );
    expect(restored.volumePercent, 200);
    expect(restored.volumeGainDb, closeTo(6.0206, .01));
  });

  test('旧 dB 偏好迁移到百分比而不是清零', () {
    final restored = ListeningEnhancementPreference.fromJson({
      'mode': 'speech',
      'gain': 6,
      'normalize': false,
    });
    expect(restored.mode, ListeningEnhancementMode.speech);
    expect(restored.volumePercent, 200);
  });
}
