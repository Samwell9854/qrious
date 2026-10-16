import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_decoding.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_svg.dart';
import 'package:qrious/svg_raster.dart';

Uint8List text(String source) => Uint8List.fromList(utf8.encode(source));

void main() {
  group('looksLikeSvg', () {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';

    test('accepts a bare svg element', () {
      expect(looksLikeSvg(text(svg)), isTrue);
    });

    test('accepts leading whitespace', () {
      expect(looksLikeSvg(text('\n  \t$svg')), isTrue);
    });

    test('accepts an xml prolog before the svg', () {
      expect(
        looksLikeSvg(
          text('<?xml version="1.0"?>\n<!-- made by hand -->\n$svg'),
        ),
        isTrue,
      );
    });

    test('accepts a UTF-8 byte order mark', () {
      expect(
        looksLikeSvg(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...text(svg)])),
        isTrue,
      );
    });

    test('rejects xml that is not svg', () {
      expect(looksLikeSvg(text('<?xml version="1.0"?><html></html>')), isFalse);
    });

    test('rejects PNG bytes, text and nothing', () {
      expect(
        looksLikeSvg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])),
        isFalse,
      );
      expect(looksLikeSvg(text('hello <svg> in the middle')), isFalse);
      expect(looksLikeSvg(Uint8List(0)), isFalse);
    });
  });

  group('rasterizeSvg', () {
    const payload = 'https://example.com/svg';
    final qr = encodeQr(payload, ErrorCorrection.auto);

    // runAsync throughout, as in qr_png_test.dart: dart:ui needs the real loop.
    testWidgets("reads back Qrious's own export", (tester) async {
      await tester.runAsync(() async {
        final png = await rasterizeSvg(text(renderQrSvg(qr)));
        expect(png.take(4), [0x89, 0x50, 0x4E, 0x47]);
        expect(decodeQrCodes(png), [payload]);
      });
    });

    testWidgets('reads an svg with a viewBox and no width or height', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final sized = renderQrSvg(qr);
        final bare = sized.replaceAll(RegExp(r'\s(width|height)="[^"]*"'), '');
        expect(bare, contains('viewBox'));
        final png = await rasterizeSvg(text(bare));
        expect(decodeQrCodes(png), [payload]);
      });
    });

    testWidgets('reads black paths on a transparent canvas', (tester) async {
      await tester.runAsync(() async {
        final transparent = renderQrSvg(
          qr,
        ).replaceAll(RegExp(r'<rect[^>]*/>'), '');
        final png = await rasterizeSvg(text(transparent));
        expect(decodeQrCodes(png), [payload]);
      });
    });

    testWidgets('rejects an svg that cannot be parsed', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          rasterizeSvg(text('<svg><path d="M 0 0 L"')),
          throwsA(isA<UnreadableImageException>()),
        );
      });
    });
  });
}
