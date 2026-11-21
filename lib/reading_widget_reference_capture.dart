import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

export 'reading_widget_reference.dart';

/// In-memory capture helpers for the reference widget faces.
///
/// Widget controllers only import this library, so the re-export above keeps
/// [renderReadingDesktopCard] / [renderReadingDesktopCards] reachable without
/// pulling the renderer in twice. No file is written here: hosts decide where
/// the PNG bytes live so a failed publish cannot leave partial files behind.
class ReadingWidgetReferenceCapture {
  const ReadingWidgetReferenceCapture._();

  /// Captures every face a host can display, keyed by `<size>_<brightness>`.
  static Future<Map<String, Uint8List>> captureAll(
    ReadingWidgetSnapshot snapshot, {
    Iterable<ReadingDesktopSize> sizes = ReadingDesktopSize.values,
    Iterable<Brightness> brightnesses = Brightness.values,
    bool paintQuote = false,
    double pixelRatio = readingWidgetReferencePixelRatio,
  }) => renderReadingDesktopCards(
    snapshot,
    sizes: sizes,
    brightnesses: brightnesses,
    paintQuote: paintQuote,
    pixelRatio: pixelRatio,
  );

  /// Captures a single face, for previews or a host that only needs one size.
  static Future<Uint8List> capture(
    ReadingWidgetSnapshot snapshot,
    ReadingDesktopSize size, {
    Brightness brightness = Brightness.light,
    bool paintQuote = true,
    double pixelRatio = readingWidgetReferencePixelRatio,
  }) => renderReadingDesktopCard(
    snapshot,
    size,
    brightness: brightness,
    paintQuote: paintQuote,
    pixelRatio: pixelRatio,
  );

  /// Stable file name for one captured face.
  static String fileNameFor(ReadingDesktopSize size, Brightness brightness) =>
      '${size.name}_${brightness.name}.png';
}
