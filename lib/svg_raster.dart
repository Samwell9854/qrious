import 'dart:convert';

import 'package:flutter/services.dart';

import 'qr_decoding.dart';

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

/// The runner's rasteriser (linux/runner/my_application.cc).
const _channel = MethodChannel('qrious/svg');

/// Draws the SVG in [bytes] to a PNG on an opaque white background, its longer side
/// about 1200 pixels.
///
/// Drawn by librsvg in the Linux runner rather than by a Dart package: it supports
/// the whole format, nested `<svg>` elements included, which other generators emit
/// and which flutter_svg draws as a blank image. It is also the renderer GNOME uses,
/// and GTK 3 already depends on it, so it costs the app nothing to ship.
///
/// White because an SVG code is often black paths on a transparent canvas, and the
/// decoder needs the contrast a flattened image would give it; Qrious's own export
/// paints its background, but others do not. The scale is fixed rather than the
/// SVG's own size because that size is arbitrary (a viewBox of 33 units, or
/// millimetres) and a tiny one would leave the modules too small to read. The runner
/// works out the size from width and height, else the viewBox, else a square.
///
/// Throws [UnreadableImageException] when the SVG cannot be parsed or drawn, or the
/// runner does not answer (a platform without it).
Future<Uint8List> rasterizeSvg(Uint8List bytes) async {
  try {
    final png = await _channel.invokeMethod<Uint8List>('rasterize', bytes);
    if (png == null) {
      throw const UnreadableImageException('The SVG could not be drawn.');
    }
    return png;
  } on PlatformException catch (error) {
    throw UnreadableImageException(
      'The SVG could not be read: ${error.message}',
    );
  } on MissingPluginException {
    throw const UnreadableImageException(
      'Reading an SVG is only supported on Linux so far.',
    );
  }
}
