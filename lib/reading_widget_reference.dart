import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

/// Physical pixels per logical pixel for the PNG payloads. Native hosts ask for
/// the same three sizes at this scale, so one constant keeps them consistent.
const double readingWidgetReferencePixelRatio = 2.2;

/// Renders one card face to PNG bytes.
///
/// Painting is synchronous and deterministic; only the engine encode step is
/// awaited. The surface is painted from primitives through
/// [ReadingDesktopCardPainter], so a card needs no widget tree to be captured.
Future<Uint8List> renderReadingDesktopCard(
  ReadingWidgetSnapshot snapshot,
  ReadingDesktopSize size, {
  Brightness brightness = Brightness.light,
  bool paintQuote = true,
  String? quoteText,
  String quoteSource = '',
  int? quoteCount,
  double pixelRatio = readingWidgetReferencePixelRatio,
}) async {
  final logicalWidth = size.width;
  final logicalHeight = size.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, logicalWidth, logicalHeight),
  );
  canvas.scale(pixelRatio);
  ReadingDesktopCardPainter(
    data: snapshot,
    size: size,
    brightness: brightness,
    paintQuote: paintQuote,
    quoteText: quoteText,
    quoteSource: quoteSource,
    quoteCount: quoteCount ?? 0,
  ).paint(canvas, Size(logicalWidth, logicalHeight));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (logicalWidth * pixelRatio).round(),
      (logicalHeight * pixelRatio).round(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Reading widget PNG encoding returned no bytes');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Renders the whole size/brightness matrix a native host expects.
///
/// Keys match the host contract: `<size>_<brightness>`, for example
/// `medium_dark`. Quote text is deliberately not painted by default because
/// hosts composite the user's excerpts on top of this background layer.
Future<Map<String, Uint8List>> renderReadingDesktopCards(
  ReadingWidgetSnapshot snapshot, {
  Iterable<ReadingDesktopSize> sizes = ReadingDesktopSize.values,
  Iterable<Brightness> brightnesses = Brightness.values,
  bool paintQuote = false,
  String? quoteText,
  String quoteSource = '',
  int quoteCount = 0,
  double pixelRatio = readingWidgetReferencePixelRatio,
}) async {
  final images = <String, Uint8List>{};
  for (final size in sizes) {
    for (final brightness in brightnesses) {
      images['${size.name}_${brightness.name}'] =
          await renderReadingDesktopCard(
            snapshot,
            size,
            brightness: brightness,
            paintQuote: paintQuote,
            quoteText: quoteText,
            quoteSource: quoteSource,
            quoteCount: quoteCount,
            pixelRatio: pixelRatio,
          );
    }
  }
  return images;
}

/// Hooks the caller into whatever should be decoded before a render batch.
///
/// Reference cards are painted from primitives, so there is no image cache to
/// prime today: covers stay owned by the controller and the card paints
/// typography only. The call is kept so widget controllers can `await` a stable
/// future before drawing six faces.
Future<void> warmReadingDesktopImages(ReadingWidgetSnapshot snapshot) async {
  // Intentionally empty. The snapshot is fully validated by its constructor, so
  // touching it here would do no work the render pass does not repeat.
}
