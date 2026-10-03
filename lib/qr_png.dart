import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'qr_encoding.dart';

/// Image size presets, as whole pixels per module.
///
/// Sized per module rather than per image so that a short URL makes a small file
/// and a dense vCard a large one, and so that every module edge lands on a pixel
/// boundary: a fixed image size divided by a module count leaves fractions, which
/// anti-aliasing smears into grey edges.
enum ImageSize {
  small('Small', 4),
  medium('Medium', 8),
  large('Large', 16),
  extraLarge('Extra large', 32);

  const ImageSize(this.label, this.pixelsPerModule);

  final String label;
  final int pixelsPerModule;

  /// Width and height of the image for [qr], quiet zone included.
  int pixelsFor(EncodedQr qr) =>
      (qr.moduleCount + quietZoneModules * 2) * pixelsPerModule;
}

/// The margin the spec requires on every side, in modules.
const quietZoneModules = 4;

/// Renders [qr] as a PNG suitable for saving or printing.
///
/// This deliberately does not reuse what is on screen. The preview is a widget
/// styled for the current theme, and two of those choices do not survive being
/// written to a file:
///
/// * `QrPainter` paints the modules and nothing else, so the background is
///   transparent. A transparent PNG dropped on a dark background is a QR code no
///   scanner can read, because the contrast it depends on is inverted.
/// * The spec requires a quiet zone of four modules on every side. On screen the
///   surrounding padding provides it; in a file, whatever the image is pasted
///   onto does, which is to say nothing.
///
/// So the code is always painted black on white with its own margin, whatever
/// the app's theme is doing.
Future<Uint8List> renderQrPng(
  EncodedQr qr, {
  ImageSize size = ImageSize.medium,
}) async {
  final unit = size.pixelsPerModule;
  final side = size.pixelsFor(qr);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final dark = Paint()
    ..color = const Color(0xFF000000)
    ..isAntiAlias = false;
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.image.isDark(row, col)) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          ((col + quietZoneModules) * unit).toDouble(),
          ((row + quietZoneModules) * unit).toDouble(),
          unit.toDouble(),
          unit.toDouble(),
        ),
        dark,
      );
    }
  }

  final image = await recorder.endRecording().toImage(side, side);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Encoding the QR code as a PNG produced no bytes.');
    }
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// A filename for [formatId] that sorts by when it was made: `qrious-wifi.png`
/// with a timestamp, so saving several in a row does not overwrite one file.
String qrFileName(String formatId, DateTime when) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${when.year}${two(when.month)}${two(when.day)}'
      '-${two(when.hour)}${two(when.minute)}${two(when.second)}';
  return 'qrious-$formatId-$stamp.png';
}
