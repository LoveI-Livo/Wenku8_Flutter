import 'package:flutter/painting.dart';

import 'reading_visual_theme.dart';

const readingExportBrandName = '轻小说文库';

/// Resolve artwork once for a surface's snapshot. An artwork date does not add
/// a recorded date to the content; dateless excerpts can still follow the season.
String readingExportArt(
  ReadingVisualTheme theme, {
  DateTime? at,
  bool portrait = false,
}) {
  if (theme == ReadingVisualTheme.editorial) {
    final season = switch ((at ?? DateTime.now()).month) {
      3 || 4 || 5 => 'spring',
      6 || 7 || 8 => 'summer',
      9 || 10 || 11 => 'autumn',
      _ => 'winter',
    };
    return 'assets/report/char_season_$season.webp';
  }
  final style = readingExportTheme(theme);
  return portrait ? style.portraitArtAsset : style.artAsset;
}

/// One visual family for reports, bookmark cards and reading keepsakes.
/// Persisted identities and native home-widget presentation stay independent.
class ReadingExportTheme {
  const ReadingExportTheme({
    required this.identity,
    required this.label,
    required this.description,
    required this.artAsset,
    required this.portraitArtAsset,
    required this.backgroundValue,
    required this.foregroundValue,
    required this.mutedValue,
    required this.accentValue,
    this.previewAlignment = Alignment.centerRight,
    this.prefersSerif = false,
  });

  final ReadingVisualTheme identity;
  final String label, description, artAsset, portraitArtAsset;
  final int backgroundValue, foregroundValue, mutedValue, accentValue;
  final Alignment previewAlignment;
  final bool prefersSerif;
  Color get background => Color(backgroundValue);
  Color get foreground => Color(foregroundValue);
  Color get muted => Color(mutedValue);
  Color get accent => Color(accentValue);
  Color get secondary => Color.lerp(background, accent, .3)!;
  bool get isDark => background.computeLuminance() < .15;
  bool get hasCharacter =>
      identity != ReadingVisualTheme.shelf &&
      identity != ReadingVisualTheme.ink &&
      identity != ReadingVisualTheme.dawn;
}

ReadingExportTheme readingExportTheme(ReadingVisualTheme theme) =>
    switch (theme) {
      ReadingVisualTheme.archive => const ReadingExportTheme(
        identity: ReadingVisualTheme.archive,
        label: '阅读档案',
        description: '人物档案 · 书库索引',
        artAsset: 'assets/report/char_cover.webp',
        portraitArtAsset: 'assets/report/char_cover.webp',
        backgroundValue: 0xfff4f3ef,
        foregroundValue: 0xff24312e,
        mutedValue: 0xff697670,
        accentValue: 0xff2a8178,
        previewAlignment: Alignment.topRight,
      ),
      ReadingVisualTheme.shelf => const ReadingExportTheme(
        identity: ReadingVisualTheme.shelf,
        label: '雾港书页',
        description: '雾港场景 · 冷灰书页',
        artAsset: 'assets/report/scene_mist_harbor.webp',
        portraitArtAsset: 'assets/report/scene_mist_harbor_portrait.webp',
        backgroundValue: 0xff141e26,
        foregroundValue: 0xffe5ece9,
        mutedValue: 0xffa5b5ba,
        accentValue: 0xff8db9b0,
        previewAlignment: Alignment.center,
      ),
      ReadingVisualTheme.editorial => const ReadingExportTheme(
        identity: ReadingVisualTheme.editorial,
        label: '四季手帐',
        description: '四季风景 · 阅读手帖',
        artAsset: 'assets/report/char_season_spring.webp',
        portraitArtAsset: 'assets/report/char_season_spring.webp',
        backgroundValue: 0xfff2efe8,
        foregroundValue: 0xff373831,
        mutedValue: 0xff817c6d,
        accentValue: 0xff7b8d62,
        prefersSerif: true,
      ),
      ReadingVisualTheme.constellation => const ReadingExportTheme(
        identity: ReadingVisualTheme.constellation,
        label: '夜读之城',
        description: '台灯夜色 · 阅读时钟',
        artAsset: 'assets/report/char_night_desk.webp',
        portraitArtAsset: 'assets/report/char_night_desk.webp',
        backgroundValue: 0xff0e1116,
        foregroundValue: 0xffece5d4,
        mutedValue: 0xff969c9f,
        accentValue: 0xffd9b66f,
        previewAlignment: Alignment(1, -.05),
      ),
      ReadingVisualTheme.signal => const ReadingExportTheme(
        identity: ReadingVisualTheme.signal,
        label: '纸上回声',
        description: '黑白剪纸 · 纸鸟回声',
        artAsset: 'assets/report/char_papercut.webp',
        portraitArtAsset: 'assets/report/char_papercut.webp',
        backgroundValue: 0xff272727,
        foregroundValue: 0xfff2efe7,
        mutedValue: 0xffb4b3aa,
        accentValue: 0xffdad5c7,
        previewAlignment: Alignment.topRight,
      ),
      ReadingVisualTheme.score => const ReadingExportTheme(
        identity: ReadingVisualTheme.score,
        label: '三幕放映',
        description: '胶片三幕 · 书页放映',
        artAsset: 'assets/report/char_pv_open.webp',
        portraitArtAsset: 'assets/report/char_pv_open.webp',
        backgroundValue: 0xff0b0c0e,
        foregroundValue: 0xffeee4ce,
        mutedValue: 0xff8d939a,
        accentValue: 0xffb99a6b,
      ),
      ReadingVisualTheme.ink => const ReadingExportTheme(
        identity: ReadingVisualTheme.ink,
        label: '远山晨光',
        description: '远山晨光 · 暖纸留白',
        artAsset: 'assets/report/scene_mountain_dawn.webp',
        portraitArtAsset: 'assets/report/scene_mountain_dawn_portrait.webp',
        backgroundValue: 0xfff5f0e6,
        foregroundValue: 0xff303b34,
        mutedValue: 0xff6e796e,
        accentValue: 0xff9d704d,
        previewAlignment: Alignment.center,
        prefersSerif: true,
      ),
      ReadingVisualTheme.festival => const ReadingExportTheme(
        identity: ReadingVisualTheme.festival,
        label: '晴空来信',
        description: '列车风景 · 旅途明信片',
        artAsset: 'assets/report/char_pv_train.webp',
        portraitArtAsset: 'assets/report/char_pv_train.webp',
        backgroundValue: 0xffeff1e9,
        foregroundValue: 0xff273e47,
        mutedValue: 0xff697776,
        accentValue: 0xffb96f44,
      ),
      ReadingVisualTheme.autumn => const ReadingExportTheme(
        identity: ReadingVisualTheme.autumn,
        label: '秋叶书签',
        description: '金色落叶 · 树下静读',
        artAsset: 'assets/report/char_autumn_reading.webp',
        portraitArtAsset: 'assets/report/char_autumn_reading.webp',
        backgroundValue: 0xfff8f1e4,
        foregroundValue: 0xff2d241b,
        mutedValue: 0xff7f6a51,
        accentValue: 0xffb96e35,
        previewAlignment: Alignment.centerRight,
      ),
      ReadingVisualTheme.twilight => const ReadingExportTheme(
        identity: ReadingVisualTheme.twilight,
        label: '黄昏列车',
        description: '暮色车窗 · 旅途书简',
        artAsset: 'assets/report/char_twilight_train.webp',
        portraitArtAsset: 'assets/report/char_twilight_train.webp',
        backgroundValue: 0xfffaece1,
        foregroundValue: 0xff33241f,
        mutedValue: 0xff805d4d,
        accentValue: 0xffd27943,
        previewAlignment: Alignment.center,
      ),
      ReadingVisualTheme.dawn => const ReadingExportTheme(
        identity: ReadingVisualTheme.dawn,
        label: '晨山云海',
        description: '云海晨光 · 山间书斋',
        artAsset: 'assets/report/scene_dawn_study.webp',
        portraitArtAsset: 'assets/report/scene_dawn_study.webp',
        backgroundValue: 0xffedf5f6,
        foregroundValue: 0xff24363a,
        mutedValue: 0xff61787a,
        accentValue: 0xff4e8c86,
        previewAlignment: Alignment.center,
        prefersSerif: true,
      ),
      ReadingVisualTheme.spring => const ReadingExportTheme(
        identity: ReadingVisualTheme.spring,
        label: '春雨窗边',
        description: '细雨新绿 · 窗前阅读',
        artAsset: 'assets/report/char_spring_rain.webp',
        portraitArtAsset: 'assets/report/char_spring_rain.webp',
        backgroundValue: 0xfff0f5ed,
        foregroundValue: 0xff26352a,
        mutedValue: 0xff687b6a,
        accentValue: 0xff5f8a5e,
        previewAlignment: Alignment.centerRight,
      ),
    };
