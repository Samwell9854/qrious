import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    testWidgets('produces a PNG at the requested size', (tester) async {
      // runAsync throughout: encoding and decoding an image need the real event
      // loop, and deadlock against the fake async a widget test runs under.
      await tester.runAsync(() async {
        final bytes = await renderQrPng('https://example.com', size: 256);

        expect(bytes.take(8), pngSignature);
        expect(pngSize(bytes), (width: 256, height: 256));
      });
    });

    testWidgets('defaults to a size worth printing', (tester) async {
      await tester.runAsync(() async {
        final bytes = await renderQrPng('https://example.com');
        expect(pngSize(bytes), (width: 1024, height: 1024));
      });
    });

    testWidgets('paints on an opaque white background, not transparency', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // The corners are quiet zone, so they are background and nothing else.
        final bytes = await renderQrPng('https://example.com', size: 128);
        final image = await decodeImageFromList(bytes);
        addTearDown(image.dispose);
        final pixels = (await image.toByteData())!;

        expect(pixels.getUint32(0), 0xFFFFFFFF, reason: 'top left corner');
        final lastPixel = pixels.lengthInBytes - 4;
        expect(pixels.getUint32(lastPixel), 0xFFFFFFFF, reason: 'bottom right');
      });
    });

    testWidgets('leaves a quiet zone the modules never reach into', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final bytes = await renderQrPng('https://example.com', size: 240);
        final image = await decodeImageFromList(bytes);
        addTearDown(image.dispose);
        final pixels = (await image.toByteData())!;

        // Every pixel of the top row and left column must still be white.
        for (var x = 0; x < 240; x++) {
          expect(pixels.getUint32(x * 4), 0xFFFFFFFF, reason: 'top row x=$x');
        }
        for (var y = 0; y < 240; y++) {
          expect(
            pixels.getUint32(y * 240 * 4),
            0xFFFFFFFF,
            reason: 'left column at y=$y',
          );
        }
      });
    });

    testWidgets('actually paints the code, not just the background', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final bytes = await renderQrPng('https://example.com', size: 128);
        final image = await decodeImageFromList(bytes);
        addTearDown(image.dispose);
        final pixels = (await image.toByteData())!;

        var dark = 0;
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          if (pixels.getUint32(i) != 0xFFFFFFFF) dark++;
        }
        expect(dark, greaterThan(0));
      });
    });

    testWidgets('refuses an empty payload', (tester) async {
      expect(() => renderQrPng(''), throwsArgumentError);
    });

    testWidgets('handles a payload long enough to need a high version', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final bytes = await renderQrPng('x' * 1000, size: 256);
        expect(bytes.take(8), pngSignature);
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
