import 'package:flutter/material.dart';

import 'reading_widget_snapshot.dart';

/// One light/dark colour set used by a [ReadingWidgetSkin].
class ReadingWidgetSkinColors {
  const ReadingWidgetSkinColors({
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.border,
  });

  final Color background;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color border;
}

/// The decorative motif painted behind the reading facts of a card.
enum ReadingWidgetSkinPattern { plain, orbit, ruled, wash, constellation }

/// Appearance of the home-screen reading widget.
///
/// A skin never changes which reading facts a card shows; it only decides how
/// [ReadingDesktopCard] looks. Persisted values are [name]s, so the declaration
/// order may change without invalidating saved cards.
enum ReadingWidgetSkin {
  original(
    label: '原版',
    description: '素纸底色，接近系统桌面的安静默认值',
    light: ReadingWidgetSkinColors(
      background: Color(0xFFF6F3ED),
      surface: Color(0xFFFFFFFF),
      foreground: Color(0xFF23211D),
      muted: Color(0xFF807A6F),
      accent: Color(0xFF8A6A4C),
      border: Color(0x1F23211D),
    ),
    dark: ReadingWidgetSkinColors(
      background: Color(0xFF17171A),
      surface: Color(0xFF212124),
      foreground: Color(0xFFF3F0E9),
      muted: Color(0xFF9C968C),
      accent: Color(0xFFD2B189),
      border: Color(0x2EF3F0E9),
    ),
  ),
  seasons(
    label: '四季',
    description: '暖纸渐变配一轮季候光斑，最像手帐封面',
    light: ReadingWidgetSkinColors(
      background: Color(0xFFF5EFE3),
      surface: Color(0xFFFBF6EC),
      foreground: Color(0xFF2A241C),
      muted: Color(0xFF8A7B66),
      accent: Color(0xFFB5713C),
      border: Color(0x248A7B66),
    ),
    dark: ReadingWidgetSkinColors(
      background: Color(0xFF1C1915),
      surface: Color(0xFF26221B),
      foreground: Color(0xFFF5EEDF),
      muted: Color(0xFFA6977F),
      accent: Color(0xFFDD9A5C),
      border: Color(0x30F5EEDF),
    ),
    pattern: ReadingWidgetSkinPattern.orbit,
    usesGradient: true,
    cornerRadius: 22,
  ),
  paper(
    label: '纸页',
    description: '横线稿纸与墨绿字迹，适合长时间阅读',
    light: ReadingWidgetSkinColors(
      background: Color(0xFFFBFAF5),
      surface: Color(0xFFFFFFFF),
      foreground: Color(0xFF22241F),
      muted: Color(0xFF7C8172),
      accent: Color(0xFF4F6B54),
      border: Color(0x1F22241F),
    ),
    dark: ReadingWidgetSkinColors(
      background: Color(0xFF1A1B17),
      surface: Color(0xFF23241F),
      foreground: Color(0xFFF1F1E8),
      muted: Color(0xFF9EA293),
      accent: Color(0xFF9AC0A0),
      border: Color(0x2BF1F1E8),
    ),
    pattern: ReadingWidgetSkinPattern.ruled,
    cornerRadius: 10,
  ),
  ink(
    label: '水墨',
    description: '冷灰渐层和水痕，让数字安静下来',
    light: ReadingWidgetSkinColors(
      background: Color(0xFFF1F4F6),
      surface: Color(0xFFE6ECEF),
      foreground: Color(0xFF1D262B),
      muted: Color(0xFF6C7C85),
      accent: Color(0xFF2F6C8E),
      border: Color(0x241D262B),
    ),
    dark: ReadingWidgetSkinColors(
      background: Color(0xFF0F1417),
      surface: Color(0xFF182126),
      foreground: Color(0xFFE9F1F5),
      muted: Color(0xFF90A2AC),
      accent: Color(0xFF7DB6D8),
      border: Color(0x2EE9F1F5),
    ),
    pattern: ReadingWidgetSkinPattern.wash,
    usesGradient: true,
    cornerRadius: 18,
  ),
  moss(
    label: '苔原',
    description: '浅绿底色，读书进度像一层新苔',
    light: ReadingWidgetSkinColors(
      background: Color(0xFFF0F3E9),
      surface: Color(0xFFF8FAF2),
      foreground: Color(0xFF202A1C),
      muted: Color(0xFF77836A),
      accent: Color(0xFF567A3E),
      border: Color(0x1F202A1C),
    ),
    dark: ReadingWidgetSkinColors(
      background: Color(0xFF12160F),
      surface: Color(0xFF1C2118),
      foreground: Color(0xFFEFF3E4),
      muted: Color(0xFF9BA98A),
      accent: Color(0xFFA9C77C),
      border: Color(0x2EEFF3E4),
    ),
    usesGradient: true,
    cornerRadius: 18,
  ),
  night(
    label: '夜读',
    description: '深蓝夜色与细小星点，睡前也看得清',
    light: ReadingWidgetSkinColors(
      background: Color(0xFFEDECF3),
      surface: Color(0xFFF6F5FA),
      foreground: Color(0xFF232232),
      muted: Color(0xFF7B7890),
      accent: Color(0xFF6B5CB8),
      border: Color(0x1F232232),
    ),
    dark: ReadingWidgetSkinColors(
      background: Color(0xFF0D0D14),
      surface: Color(0xFF17161F),
      foreground: Color(0xFFEDEAF8),
      muted: Color(0xFF9793AC),
      accent: Color(0xFFB0A2F0),
      border: Color(0x30EDEAF8),
    ),
    pattern: ReadingWidgetSkinPattern.constellation,
    usesGradient: true,
    cornerRadius: 24,
  );

  const ReadingWidgetSkin({
    required this.label,
    required this.description,
    required this.light,
    required this.dark,
    this.pattern = ReadingWidgetSkinPattern.plain,
    this.usesGradient = false,
    this.cornerRadius = 16,
  });

  final String label;
  final String description;
  final ReadingWidgetSkinColors light;
  final ReadingWidgetSkinColors dark;
  final ReadingWidgetSkinPattern pattern;
  final bool usesGradient;
  final double cornerRadius;

  /// Saved preferences only store [name]s; unknown or legacy values fall back to
  /// the plain skin instead of dropping the user's card.
  static ReadingWidgetSkin fromId(String? value) {
    final id = value?.trim().toLowerCase();
    if (id == null || id.isEmpty) return ReadingWidgetSkin.original;
    for (final skin in ReadingWidgetSkin.values) {
      if (skin.name == id) return skin;
    }
    return ReadingWidgetSkin.original;
  }

  ReadingWidgetSkinColors colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Upper bound accepted for [ReadingWidgetSnapshot.dailyGoalMinutes].
const int readingWidgetMaxDailyGoalMinutes = 1440;

/// Normalizes a stored goal: zero means "no goal", anything above a day is
/// clamped so a corrupted preference cannot break layout or progress ratios.
int readingDailyGoal(int? value) {
  if (value == null || value <= 0) return 0;
  return value > readingWidgetMaxDailyGoalMinutes
      ? readingWidgetMaxDailyGoalMinutes
      : value;
}

/// One-line goal description shared by the settings page and widget cards.
String readingGoalCaption(int dailyGoalMinutes, int? verifiedTodaySeconds) {
  final goal = readingDailyGoal(dailyGoalMinutes);
  if (goal <= 0) return '按自己的节奏阅读';
  final today = verifiedTodaySeconds;
  if (today == null) return '目标 $goal 分钟 · 今日尚未记录';
  if (today >= goal * 60) return '今日已完成 $goal 分钟目标';
  return '今日 ${widgetMinutes(today)} / $goal 分钟';
}

/// A human readable duration. Minute precision mirrors the native widgets.
String readingWidgetDurationLabel(int seconds) {
  if (seconds <= 0) return '0 分钟';
  if (seconds < 60) return '<1 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}

/// Widget families a card can be rendered for. Widths follow the native
/// launcher cells: 2x2, 4x2 and 4x4 at the 364pt reference grid.
enum ReadingDesktopSize {
  small(
    label: '小 2×2',
    description: '方形小卡，只放一个数字',
    columns: 2,
    rows: 2,
    width: 170,
    height: 170,
    contentScale: 0.78,
    padding: 14,
  ),
  medium(
    label: '中 4×2',
    description: '横向卡片，信息最完整',
    columns: 4,
    rows: 2,
    width: 364,
    height: 170,
    contentScale: 1,
    padding: 18,
  ),
  large(
    label: '大 4×4',
    description: '方形大卡，展开一周与日历',
    columns: 4,
    rows: 4,
    width: 364,
    height: 364,
    contentScale: 1.16,
    padding: 22,
  );

  const ReadingDesktopSize({
    required this.label,
    required this.description,
    required this.columns,
    required this.rows,
    required this.width,
    required this.height,
    required this.contentScale,
    required this.padding,
  });

  final String label;
  final String description;
  final int columns;
  final int rows;
  final double width;
  final double height;
  final double contentScale;
  final double padding;

  Size get size => Size(width, height);

  double get aspectRatio => width / height;

  bool get isCompact => this == ReadingDesktopSize.small;

  bool get isSquare => columns == rows;

  EdgeInsets get insets => EdgeInsets.all(padding);

  double get radiusScale => isCompact ? 0.8 : (isSquare ? 1.08 : 1);

  static ReadingDesktopSize fromId(String? value) {
    final id = value?.trim().toLowerCase();
    for (final size in ReadingDesktopSize.values) {
      if (size.name == id) return size;
    }
    return ReadingDesktopSize.medium;
  }
}

/// A rendered home-screen card preview.
///
/// The card is a fixed-size surface: the settings page embeds it through a
/// [FittedBox], and the widget renderer paints the very same surface off-screen
/// through [ReadingDesktopCardPainter]. Factual content comes from [data]; the
/// quote fields are only used by the quote design.
class ReadingDesktopCard extends StatelessWidget {
  const ReadingDesktopCard({
    super.key,
    required this.data,
    this.size = ReadingDesktopSize.medium,
    this.brightness = Brightness.light,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
    this.paintQuote = true,
  });

  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  final Brightness brightness;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;
  final bool paintQuote;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Semantics(
          label: _semanticsLabel(),
          container: true,
          child: CustomPaint(
            painter: ReadingDesktopCardPainter(
              data: data,
              size: size,
              brightness: brightness,
              paintQuote: paintQuote,
              quoteText: quoteText,
              quoteSource: quoteSource,
              quoteCount: quoteCount,
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel() {
    final today = data.verifiedTodaySeconds;
    final streak = data.qualifiedStreakDays;
    final parts = <String>[
      '${data.design.label}桌面小组件',
      size.label,
      if (today != null) '今日 ${widgetMinutes(today)} 分钟',
      if (streak != null && streak > 0) '连续 $streak 天',
    ];
    return parts.join('，');
  }
}

/// Paints a [ReadingDesktopCard] surface. Kept separate from the widget so the
/// PNG renderer and the on-screen preview cannot drift apart.
class ReadingDesktopCardPainter extends CustomPainter {
  ReadingDesktopCardPainter({
    required this.data,
    required this.size,
    required this.brightness,
    this.paintQuote = true,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
  });

  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  final Brightness brightness;
  final bool paintQuote;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;

  static const _weekdayLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

  ReadingWidgetSkin get skin => data.skin;

  ReadingWidgetSkinColors get colors => skin.colorsFor(brightness);

  double get scale => size.contentScale;

  int get _footerMaxLines => size.isCompact ? 1 : 2;

  TextStyle get _footerStyle => TextStyle(
    color: colors.muted,
    fontSize: 9.5 * scale,
    height: 1.25,
    letterSpacing: 0.2,
  );

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final rect = Offset.zero & canvasSize;
    final card = RRect.fromRectAndRadius(
      rect,
      Radius.circular(skin.cornerRadius * size.radiusScale),
    );
    canvas.save();
    canvas.clipRRect(card);
    _paintBackground(canvas, rect);
    _paintPattern(canvas, rect);
    _paintContent(canvas, rect);
    canvas.restore();
    canvas.drawRRect(
      card.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.border,
    );
  }

  @override
  bool shouldRepaint(ReadingDesktopCardPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.size != size ||
      oldDelegate.brightness != brightness ||
      oldDelegate.paintQuote != paintQuote ||
      oldDelegate.quoteText != quoteText ||
      oldDelegate.quoteSource != quoteSource ||
      oldDelegate.quoteCount != quoteCount;

  void _paintBackground(Canvas canvas, Rect rect) {
    final paint = Paint();
    if (skin.usesGradient) {
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[colors.background, colors.surface],
      ).createShader(rect);
    } else {
      paint.color = colors.background;
    }
    canvas.drawRect(rect, paint);
  }

  void _paintPattern(Canvas canvas, Rect rect) {
    final pattern = skin.pattern;
    if (pattern == ReadingWidgetSkinPattern.orbit) {
      final center = Offset(rect.width * 0.88, rect.height * 0.04);
      canvas.drawCircle(
        center,
        rect.width * 0.34,
        Paint()..color = colors.accent.withValues(alpha: 0.09),
      );
      canvas.drawCircle(
        center,
        rect.width * 0.34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colors.accent.withValues(alpha: 0.16),
      );
      return;
    }
    if (pattern == ReadingWidgetSkinPattern.ruled) {
      final line = Paint()
        ..color = colors.foreground.withValues(alpha: 0.05)
        ..strokeWidth = 1;
      final gap = 18.0 * scale;
      for (var y = rect.top + gap; y < rect.bottom; y += gap) {
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
      }
      return;
    }
    if (pattern == ReadingWidgetSkinPattern.wash) {
      final path = Path()
        ..moveTo(rect.width * 0.52, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.bottom * 0.62)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = colors.accent.withValues(alpha: 0.08),
      );
      return;
    }
    if (pattern == ReadingWidgetSkinPattern.constellation) {
      final star = Paint()..color = colors.accent.withValues(alpha: 0.4);
      for (var index = 0; index < 16; index++) {
        final x = rect.left + rect.width * ((index * 37 % 97) / 97);
        final y = rect.top + rect.height * ((index * 61 % 89) / 89);
        final radius = (index.isEven ? 1.2 : 0.8) * scale;
        canvas.drawCircle(Offset(x, y), radius, star);
      }
    }
  }

  void _paintContent(Canvas canvas, Rect rect) {
    final padding = size.insets;
    final content = Rect.fromLTRB(
      rect.left + padding.left,
      rect.top + padding.top,
      rect.right - padding.right,
      rect.bottom - padding.bottom,
    );
    if (content.width <= 0 || content.height <= 0) return;
    final headerHeight = _paintHeader(canvas, content);
    final gap = 7.0 * scale;
    final footerHeight = _measureFooter(content.width);
    final body = Rect.fromLTRB(
      content.left,
      content.top + headerHeight + gap,
      content.right,
      content.bottom - footerHeight - gap,
    );
    if (body.height > 0) {
      canvas.save();
      canvas.clipRect(body);
      _paintBody(canvas, body);
      canvas.restore();
    }
    _paintFooter(
      canvas,
      Rect.fromLTRB(
        content.left,
        content.bottom - footerHeight,
        content.right,
        content.bottom,
      ),
    );
  }

  double _paintHeader(Canvas canvas, Rect content) {
    final style = TextStyle(
      color: colors.muted,
      fontSize: 10.0 * scale,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1 * scale,
      height: 1,
    );
    final label = _layout(
      _ellipsis(data.design.label, size.isCompact ? 6 : 10),
      style,
      maxWidth: content.width * 0.58,
    );
    label.paint(canvas, content.topLeft);
    final labelHeight = label.height;
    label.dispose();
    final trailing = _layout(
      _headerTrailing(),
      style.copyWith(letterSpacing: 0.3 * scale),
      maxWidth: content.width * 0.40,
    );
    trailing.paint(canvas, Offset(content.right - trailing.width, content.top));
    final trailingHeight = trailing.height;
    trailing.dispose();
    return labelHeight > trailingHeight ? labelHeight : trailingHeight;
  }

  String _headerTrailing() {
    final design = data.design.name;
    if (design == 'quote' && quoteCount > 1) return '共 $quoteCount 条';
    final streak = data.qualifiedStreakDays;
    if (streak != null && streak > 0) return '连续 $streak 天';
    final day = data.localDay;
    return '${day.month} 月 ${day.day} 日';
  }

  void _paintBody(Canvas canvas, Rect body) {
    final design = data.design.name;
    if (design == 'focus') {
      _paintFocus(canvas, body);
    } else if (design == 'week') {
      _paintWeek(canvas, body);
    } else if (design == 'calendar') {
      _paintCalendar(canvas, body);
    } else if (design == 'memory') {
      _paintMemory(canvas, body);
    } else if (design == 'quote') {
      _paintQuote(canvas, body);
    } else {
      _paintClassic(canvas, body);
    }
  }

  void _paintFocus(Canvas canvas, Rect body) {
    final today = data.verifiedTodaySeconds;
    final number = _layout(
      widgetMinutes(today),
      TextStyle(
        color: colors.foreground,
        fontSize: 30.0 * scale,
        fontWeight: FontWeight.w600,
        height: 1,
        letterSpacing: -0.6 * scale,
      ),
      maxWidth: body.width,
    );
    number.paint(canvas, body.topLeft);
    final numberHeight = number.height;
    final numberWidth = number.width;
    number.dispose();
    final unit = _layout(
      '分钟',
      TextStyle(
        color: colors.muted,
        fontSize: 10.5 * scale,
        fontWeight: FontWeight.w500,
        height: 1,
      ),
      maxWidth: body.width,
    );
    final unitHeight = unit.height;
    unit.paint(
      canvas,
      Offset(
        body.left + numberWidth + 4.0 * scale,
        body.top + numberHeight - unitHeight - 3.0 * scale,
      ),
    );
    unit.dispose();
    final caption = _layout(
      today == null ? '今日尚未记录' : '今日阅读',
      TextStyle(
        color: colors.muted,
        fontSize: 10.0 * scale,
        height: 1.2,
        letterSpacing: 0.2,
      ),
      maxWidth: body.width,
    );
    final captionHeight = caption.height;
    caption.paint(
      canvas,
      Offset(body.left, body.top + numberHeight + 3.0 * scale),
    );
    caption.dispose();
    var contentBottom = body.top + numberHeight + captionHeight + 3.0 * scale;
    final book = data.showBookDetails ? data.currentBook : null;
    if (book != null) {
      final title = _layout(
        _ellipsis(book.title, size.isCompact ? 10 : 22),
        TextStyle(
          color: colors.foreground,
          fontSize: 11.5 * scale,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        maxWidth: body.width,
      );
      final titleTop = contentBottom + 7.0 * scale;
      if (titleTop + title.height <= body.bottom) {
        title.paint(canvas, Offset(body.left, titleTop));
        contentBottom = titleTop + title.height;
        title.dispose();
        final chapter = book.chapter.trim();
        if (chapter.isNotEmpty) {
          final chapterPainter = _layout(
            _ellipsis(chapter, size.isCompact ? 12 : 28),
            TextStyle(color: colors.muted, fontSize: 9.5 * scale, height: 1.25),
            maxWidth: body.width,
          );
          final chapterTop = contentBottom + 2.0 * scale;
          if (chapterTop + chapterPainter.height <= body.bottom) {
            chapterPainter.paint(canvas, Offset(body.left, chapterTop));
            contentBottom = chapterTop + chapterPainter.height;
          }
          chapterPainter.dispose();
        }
      } else {
        title.dispose();
      }
    }
    if (!size.isCompact) {
      _paintWeekStrip(canvas, body, contentBottom + 8.0 * scale);
    }
  }

  void _paintWeekStrip(Canvas canvas, Rect body, double top) {
    final available = body.bottom - top;
    if (available < 34.0 * scale) return;
    final maximum = body.height * 0.42;
    final height = available > maximum ? maximum : available;
    _paintWeek(
      canvas,
      Rect.fromLTRB(body.left, body.bottom - height, body.right, body.bottom),
    );
  }

  void _paintWeek(Canvas canvas, Rect body) {
    final days = data.week;
    if (days.isEmpty) return;
    var maxSeconds = 0;
    for (final day in days) {
      final seconds = day.verifiedSeconds;
      if (seconds != null && seconds > maxSeconds) maxSeconds = seconds;
    }
    final labelHeight = 11.0 * scale;
    final chartHeight = body.height - labelHeight - 3.0 * scale;
    if (chartHeight <= 0) return;
    final slot = body.width / days.length;
    final barWidth = (slot * 0.44).clamp(2.0, 14.0 * scale).toDouble();
    final radius = Radius.circular(barWidth / 2);
    final trackPaint = Paint()
      ..color = colors.foreground.withValues(alpha: 0.06);
    final fillPaint = Paint()..color = colors.accent;
    final softPaint = Paint()..color = colors.accent.withValues(alpha: 0.42);
    final labelStyle = TextStyle(
      color: colors.muted,
      fontSize: 8.5 * scale,
      height: 1,
    );
    for (var index = 0; index < days.length; index++) {
      final day = days[index];
      final centerX = body.left + slot * index + slot / 2;
      final left = centerX - barWidth / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, body.top, barWidth, chartHeight),
          radius,
        ),
        trackPaint,
      );
      final seconds = day.verifiedSeconds;
      if (seconds != null && seconds > 0 && maxSeconds > 0) {
        final ratio = (seconds / maxSeconds).clamp(0.08, 1.0).toDouble();
        final height = chartHeight * ratio;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              body.top + chartHeight - height,
              barWidth,
              height,
            ),
            radius,
          ),
          index == days.length - 1 ? fillPaint : softPaint,
        );
      }
      final label = _layout(
        _weekdayLabel(day.date.weekday),
        labelStyle,
        maxWidth: slot,
        textAlign: TextAlign.center,
      );
      label.paint(
        canvas,
        Offset(body.left + slot * index, body.top + chartHeight + 3.0 * scale),
      );
      label.dispose();
    }
  }

  void _paintCalendar(Canvas canvas, Rect body) {
    final values = data.heatmap.verifiedSeconds;
    final maxColumns = values.length ~/ 7;
    if (maxColumns <= 0) return;
    final wanted = size.isCompact
        ? 6
        : (size == ReadingDesktopSize.large ? 13 : 10);
    final columns = wanted < maxColumns ? wanted : maxColumns;
    final gap = 2.0 * scale;
    final byWidth = (body.width - gap * (columns - 1)) / columns;
    final byHeight = (body.height - gap * 6) / 7;
    final cell = byWidth < byHeight ? byWidth : byHeight;
    if (cell <= 0) return;
    final gridWidth = cell * columns + gap * (columns - 1);
    final gridHeight = cell * 7 + gap * 6;
    final left = body.left + (body.width - gridWidth) / 2;
    final top = body.top + (body.height - gridHeight) / 2;
    final start = values.length - columns * 7;
    for (var index = start; index < values.length; index++) {
      final local = index - start;
      final column = local ~/ 7;
      final row = local % 7;
      final rect = Rect.fromLTWH(
        left + column * (cell + gap),
        top + row * (cell + gap),
        cell,
        cell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.26)),
        Paint()..color = _heatColor(readingWidgetHeatLevel(values[index])),
      );
    }
  }

  Color _heatColor(int? level) {
    if (level == null) return colors.foreground.withValues(alpha: 0.06);
    const alphas = <double>[0.14, 0.30, 0.48, 0.68, 1.0];
    final index = level < 0
        ? 0
        : (level >= alphas.length ? alphas.length - 1 : level);
    return colors.accent.withValues(alpha: alphas[index]);
  }

  void _paintMemory(Canvas canvas, Rect body) {
    final completion = data.latestCompletion;
    final completedAt = completion?.completedAt;
    final title = completion?.title?.trim() ?? '';
    final author = completion?.author?.trim() ?? '';
    final headingText = title.isEmpty
        ? (completion == null ? '还没有读完的书' : '一次完成的阅读')
        : title;
    final spineWidth = 4.0 * scale;
    final heading = _layout(
      _ellipsis(headingText, size.isCompact ? 9 : 20),
      TextStyle(
        color: colors.foreground,
        fontSize: 14.5 * scale,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      maxWidth: body.width - spineWidth - 8.0 * scale,
      maxLines: 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.left,
          body.top + 1.0 * scale,
          spineWidth,
          heading.height,
        ),
        Radius.circular(spineWidth / 2),
      ),
      Paint()..color = colors.accent.withValues(alpha: 0.8),
    );
    heading.paint(
      canvas,
      Offset(body.left + spineWidth + 8.0 * scale, body.top),
    );
    final headingHeight = heading.height;
    heading.dispose();
    final parts = <String>[];
    if (completion != null) {
      parts.add(completion.finished ? '已读完' : '读到一半');
    }
    if (completedAt != null) {
      parts.add('${completedAt.month} 月 ${completedAt.day} 日');
    }
    if (author.isNotEmpty) parts.add(author);
    final status = _layout(
      parts.isEmpty ? '完成一次阅读后会出现在这里' : parts.join(' · '),
      TextStyle(color: colors.muted, fontSize: 9.5 * scale, height: 1.3),
      maxWidth: body.width - spineWidth - 8.0 * scale,
      maxLines: 2,
    );
    var statusTop = body.top + headingHeight + 6.0 * scale;
    if (statusTop + status.height > body.bottom) {
      statusTop = body.bottom - status.height;
    }
    if (statusTop >= body.top + headingHeight) {
      status.paint(
        canvas,
        Offset(body.left + spineWidth + 8.0 * scale, statusTop),
      );
    }
    status.dispose();
  }

  void _paintQuote(Canvas canvas, Rect body) {
    final mark = _layout(
      '“',
      TextStyle(
        color: colors.accent.withValues(alpha: 0.55),
        fontSize: 28.0 * scale,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
      maxWidth: body.width,
    );
    mark.paint(canvas, Offset(body.left - 1.0 * scale, body.top - 2.0 * scale));
    mark.dispose();
    if (!paintQuote) return;
    final textTop = body.top + 13.0 * scale;
    final provided = quoteText?.trim() ?? '';
    final text = provided.isEmpty ? _fallbackQuote() : provided;
    final painter = _layout(
      text,
      TextStyle(
        color: colors.foreground,
        fontSize: (size.isCompact ? 10.5 : 12.5) * scale,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: body.width,
      maxLines: size.isCompact ? 2 : 3,
    );
    painter.paint(canvas, Offset(body.left, textTop));
    painter.dispose();
    final source = quoteSource.trim();
    if (source.isEmpty) return;
    final sourcePainter = _layout(
      _ellipsis(source, size.isCompact ? 16 : 32),
      TextStyle(color: colors.muted, fontSize: 9.0 * scale, height: 1.2),
      maxWidth: body.width,
    );
    sourcePainter.paint(
      canvas,
      Offset(body.left, body.bottom - sourcePainter.height),
    );
    sourcePainter.dispose();
  }

  String _fallbackQuote() {
    if (data.showBookDetails) {
      final title = data.latestCompletion?.title?.trim() ?? '';
      if (title.isNotEmpty) return '《$title》还没有摘录';
    }
    return '在书里留下第一段摘录';
  }

  void _paintClassic(Canvas canvas, Rect body) {
    final total = data.verifiedTotalSeconds;
    final today = data.verifiedTodaySeconds;
    final streak = data.qualifiedStreakDays;
    final caption = _layout(
      '累计阅读',
      TextStyle(
        color: colors.muted,
        fontSize: 9.5 * scale,
        height: 1.2,
        letterSpacing: 0.6 * scale,
      ),
      maxWidth: body.width,
    );
    final captionHeight = caption.height;
    caption.paint(canvas, body.topLeft);
    caption.dispose();
    final headlineText = total == null
        ? '开始阅读后记录'
        : readingWidgetDurationLabel(total);
    final headline = _layout(
      headlineText,
      TextStyle(
        color: colors.foreground,
        fontSize: (total == null ? 12.5 : 23.0) * scale,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.2,
      ),
      maxWidth: body.width,
    );
    final headlineTop = body.top + captionHeight + 3.0 * scale;
    headline.paint(canvas, Offset(body.left, headlineTop));
    final headlineHeight = headline.height;
    headline.dispose();
    final stats = <String>[];
    if (today != null) stats.add('今日 ${widgetMinutes(today)} 分钟');
    if (streak != null && streak > 0) stats.add('连续 $streak 天');
    var contentBottom = headlineTop + headlineHeight;
    if (stats.isNotEmpty) {
      final statsPainter = _layout(
        stats.join(' · '),
        TextStyle(color: colors.muted, fontSize: 9.5 * scale, height: 1.25),
        maxWidth: body.width,
      );
      final statsTop = contentBottom + 5.0 * scale;
      if (statsTop + statsPainter.height <= body.bottom) {
        statsPainter.paint(canvas, Offset(body.left, statsTop));
        contentBottom = statsTop + statsPainter.height;
      }
      statsPainter.dispose();
    }
    if (!size.isCompact) {
      _paintWeekStrip(canvas, body, contentBottom + 10.0 * scale);
    }
  }

  double _measureFooter(double width) {
    final text = _layout(
      _footerText(),
      _footerStyle,
      maxWidth: width,
      maxLines: _footerMaxLines,
    );
    var height = text.height;
    text.dispose();
    if (readingDailyGoal(data.dailyGoalMinutes) > 0) {
      height += 3.0 * scale + 6.0 * scale;
    }
    return height;
  }

  void _paintFooter(Canvas canvas, Rect area) {
    final goal = readingDailyGoal(data.dailyGoalMinutes);
    var textTop = area.top;
    if (goal > 0) {
      final trackHeight = 3.0 * scale;
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(area.left, area.top, area.width, trackHeight),
        Radius.circular(trackHeight),
      );
      canvas.drawRRect(
        track,
        Paint()..color = colors.foreground.withValues(alpha: 0.08),
      );
      final today = data.verifiedTodaySeconds ?? 0;
      final progress = (today / (goal * 60)).clamp(0.0, 1.0).toDouble();
      if (progress > 0) {
        final fill = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            area.left,
            area.top,
            area.width * progress,
            trackHeight,
          ),
          Radius.circular(trackHeight),
        );
        canvas.drawRRect(fill, Paint()..color = colors.accent);
      }
      textTop = area.top + trackHeight + 6.0 * scale;
    }
    final text = _layout(
      _footerText(),
      _footerStyle,
      maxWidth: area.width,
      maxLines: _footerMaxLines,
    );
    text.paint(canvas, Offset(area.left, textTop));
    text.dispose();
  }

  String _footerText() {
    final goal = readingDailyGoal(data.dailyGoalMinutes);
    final today = data.verifiedTodaySeconds;
    if (goal > 0) return readingGoalCaption(goal, today);
    final total = data.verifiedTotalSeconds;
    if (total != null && total > 0) {
      return '累计阅读 ${readingWidgetDurationLabel(total)}';
    }
    if (today != null && today > 0) {
      return '今日已读 ${widgetMinutes(today)} 分钟';
    }
    return '开始阅读后，这里会出现你的记录';
  }

  String _weekdayLabel(int weekday) {
    final index = weekday - DateTime.monday;
    if (index < 0 || index >= _weekdayLabels.length) return '';
    return _weekdayLabels[index];
  }

  TextPainter _layout(
    String text,
    TextStyle style, {
    double? maxWidth,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    painter.layout(maxWidth: maxWidth ?? double.infinity);
    return painter;
  }
}

String _ellipsis(String value, int limit) {
  final trimmed = value.trim();
  if (limit <= 0) return '';
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit)}…';
}
