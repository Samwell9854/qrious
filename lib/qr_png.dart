import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

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

  /// This size with the spec's quiet zone, which is what beginner mode draws.
  QrLayout get layout => QrLayout(pixelsPerModule: pixelsPerModule);
}

/// The margin the spec requires on every side, in modules.
const quietZoneModules = 4;

/// The longest side an image may have, in pixels.
///
/// A choice, not a hard limit of the renderer below, whose cost grows with the square
/// of the side: 32768 pixels is 134 MB of 1-bit image and under a second to encode,
/// which any machine can afford. Flutter's own renderer is not used for files
/// because it silently clamps an image to the GPU's largest texture (16384 pixels
/// with Impeller on the machine this was measured on), saving a smaller file than
/// asked for without a word.
const maxImageSide = 32768;

/// How a code is laid out as an image: pixels per module, and the quiet zone around
/// it in modules.
class QrLayout {
  const QrLayout({this.pixelsPerModule = 8, this.quietZone = quietZoneModules});

  final int pixelsPerModule;
  final int quietZone;

  /// Width and height of the image for [qr], quiet zone included.
  int sideFor(EncodedQr qr) =>
      (qr.moduleCount + 2 * quietZone) * pixelsPerModule;

  /// The layout as close to this one as [qr] allows within [maxImageSide]: the
  /// quiet zone is kept as far as it fits at one pixel per module, then the pixels
  /// per module come down until the whole image fits.
  QrLayout fittedTo(EncodedQr qr) {
    final zone = min(quietZone, (maxImageSide - qr.moduleCount) ~/ 2);
    final unit = min(
      pixelsPerModule,
      maxImageSide ~/ (qr.moduleCount + 2 * zone),
    );
    return QrLayout(pixelsPerModule: max(unit, 1), quietZone: zone);
  }

  /// The most pixels per module [qr] can take with this quiet zone.
  int maxPixelsPerModuleFor(EncodedQr qr) =>
      maxImageSide ~/ (qr.moduleCount + 2 * quietZone);

  /// The widest quiet zone [qr] can take at these pixels per module.
  int maxQuietZoneFor(EncodedQr qr) =>
      (maxImageSide ~/ pixelsPerModule - qr.moduleCount) ~/ 2;

  @override
  bool operator ==(Object other) =>
      other is QrLayout &&
      other.pixelsPerModule == pixelsPerModule &&
      other.quietZone == quietZone;

  @override
  int get hashCode => Object.hash(pixelsPerModule, quietZone);
}

/// Renders [qr] as a PNG suitable for saving or printing.
///
/// This deliberately does not reuse what is on screen. The preview is a widget,
/// and a file needs two things a widget does not give it:
///
/// * An opaque background. A transparent PNG dropped on a dark background is a QR
///   code no scanner can read, because the contrast it depends on is inverted.
/// * Its own quiet zone. On screen the white box provides it; in a file, whatever
///   the image is pasted onto does, which is to say nothing.
///
/// So the code is always black on white with its own margin, whatever the app's
/// theme is doing. It is a 1-bit greyscale PNG, written row by row in Dart: a module
/// row is packed once and copied to each pixel row it covers, which keeps the largest
/// image well under a second. That second is spent on another isolate, so the window
/// does not freeze for it.
Future<Uint8List> renderQrPng(
  EncodedQr qr, {
  QrLayout layout = const QrLayout(),
}) => Isolate.run(() => _renderPng(qr, layout));

Uint8List _renderPng(EncodedQr qr, QrLayout layout) {
  final unit = layout.pixelsPerModule;
  final side = layout.sideFor(qr);
  final image = img.Image(
    width: side,
    height: side,
    format: img.Format.uint1,
    numChannels: 1,
  );
  final bits = image.buffer.asUint8List();
  final stride = (side + 7) ~/ 8;
  // 1 is white. Bits are filled most significant first, as PNG stores them.
  bits.fillRange(0, bits.length, 0xFF);

  final row = Uint8List(stride);
  for (var r = 0; r < qr.moduleCount; r++) {
    row.fillRange(0, stride, 0xFF);
    for (var c = 0; c < qr.moduleCount; c++) {
      if (!qr.image.isDark(r, c)) continue;
      final from = (c + layout.quietZone) * unit;
      for (var x = from; x < from + unit; x++) {
        row[x >> 3] &= ~(0x80 >> (x & 7));
      }
    }
    final top = (r + layout.quietZone) * unit;
    for (var y = top; y < top + unit; y++) {
      bits.setRange(y * stride, (y + 1) * stride, row);
    }
  }
  return img.encodePng(image);
}
