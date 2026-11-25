import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The optional "listening enhancement" only shapes playback. It never changes
/// the synthesised voice cache, the stored cursors or the reading library.
enum ListeningEnhancementMode {
  off('关闭', '保持原始音量，不做额外处理'),
  speech('人声增强', '突出人声清晰度，弱化背景噪声'),
  night('夜间柔和', '降低刺耳高频，深夜听书更轻');

  const ListeningEnhancementMode(this.label, this.description);

  final String label, description;

  static ListeningEnhancementMode parse(Object? value) => switch (value) {
    'speech' || 'voice' || 'clarity' => ListeningEnhancementMode.speech,
    'night' || 'soft' || 'gentle' => ListeningEnhancementMode.night,
    _ => ListeningEnhancementMode.off,
  };
}

const listeningEnhancementMaximumGain = 12.0;
const listeningMinimumVolumePercent = 100;
const listeningMaximumVolumePercent = 200;

double _gain(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value.trim()) ?? 0
      : 0;
  if (number.isNaN || number.isInfinite) return 0;
  return number.clamp(0, listeningEnhancementMaximumGain).toDouble();
}

int _volumePercent(Object? value, {double? legacyGain}) {
  final number = value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value.trim()) ?? 0
      : 0;
  if (number >= listeningMinimumVolumePercent &&
      number <= listeningMaximumVolumePercent) {
    return number;
  }
  if (legacyGain != null && legacyGain > 0) {
    final percent = 100 * math.pow(10, legacyGain / 20);
    return percent.round().clamp(
      listeningMinimumVolumePercent,
      listeningMaximumVolumePercent,
    );
  }
  return listeningMinimumVolumePercent;
}

/// A small, immutable record so a damaged preference cannot break playback.
@immutable
class ListeningEnhancementPreference {
  const ListeningEnhancementPreference({
    this.mode = ListeningEnhancementMode.off,
    this.gain = 0,
    this.normalize = false,
    this.volumePercent = listeningMinimumVolumePercent,
  });

  static const none = ListeningEnhancementPreference();

  final ListeningEnhancementMode mode;

  /// Extra loudness in dB, 0 – [listeningEnhancementMaximumGain].
  final double gain;

  /// Even out quiet and loud passages instead of adding gain.
  final bool normalize;

  /// Playback loudness, 100 – 200 %. 200 % is a real +6 dB boost rather than
  /// a cosmetic slider label.
  final int volumePercent;

  bool get enabled =>
      mode != ListeningEnhancementMode.off ||
      normalize ||
      gain > 0 ||
      volumePercent > listeningMinimumVolumePercent;

  double get volumeGainDb => 20 * math.log(volumePercent / 100) / math.ln10;

  String get summary {
    if (!enabled) return '未启用';
    return [
      if (mode != ListeningEnhancementMode.off) mode.label,
      if (volumePercent > listeningMinimumVolumePercent) '音量 $volumePercent%',
      if (gain > 0) '+${gain.toStringAsFixed(0)} dB',
      if (normalize) '音量均衡',
    ].join(' · ');
  }

  Map<String, Object> toJson() => {
    'mode': mode.name,
    'gain': gain,
    'normalize': normalize,
    'volumePercent': volumePercent,
  };

  factory ListeningEnhancementPreference.fromJson(Map<dynamic, dynamic> json) {
    final legacyGain = _gain(json['gain']);
    return ListeningEnhancementPreference(
      mode: ListeningEnhancementMode.parse(json['mode']),
      gain: legacyGain,
      normalize: json['normalize'] == true,
      volumePercent: _volumePercent(
        json['volumePercent'],
        legacyGain: legacyGain,
      ),
    );
  }

  ListeningEnhancementPreference copyWith({
    ListeningEnhancementMode? mode,
    double? gain,
    bool? normalize,
    int? volumePercent,
  }) => ListeningEnhancementPreference(
    mode: mode ?? this.mode,
    gain: gain == null ? this.gain : _gain(gain),
    normalize: normalize ?? this.normalize,
    volumePercent: volumePercent == null
        ? this.volumePercent
        : _volumePercent(volumePercent),
  );

  @override
  bool operator ==(Object other) =>
      other is ListeningEnhancementPreference &&
      other.mode == mode &&
      other.gain == gain &&
      other.normalize == normalize &&
      other.volumePercent == volumePercent;

  @override
  int get hashCode => Object.hash(mode, gain, normalize, volumePercent);

  @override
  String toString() =>
      'ListeningEnhancementPreference(${mode.name}, +$gain dB, '
      '${volumePercent}%, normalize: $normalize)';
}

/// Holds the current enhancement preference and notifies the listening panel.
///
/// [Listenable] is implemented directly (rather than [ChangeNotifier]) because
/// the controller awaits [dispose]; a notifier's `void dispose()` could not be
/// awaited.
class ListeningEnhancement implements Listenable {
  int? _audioSessionId;

  /// 当前音频会话 id（Android 上由播放器回传）。
  int? get audioSessionId => _audioSessionId;

  ListeningEnhancement({
    ListeningEnhancementPreference preference =
        ListeningEnhancementPreference.none,
  }) : _preference = preference;

  ListeningEnhancementPreference _preference;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _disposed = false;

  ListeningEnhancementPreference get preference => _preference;

  bool get enabled => _preference.enabled;

  /// Gain that playback should apply, already neutralised when switched off.
  /// [ListeningEnhancementPreference.volumePercent] is independent of the
  /// optional tone mode: selecting 200 % must still produce a louder signal.
  double get effectiveGain => math.max(
    _preference.mode == ListeningEnhancementMode.off ? 0 : _preference.gain,
    _preference.volumeGainDb,
  );

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Restore a stored preference before playback starts.
  Future<void> configure(
    ListeningEnhancementPreference value, {
    int? audioSessionId,
  }) async {
    _audioSessionId = audioSessionId;
    _apply(value);
  }

  /// Save an explicit user choice; the controller persists it separately.
  Future<void> setPreference(ListeningEnhancementPreference value) async {
    _apply(value);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
  }

  void _apply(ListeningEnhancementPreference value) {
    if (_disposed || value == _preference) return;
    _preference = value;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}
