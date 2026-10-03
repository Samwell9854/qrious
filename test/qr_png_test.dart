import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_png.dart';

/// The eight bytes every PNG file begins with.
const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Width and height from the IHDR chunk, which is always the first chunk.
({int width, int height}) pngSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}

void main() {
  group('renderQrPng', () {
    // Version 2 at auto: 25 modules a side, 33 with the quiet zone.
    final qr = encodeQr('https://example.com', ErrorCorrection.auto);

    testWidgets('sizes the image by modules, quiet zone included', (
      tester,
    ) async {
      // runAsync throughout: encoding and decoding an image need the real event
      // loop, and deadlock against the fake async a widget test runs under.
      await tester.runAsync(() async {
        for (final size in ImageSize.values) {
          final bytes = await renderQrPng(qr, size: size);
          final side = 33 * size.pixelsPerModule;

          expect(bytes.take(8), pngSignature);
          expect(pngSize(bytes), (
            width: side,
            height: side,
          ), reason: size.name);
          expect(size.pixelsFor(qr), side, reason: size.name);
        }
      });
    });

    testWidgets('paints every module as a solid block on a white background', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const unit = 4;
        final bytes = await renderQrPng(qr, size: ImageSize.small);
        final image = await decodeImageFromList(bytes);
        addTearDown(image.dispose);
        final pixels = (await image.toByteData())!;
        final side = image.width;
        int pixel(int x, int y) => pixels.getUint32((y * side + x) * 4);

        for (var y = 0; y < side; y++) {
          for (var x = 0; x < side; x++) {
            final row = y ~/ unit - quietZoneModules;
            final col = x ~/ unit - quietZoneModules;
            final inSymbol =
                row >= 0 &&
                col >= 0 &&
                row < qr.moduleCount &&
                col < qr.moduleCount;
            final dark = inSymbol && qr.image.isDark(row, col);
            // Exactly black or white: a module edge on a fractional pixel would
            // anti-alias into grey here.
            expect(
              pixel(x, y),
              dark ? 0x000000FF : 0xFFFFFFFF,
              reason: 'pixel ($x, $y)',
            );
          }
        }
      });
    });

    testWidgets('handles a payload long enough to need a high version', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final large = encodeQr('x' * 1000, ErrorCorrection.auto);
        final bytes = await renderQrPng(large, size: ImageSize.small);
        expect(bytes.take(8), pngSignature);
        expect(pngSize(bytes).width, (large.moduleCount + 8) * 4);
      });
    });
  });

  group('qrFileName', () {
    test('carries the format and a sortable timestamp', () {
      expect(
        qrFileName('wifi', DateTime(2026, 8, 30, 9, 5, 4)),
        'qrious-wifi-20260830-090504.png',
      );
    });

    test('zero-pads so names sort chronologically as strings', () {
      final early = qrFileName('url', DateTime(2026, 1, 2, 3, 4, 5));
      final later = qrFileName('url', DateTime(2026, 11, 12, 13, 14, 15));
      expect(early.compareTo(later), isNegative);
    });

    test('differs second by second, so a second save does not overwrite', () {
      expect(
        qrFileName('vcard', DateTime(2026, 8, 30, 9, 5, 4)),
        isNot(qrFileName('vcard', DateTime(2026, 8, 30, 9, 5, 5))),
      );
    });
  });
}
