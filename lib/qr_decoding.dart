import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Thrown when the bytes are not an image the decoder can open.
class UnreadableImageException implements Exception {
  const UnreadableImageException([
    this.message = 'The file is not an image that can be opened.',
  ]);

  final String message;

  @override
  String toString() => 'UnreadableImageException: $message';
}

/// The long side is capped here: a phone photo is 4000+ px and the detector's cost grows
/// with the pixel count, while a code that needs more than this to be read is lost anyway.
const _maxLongSide = 2000;

/// A downscale that would leave the short side under this is not attempted.
const _minScaledSide = 100;

/// Regions smaller than this (in either direction) are not searched for more codes. The
/// smallest QR code, at one pixel per module, is 21 px, but the detector needs several
/// pixels per module to lock on, so this is the same bound ZXing's multi reader uses.
const _minRegionSide = 100;

/// How deep the search for further codes goes around a found one.
const _maxDepth = 4;

/// The payload of every QR code in [imageBytes] (PNG, JPEG, GIF, BMP, WebP...),
/// deduplicated, ordered top-to-bottom then left-to-right by position. Empty when none is
/// found. Throws [UnreadableImageException] when the bytes are no image.
List<String> decodeQrCodes(Uint8List imageBytes) {
  var image = img.decodeImage(imageBytes);
  if (image == null) throw const UnreadableImageException();
  // Phone photos carry their rotation in EXIF rather than in the pixels.
  image = img.bakeOrientation(image);
  image = _capped(image, _maxLongSide);

  // Different binarizers and scales fail on different photos, so each is a fallback for
  // the previous. A printed, photographed code with speckle inside its modules fails with
  // the local-threshold HybridBinarizer and reads with the global histogram one; another
  // decoder only read the same sample once it was shrunk to a quarter, which averages the
  // speckle away. The first attempt that finds anything gives the whole answer.
  for (final divisor in const [1, 2, 4]) {
    final scaled = divisor == 1 ? image : _scaled(image, divisor);
    if (scaled == null) continue;
    final source = _luminanceSource(scaled);
    for (final makeBinarizer in <Binarizer Function(LuminanceSource)>[
      HybridBinarizer.new,
      GlobalHistogramBinarizer.new,
    ]) {
      final found = _findAll(BinaryBitmap(makeBinarizer(source)));
      if (found.isNotEmpty) return _ordered(found);
    }
  }
  return const [];
}

img.Image _capped(img.Image image, int longSide) {
  if (image.width <= longSide && image.height <= longSide) return image;
  return image.width >= image.height
      ? img.copyResize(image, width: longSide)
      : img.copyResize(image, height: longSide);
}

img.Image? _scaled(img.Image image, int divisor) {
  final width = image.width ~/ divisor;
  final height = image.height ~/ divisor;
  if (width < _minScaledSide || height < _minScaledSide) return null;
  // Averaging, not nearest-neighbour: the point of shrinking is to smooth noise.
  return img.copyResize(
    image,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );
}

LuminanceSource _luminanceSource(img.Image image) => RGBLuminanceSource(
  image.width,
  image.height,
  image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List(),
);

/// A decoded payload and where its top-left-most point sits in the whole image.
typedef _Hit = ({String text, double x, double y});

/// Every code in [bitmap]. zxing2 has no multi reader, so this is a port of ZXing's
/// GenericMultipleBarcodeReader: decode once, then search the four regions around the
/// bounding box of what was found, since the box itself is already spoken for.
List<_Hit> _findAll(BinaryBitmap bitmap) {
  final hits = <_Hit>[];
  _search(bitmap, 0, 0, 0, hits);
  return hits;
}

void _search(
  BinaryBitmap bitmap,
  int offsetX,
  int offsetY,
  int depth,
  List<_Hit> hits,
) {
  if (depth > _maxDepth) return;
  final Result result;
  try {
    result = QRCodeReader().decode(
      bitmap,
      hints: DecodeHints()..put(DecodeHintType.tryHarder),
    );
  } on ReaderException {
    // NotFound, Checksum and FormatReader all mean "no code in this region".
    return;
  }

  final points = result.resultPoints;
  if (points.isEmpty) return;
  var minX = double.infinity, minY = double.infinity;
  var maxX = 0.0, maxY = 0.0;
  for (final p in points) {
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  final text = _repaired(result);
  if (!hits.any((h) => h.text == text)) {
    hits.add((text: text, x: minX + offsetX, y: minY + offsetY));
  }

  if (!bitmap.isCropSupported) return;
  final width = bitmap.width, height = bitmap.height;
  void recurse(int left, int top, int w, int h) {
    if (w < _minRegionSide || h < _minRegionSide) return;
    _search(
      bitmap.crop(left, top, w, h),
      offsetX + left,
      offsetY + top,
      depth + 1,
      hits,
    );
  }

  final left = minX.floor().clamp(0, width);
  final top = minY.floor().clamp(0, height);
  final right = maxX.ceil().clamp(0, width);
  final bottom = maxY.ceil().clamp(0, height);
  recurse(0, 0, left, height); // left of the box
  recurse(0, 0, width, top); // above it
  recurse(right, 0, width - right, height); // right of it
  recurse(0, bottom, width, height - bottom); // below it
}

/// Reading order: rows top to bottom, and within a row left to right. Two codes count as
/// one row when their tops are within [_rowTolerance] of each other, so that the slightly
/// different finder-pattern estimates of codes printed side by side do not reorder them.
List<String> _ordered(List<_Hit> hits) {
  final sorted = [...hits]..sort((a, b) => a.y.compareTo(b.y));
  final rows = <List<_Hit>>[];
  for (final hit in sorted) {
    if (rows.isNotEmpty && (hit.y - rows.last.first.y).abs() <= _rowTolerance) {
      rows.last.add(hit);
    } else {
      rows.add([hit]);
    }
  }
  return [
    for (final row in rows)
      for (final hit in row..sort((a, b) => a.x.compareTo(b.x))) hit.text,
  ];
}

/// In pixels of the scale the search ran at; the finder-pattern y estimates of one row of
/// codes differ by a few pixels, not by a code's height.
const _rowTolerance = 20.0;

/// zxing2 hands its signed bytes straight to the character decoder, so every byte of 0x80
/// or above reads as invalid and non-ASCII text comes out as U+FFFD ("Café" as "Caf??").
/// The bytes survive in the byte segments, so decode those properly and swap them in for
/// what zxing2 produced from them. Which charset the bytes are in is not recorded when no
/// ECI says so; UTF-8 is what Qrious and nearly every phone app write, else Latin-1.
String _repaired(Result result) {
  var text = result.text;
  if (!text.contains('\uFFFD')) return text;
  final segments = result.resultMetadata[ResultMetadataType.byteSegments];
  if (segments is! List) return text;
  for (final segment in segments.whereType<Int8List>()) {
    final bytes = Uint8List.view(
      segment.buffer,
      segment.offsetInBytes,
      segment.length,
    );
    String good;
    try {
      good = utf8.decode(bytes);
    } on FormatException {
      good = latin1.decode(bytes);
    }
    for (final broken in [
      const Utf8Codec(allowMalformed: true).decode(segment),
      const Latin1Codec(allowInvalid: true).decode(segment),
    ]) {
      if (text.contains(broken)) {
        text = text.replaceFirst(broken, good);
        break;
      }
    }
  }
  return text;
}
