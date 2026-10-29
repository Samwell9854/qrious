import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_decoding.dart';
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
  group('QrLayout', () {
    // Version 2: 25 modules a side.
    final qr = encodeQr('https://example.com', ErrorCorrection.auto);

    test('fits within the largest image, the quiet zone first', () {
      expect(
        const QrLayout(pixelsPerModule: 10, quietZone: 2).fittedTo(qr),
        const QrLayout(pixelsPerModule: 10, quietZone: 2),
      );
      expect(
        const QrLayout(pixelsPerModule: 5000).fittedTo(qr),
        QrLayout(pixelsPerModule: maxImageSide ~/ 33),
      );
      expect(
        const QrLayout(pixelsPerModule: 4, quietZone: 99999).fittedTo(qr),
        const QrLayout(pixelsPerModule: 1, quietZone: (maxImageSide - 25) ~/ 2),
      );
    });

    test('its bounds are exactly the largest that fit', () {
      const layout = QrLayout(pixelsPerModule: 16, quietZone: 3);
      final pixels = layout.maxPixelsPerModuleFor(qr);
      expect(
        QrLayout(pixelsPerModule: pixels, quietZone: 3).sideFor(qr),
        lessThanOrEqualTo(maxImageSide),
      );
      expect(
        QrLayout(pixelsPerModule: pixels + 1, quietZone: 3).sideFor(qr),
        greaterThan(maxImageSide),
      );
      final zone = layout.maxQuietZoneFor(qr);
      expect(
        QrLayout(pixelsPerModule: 16, quietZone: zone).sideFor(qr),
        lessThanOrEqualTo(maxImageSide),
      );
      expect(
        QrLayout(pixelsPerModule: 16, quietZone: zone + 1).sideFor(qr),
        greaterThan(maxImageSide),
      );
    });
  });

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
          final bytes = await renderQrPng(qr, layout: size.layout);
          final side = 33 * size.pixelsPerModule;

          expect(bytes.take(8), pngSignature);
          expect(pngSize(bytes), (
            width: side,
            height: side,
          ), reason: size.name);
          expect(size.layout.sideFor(qr), side, reason: size.name);
        }
      });
    });

    testWidgets('paints every module as a solid block on a white background', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const unit = 4;
        final bytes = await renderQrPng(qr, layout: ImageSize.small.layout);
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

    testWidgets('one pixel per module and no quiet zone still read back', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // A reader needs some margin to find the code; the file has none, so the
        // test gives it one, as whatever the image is pasted onto would.
        final bytes = await renderQrPng(
          qr,
          layout: const QrLayout(pixelsPerModule: 1, quietZone: 0),
        );
        expect(pngSize(bytes).width, qr.moduleCount);
        final tight = await renderQrPng(
          qr,
          layout: const QrLayout(pixelsPerModule: 1, quietZone: 4),
        );
        expect(decodeQrCodes(tight), ['https://example.com']);
      });
    });

    testWidgets('renders the largest image at its full size', (tester) async {
      await tester.runAsync(() async {
        final layout = QrLayout(pixelsPerModule: maxImageSide ~/ 33);
        final bytes = await renderQrPng(qr, layout: layout);
        expect(pngSize(bytes).width, layout.sideFor(qr));
      });
    });

    testWidgets('handles a payload long enough to need a high version', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final large = encodeQr('x' * 1000, ErrorCorrection.auto);
        final bytes = await renderQrPng(large, layout: ImageSize.small.layout);
        expect(bytes.take(8), pngSignature);
        expect(pngSize(bytes).width, (large.moduleCount + 8) * 4);
      });
    });
  });
}
