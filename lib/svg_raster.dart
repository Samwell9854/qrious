import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

import 'qr_decoding.dart';

/// How long the longer side of the drawn image is, whatever size the SVG declares.
///
/// Large enough that a code's modules stay several pixels wide even in a dense
/// symbol, and small enough to decode quickly.
const _targetLongSide = 1200.0;

/// Used when the SVG declares no usable size at all.
const _fallbackSide = 100.0;

/// How much of the start of a file is searched for `<svg` after an XML prolog.
const _sniffLength = 1024;

/// Whether [bytes] look like an SVG document rather than a raster image.
///
/// Looks at the start only: past a UTF-8 BOM and whitespace, either `<svg`, or an
/// `<?xml` prolog with `<svg` somewhere in the first kilobyte (a doctype or a
/// comment may sit between them). The image decoder cannot tell an SVG from any
/// other unknown file, so this is what sends one down the drawing path instead.
bool looksLikeSvg(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  while (start < bytes.length && _isSpace(bytes[start])) {
    start++;
  }
  final end = start + _sniffLength < bytes.length
      ? start + _sniffLength
      : bytes.length;
  final head = latin1.decode(bytes.sublist(start, end));
  if (head.startsWith('<svg')) return true;
  return head.startsWith('<?xml') && head.contains('<svg');
}

bool _isSpace(int byte) =>
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D;

/// Draws the SVG in [bytes] to a PNG on an opaque white background, its longer side
/// about 1200 pixels.
///
/// White because an SVG code is often black paths on a transparent canvas, and the
/// decoder needs the contrast a flattened image would give it; Qrious's own export
/// paints its background, but others do not. The scale is fixed rather than the
/// SVG's own size because that size is arbitrary (a viewBox of 33 units, or
/// millimetres) and a tiny one would leave the modules too small to read.
///
/// This uses dart:ui, so it runs on the UI isolate, before the bytes go to the
/// decoder's `compute`.
///
/// Throws [UnreadableImageException] when the SVG cannot be parsed.
Future<Uint8List> rasterizeSvg(Uint8List bytes) async {
  final PictureInfo info;
  try {
    info = await vg.loadPicture(SvgBytesLoader(bytes), null);
  } catch (error) {
    throw UnreadableImageException('The SVG could not be read: $error');
  }

  ui.Image? image;
  try {
    var width = info.size.width;
    var height = info.size.height;
    if (!(width.isFinite && width > 0 && height.isFinite && height > 0)) {
      width = height = _fallbackSide;
    }
    final scale = _targetLongSide / (width > height ? width : height);
    final pixelsWide = (width * scale).round().clamp(1, 4096);
    final pixelsHigh = (height * scale).round().clamp(1, 4096);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.scale(pixelsWide / width, pixelsHigh / height);
    canvas.drawPicture(info.picture);
    final picture = recorder.endRecording();
    try {
      image = await picture.toImage(pixelsWide, pixelsHigh);
    } finally {
      picture.dispose();
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const UnreadableImageException('The SVG could not be drawn.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    info.picture.dispose();
  }
}
