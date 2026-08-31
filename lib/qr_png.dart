import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Renders [data] as a PNG suitable for saving or printing.
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
Future<Uint8List> renderQrPng(String data, {double size = 1024}) async {
  if (data.isEmpty) {
    throw ArgumentError.value(data, 'data', 'Cannot render an empty QR code.');
  }

  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  );

  // A twelfth of the image on each side is comfortably more than the four
  // modules the spec asks for, at every version the app can produce.
  final margin = size / 12;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.translate(margin, margin);
  painter.paint(canvas, Size(size - margin * 2, size - margin * 2));

  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
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
