import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/qr_decoding.dart';
import 'package:zxing2/qrcode.dart';

const _module = 8;
const _quiet = 4;

/// Black modules on white with a quiet zone, [_module] pixels per module.
img.Image _render(String data) {
  final qr = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final side = (qr.moduleCount + 2 * _quiet) * _module;
  final image = img.Image(width: side, height: side, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var r = 0; r < qr.moduleCount; r++) {
    for (var c = 0; c < qr.moduleCount; c++) {
      if (!qr.isDark(r, c)) continue;
      img.fillRect(
        image,
        x1: (c + _quiet) * _module,
        y1: (r + _quiet) * _module,
        x2: (c + _quiet + 1) * _module - 1,
        y2: (r + _quiet + 1) * _module - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return image;
}

/// Two codes on one white canvas, [a] first and [b] to its right or below it.
img.Image _pair(String a, String b, {required bool sideBySide}) {
  final first = _render(a), second = _render(b);
  const gap = 40;
  final canvas = img.Image(
    width: sideBySide
        ? first.width + second.width + gap
        : max(first.width, second.width),
    height: sideBySide
        ? max(first.height, second.height)
        : first.height + second.height + gap,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, first);
  img.compositeImage(
    canvas,
    second,
    dstX: sideBySide ? first.width + gap : 0,
    dstY: sideBySide ? 0 : first.height + gap,
  );
  return canvas;
}

/// Stands in for a printed code photographed with a phone: speckle of paper showing
/// through the ink, grey noise everywhere, then lossy recompression.
Uint8List _degraded(String data, {int seed = 7}) {
  final image = _render(data);
  final random = Random(seed);
  for (final p in image) {
    if (p.r < 128) {
      if (random.nextDouble() < 0.10) p.setRgb(255, 255, 255);
    }
    final noise = random.nextInt(81) - 40;
    p.setRgb(
      (p.r + noise).clamp(0, 255),
      (p.g + noise).clamp(0, 255),
      (p.b + noise).clamp(0, 255),
    );
  }
  return img.encodeJpg(image, quality: 25);
}

/// What decodeQrCodes does on its first attempt, to prove a fixture needs the fallbacks.
bool _hybridReads(Uint8List bytes) {
  final image = img.decodeImage(bytes)!;
  final source = RGBLuminanceSource(
    image.width,
    image.height,
    image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List(),
  );
  try {
    QRCodeReader().decode(
      BinaryBitmap(HybridBinarizer(source)),
      hints: DecodeHints()..put(DecodeHintType.tryHarder),
    );
    return true;
  } on ReaderException {
    return false;
  }
}

void main() {
  test('a clean URL code decodes to its payload', () {
    final bytes = img.encodePng(_render('https://example.com/path?q=1'));
    expect(decodeQrCodes(bytes), ['https://example.com/path?q=1']);
  });

  test('a multi-line payload with non-ASCII text decodes intact', () {
    const vcard =
        'BEGIN:VCARD\nVERSION:3.0\nFN:Café Müller\nTEL:+15145550100\nEND:VCARD';
    expect(decodeQrCodes(img.encodePng(_render(vcard))), [vcard]);
  });

  test('a speckled, noisy, recompressed code still decodes', () {
    const data = 'WIFI:T:WPA;S:Cafe;P:hunter2hunter2;;';
    final bytes = _degraded(data);
    expect(decodeQrCodes(bytes), [data]);
  });

  test('the degraded fixture defeats the first attempt alone', () {
    // Guards the test above: if this starts failing the fixture has become too easy
    // and no longer exercises the binarizer and scale fallbacks.
    expect(
      _hybridReads(_degraded('WIFI:T:WPA;S:Cafe;P:hunter2hunter2;;')),
      isFalse,
    );
  });

  test('two codes side by side come back left first', () {
    final bytes = img.encodePng(
      _pair('left-code', 'right-code', sideBySide: true),
    );
    expect(decodeQrCodes(bytes), ['left-code', 'right-code']);
  });

  test('two codes stacked come back top first', () {
    final bytes = img.encodePng(
      _pair('top-code', 'bottom-code', sideBySide: false),
    );
    expect(decodeQrCodes(bytes), ['top-code', 'bottom-code']);
  });

  test('a camera frame of luma bytes decodes like a file', () {
    final image = _pair('left-code', 'right-code', sideBySide: true);
    final luma = Uint8List.fromList([for (final p in image) p.r.toInt()]);
    expect(
      decodeQrCodesFromLuma((
        width: image.width,
        height: image.height,
        luma: luma,
      )),
      ['left-code', 'right-code'],
    );
  });

  test('a camera frame whose bytes do not match its size is refused', () {
    expect(
      () => decodeQrCodesFromLuma((width: 10, height: 10, luma: Uint8List(99))),
      throwsArgumentError,
    );
  });

  test('a blank image has no codes', () {
    final blank = img.Image(width: 300, height: 300, numChannels: 3);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(decodeQrCodes(img.encodePng(blank)), isEmpty);
  });

  test('bytes that are no image throw', () {
    final garbage = Uint8List.fromList(
      List.generate(500, (i) => (i * 37) % 256),
    );
    expect(
      () => decodeQrCodes(garbage),
      throwsA(isA<UnreadableImageException>()),
    );
  });

  test('a code rotated a quarter turn still decodes', () {
    final rotated = img.copyRotate(_render('rotated payload'), angle: 90);
    expect(decodeQrCodes(img.encodePng(rotated)), ['rotated payload']);
  });
}
