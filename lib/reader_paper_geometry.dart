import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// 一页纸张的三角网格：位置、法线、UV、索引与轮廓。
class ReaderPaperMesh {
  ReaderPaperMesh({
    required this.positions,
    required this.normals,
    required this.uv,
    required this.indices,
    required this.outline,
  });

  /// 每顶点两个分量（x, y）。
  final Float32List positions;

  /// 每顶点一个分量，用于明暗插值（此处以折痕距离近似）。
  final Float32List normals;

  /// 每顶点两个分量（u, v）。
  final Float32List uv;

  final Uint16List indices;
  final Path outline;
}

/// 翻页时的纸张几何：把页面按折痕分成正面与背面两块网格。
///
/// 原工程这一模块把真实纸张弯曲算成网格；这里给出等价接口的简化实现：
/// 折痕随 [progress] 从右向左移动，正反面各自生成一张平面网格，
/// 视觉上是干净的整页翻动，不做复杂的双面卷曲。
class ReaderPaperGeometry {
  factory ReaderPaperGeometry({
    required Size size,
    required double gap,
    required double progress,
    required double touchY,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final lift = math.sin(p * math.pi);
    final width = size.width <= 0 ? 1.0 : size.width;
    final fold = (width * (1 - p)).clamp(0.0, width);
    final front = _build(
      start: 0,
      end: fold,
      size: size,
      mirrorAt: null,
      bend: lift,
    );
    final back = _build(
      start: fold,
      end: width,
      size: size,
      mirrorAt: fold,
      bend: lift,
    );
    final sheet = Path()..addRect(Offset.zero & size);
    return ReaderPaperGeometry._(
      size: size,
      gap: gap,
      lift: lift,
      sheet: sheet,
      front: front,
      back: back,
      frontInk: front,
      backInk: back,
    );
  }

  ReaderPaperGeometry._({
    required this.size,
    required this.gap,
    required this.lift,
    required this.sheet,
    required this.front,
    required this.back,
    required this.frontInk,
    required this.backInk,
  });

  final Size size;
  final double gap;

  /// 翻页强度 0..1，0 表示没有抬起。
  final double lift;

  /// 整张纸面。
  final Path sheet;

  final ReaderPaperMesh front;
  final ReaderPaperMesh back;
  final ReaderPaperMesh frontInk;
  final ReaderPaperMesh backInk;

  static const _cols = 8;
  static const _rows = 10;

  static ReaderPaperMesh _build({
    required double start,
    required double end,
    required Size size,
    required double? mirrorAt,
    required double bend,
  }) {
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;
    final span = math.max(end - start, 0.001);
    const cols = _cols;
    const rows = _rows;
    final count = (cols + 1) * (rows + 1);
    final positions = Float32List(count * 2);
    final normals = Float32List(count);
    final uv = Float32List(count * 2);
    var index = 0;
    for (var row = 0; row <= rows; row++) {
      final v = row / rows;
      for (var col = 0; col <= cols; col++) {
        final u = col / cols;
        var x = start + span * u;
        if (mirrorAt != null) x = mirrorAt * 2 - x;
        // 轻微弧线，避免完全平直的观感。
        final arc = math.sin(u * math.pi) * bend * 6;
        final y = height * v + (mirrorAt != null ? arc : -arc) * (v - .5) * 2;
        positions[index] = x;
        positions[index + 1] = y;
        normals[index ~/ 2] = math.sin(u * math.pi) * bend;
        uv[index] = (x / width).clamp(0.0, 1.0);
        uv[index + 1] = v;
        index += 2;
      }
    }
    final indices = Uint16List(cols * rows * 6);
    var cursor = 0;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final a = row * (cols + 1) + col;
        final b = a + 1;
        final c = a + (cols + 1);
        final d = c + 1;
        indices[cursor++] = a;
        indices[cursor++] = b;
        indices[cursor++] = c;
        indices[cursor++] = b;
        indices[cursor++] = d;
        indices[cursor++] = c;
      }
    }
    final outline = Path()
      ..moveTo(positions[0], positions[1])
      ..lineTo(positions[(cols) * 2], positions[(cols) * 2 + 1])
      ..lineTo(
        positions[(rows * (cols + 1) + cols) * 2],
        positions[(rows * (cols + 1) + cols) * 2 + 1],
      )
      ..lineTo(
        positions[(rows * (cols + 1)) * 2],
        positions[(rows * (cols + 1)) * 2 + 1],
      )
      ..close();
    return ReaderPaperMesh(
      positions: positions,
      normals: normals,
      uv: uv,
      indices: indices,
      outline: outline,
    );
  }
}
