import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full-screen, low-contrast artwork that sits behind every scaffold. The
/// patterns are paint geometry, so no image decoding, blur pass or ticker is
/// added to scrolling pages.
enum AppBackdrop {
  none('纯色'),
  paper('纸境'),
  blossom('花影'),
  rain('雨窗'),
  starlight('星海'),
  forest('森屿'),
  neon('霓线');

  const AppBackdrop(this.label);
  final String label;

  String get description => switch (this) {
    AppBackdrop.none => '只保留当前配色，不额外绘制图案。',
    AppBackdrop.paper => '细纸纹、折角和装订线，安静但不再是一块纯色。',
    AppBackdrop.blossom => '枝影与花瓣，适合浅色和春日主题。',
    AppBackdrop.rain => '斜雨、玻璃水痕和窗框，阅读页也保留。',
    AppBackdrop.starlight => '星点、轨道与星座连线，深色下更明显。',
    AppBackdrop.forest => '叶影和树干围在页面边缘，不压正文。',
    AppBackdrop.neon => '透视网格与荧光块，适合赛博配色。',
  };

  static AppBackdrop parse(Object? value) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value) return item;
      }
    }
    return AppBackdrop.none;
  }
}

@immutable
class AppBackdropStyle extends ThemeExtension<AppBackdropStyle> {
  const AppBackdropStyle({
    required this.backdrop,
    required this.ink,
    required this.accent,
    required this.secondary,
    required this.dark,
  });

  final AppBackdrop backdrop;
  final Color ink, accent, secondary;
  final bool dark;

  @override
  AppBackdropStyle copyWith({
    AppBackdrop? backdrop,
    Color? ink,
    Color? accent,
    Color? secondary,
    bool? dark,
  }) => AppBackdropStyle(
    backdrop: backdrop ?? this.backdrop,
    ink: ink ?? this.ink,
    accent: accent ?? this.accent,
    secondary: secondary ?? this.secondary,
    dark: dark ?? this.dark,
  );

  @override
  AppBackdropStyle lerp(AppBackdropStyle? other, double t) {
    if (other == null) return this;
    return AppBackdropStyle(
      backdrop: t < .5 ? backdrop : other.backdrop,
      ink: Color.lerp(ink, other.ink, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      dark: t < .5 ? dark : other.dark,
    );
  }
}

/// A static layer. [strength] lets the reader keep the artwork quieter than
/// the surrounding app while preserving the same theme.
class AppBackdropLayer extends StatelessWidget {
  const AppBackdropLayer({
    super.key,
    required this.style,
    this.strength = 1,
    this.child,
  });

  final AppBackdropStyle style;
  final double strength;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (style.backdrop == AppBackdrop.none) {
      return child ?? const SizedBox.expand();
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _BackdropPainter(style, strength.clamp(0, 1)),
            child: child ?? const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.style, this.strength);
  final AppBackdropStyle style;
  final double strength;

  double get _alpha => (style.dark ? .16 : .12) * strength;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style.backdrop) {
      case AppBackdrop.paper:
        _paper(canvas, size);
      case AppBackdrop.blossom:
        _blossom(canvas, size);
      case AppBackdrop.rain:
        _rain(canvas, size);
      case AppBackdrop.starlight:
        _starlight(canvas, size);
      case AppBackdrop.forest:
        _forest(canvas, size);
      case AppBackdrop.neon:
        _neon(canvas, size);
      case AppBackdrop.none:
        break;
    }
  }

  Paint _paint(Color color, double opacity, {double width = 1}) => Paint()
    ..color = color.withValues(alpha: opacity)
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;

  void _paper(Canvas canvas, Size size) {
    final ink = style.ink;
    final line = _paint(ink, _alpha * .42, width: .6);
    for (var y = 28.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var x = 24.0; x < size.width; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    final margin = _paint(style.accent, _alpha * .34, width: 1.1);
    final left = size.width * .055;
    final right = size.width * .945;
    canvas.drawLine(Offset(left, 0), Offset(left, size.height), margin);
    canvas.drawLine(Offset(right, 0), Offset(right, size.height), margin);
    final fold = _paint(style.secondary, _alpha * .55, width: 1);
    for (final corner in [Offset(0, 0), Offset(size.width, size.height)]) {
      final dx = corner.dx == 0 ? 1.0 : -1.0;
      final dy = corner.dy == 0 ? 1.0 : -1.0;
      const length = 58.0;
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx + dx * length, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + dy * length),
        fold,
      );
    }
  }

  void _blossom(Canvas canvas, Size size) {
    final branch = _paint(style.ink, _alpha * .44, width: 1.4);
    final twig = _paint(style.ink, _alpha * .3, width: .8);
    final top = Path()
      ..moveTo(size.width * .52, -12)
      ..cubicTo(
        size.width * .64,
        size.height * .08,
        size.width * .82,
        size.height * .03,
        size.width + 12,
        size.height * .11,
      );
    canvas.drawPath(top, branch);
    final bottom = Path()
      ..moveTo(-12, size.height * .78)
      ..cubicTo(
        size.width * .12,
        size.height * .67,
        size.width * .18,
        size.height * .9,
        size.width * .3,
        size.height + 12,
      );
    canvas.drawPath(bottom, branch);
    for (var i = 0; i < 9; i++) {
      final x = size.width * (.58 + i * .045);
      final y = size.height * (.04 + (i % 3) * .035);
      canvas.drawLine(Offset(x, y), Offset(x + 24, y - 18 - (i % 4) * 7), twig);
    }
    final petal = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 22; i++) {
      final x = size.width * ((i * .618) % 1);
      final y = size.height * (((i * .414) + .11) % .92);
      final r = 2.2 + (i % 4) * .9;
      petal.color = (i.isEven ? style.accent : style.secondary).withValues(
        alpha: _alpha * (i.isEven ? .48 : .3),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i * .7);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2.4, height: r * 1.15),
        petal,
      );
      canvas.restore();
    }
  }

  void _rain(Canvas canvas, Size size) {
    final rain = _paint(style.ink, _alpha * .42, width: .8);
    for (var i = -20; i < 40; i++) {
      final x = i * 46.0 + (i.isEven ? 12 : 0);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height * .18, size.height),
        rain,
      );
    }
    final frame = _paint(style.secondary, _alpha * .55, width: 1.2);
    canvas.drawLine(
      Offset(size.width * .5, 0),
      Offset(size.width * .5, size.height),
      frame,
    );
    canvas.drawLine(
      Offset(0, size.height * .32),
      Offset(size.width, size.height * .32),
      frame,
    );
    final drop = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 14; i++) {
      final x = size.width * (((i * .37) + .08) % .94);
      final y = size.height * ((i * .23 + .06) % .9);
      drop.color = style.secondary.withValues(alpha: _alpha * .2);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 5, height: 11),
        drop,
      );
    }
  }

  void _starlight(Canvas canvas, Size size) {
    final orbit = _paint(style.accent, _alpha * .3, width: .9);
    final r = math.min(size.width, size.height) * .31;
    canvas.drawCircle(Offset(size.width * .76, size.height * .18), r, orbit);
    canvas.drawCircle(
      Offset(size.width * .76, size.height * .18),
      r * .62,
      _paint(style.secondary, _alpha * .22, width: .7),
    );
    final dot = Paint()..style = PaintingStyle.fill;
    final line = _paint(style.accent, _alpha * .28, width: .8);
    final points = <Offset>[
      for (var i = 0; i < 17; i++)
        Offset(
          size.width * ((i * .618 + .07) % .98),
          size.height * ((i * .382 + .03) % .94),
        ),
    ];
    for (var i = 0; i < points.length - 1; i += 2) {
      canvas.drawLine(points[i], points[i + 1], line);
    }
    for (var i = 0; i < points.length; i++) {
      final radius = i % 5 == 0 ? 2.3 : 1.1;
      dot.color = (i % 3 == 0 ? style.accent : style.ink).withValues(
        alpha: _alpha * .52,
      );
      canvas.drawCircle(points[i], radius, dot);
    }
  }

  void _forest(Canvas canvas, Size size) {
    final trunk = _paint(style.ink, _alpha * .25, width: 3);
    for (var i = 0; i < 4; i++) {
      final x = size.width * (.04 + i * .055);
      canvas.drawLine(Offset(x, 0), Offset(x + 14 + i * 4, size.height), trunk);
    }
    final leaf = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 15; i++) {
      final left = i.isEven;
      final x = left
          ? size.width * ((i % 5) * .035 + .015)
          : size.width * (1 - (i % 5) * .035 - .015);
      final y = size.height * ((i * .173 + .08) % .9);
      leaf.color = (i % 3 == 0 ? style.accent : style.secondary).withValues(
        alpha: _alpha * .34,
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(left ? -.55 : .55);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 26, height: 11),
        leaf,
      );
      canvas.restore();
    }
  }

  void _neon(Canvas canvas, Size size) {
    final grid = _paint(style.accent, _alpha * .38, width: .8);
    final horizon = size.height * .62;
    for (var i = -12; i <= 12; i++) {
      final x = size.width * .5 + i * size.width * .08;
      canvas.drawLine(
        Offset(size.width * .5, horizon),
        Offset(x, size.height),
        grid,
      );
    }
    for (var i = 0; i < 10; i++) {
      final t = i / 9;
      final y = horizon + math.pow(t, 2) * (size.height - horizon);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final glow = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 5; i++) {
      final x = size.width * (.08 + i * .21);
      final y = size.height * (.12 + (i % 3) * .07);
      glow.color = (i.isEven ? style.accent : style.secondary).withValues(
        alpha: _alpha * .22,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 22, 4.5),
          const Radius.circular(2),
        ),
        glow,
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.style.backdrop != style.backdrop ||
      old.style.ink != style.ink ||
      old.style.accent != style.accent ||
      old.style.secondary != style.secondary ||
      old.style.dark != style.dark ||
      old.strength != strength;
}
