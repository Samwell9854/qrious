import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_decoding.dart';
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
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('qrious/svg');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends the bytes to the runner and returns its PNG', () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return png;
      });

      final source = text('<svg xmlns="http://www.w3.org/2000/svg"></svg>');
      expect(await rasterizeSvg(source), png);
      expect(seen?.method, 'rasterize');
      expect(seen?.arguments, source);
    });

    test('maps an error from the runner to UnreadableImageException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unreadable', message: 'bad xml');
      });
      await expectLater(
        rasterizeSvg(text('<svg>')),
        throwsA(
          isA<UnreadableImageException>().having(
            (e) => e.toString(),
            'message',
            contains('bad xml'),
          ),
        ),
      );
    });

    test('maps a missing runner to UnreadableImageException', () async {
      await expectLater(
        rasterizeSvg(text('<svg>')),
        throwsA(isA<UnreadableImageException>()),
      );
    });
  });
}
