import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_export.dart';
import 'package:qrious/qr_png.dart';

void main() {
  group('ExportFileType', () {
    test('adds its extension unless the name already ends in it', () {
      expect(ExportFileType.png.withExtension('/tmp/code'), '/tmp/code.png');
      expect(
        ExportFileType.png.withExtension('/tmp/code.PNG'),
        '/tmp/code.PNG',
      );
      expect(
        ExportFileType.svg.withExtension('/tmp/code.svg'),
        '/tmp/code.svg',
      );
      expect(
        ExportFileType.svg.withExtension('/tmp/code.png'),
        '/tmp/code.png.svg',
      );
    });

    testWidgets('renders each type as that type', (tester) async {
      final qr = encodeQr('https://example.com', ErrorCorrection.auto);
      await tester.runAsync(() async {
        final png = await ExportFileType.png.render(qr, ImageSize.small);
        expect(png.take(4), [0x89, 0x50, 0x4E, 0x47]);

        final svg = await ExportFileType.svg.render(qr, ImageSize.small);
        expect(utf8.decode(svg), startsWith('<?xml'));
      });
    });
  });

  group('qrFileName', () {
    test('carries the format, a sortable timestamp and the extension', () {
      final when = DateTime(2026, 8, 30, 9, 5, 4);
      expect(
        qrFileName('wifi', when, ExportFileType.png),
        'qrious-wifi-20260830-090504.png',
      );
      expect(
        qrFileName('wifi', when, ExportFileType.svg),
        'qrious-wifi-20260830-090504.svg',
      );
    });

    test('zero-pads so names sort chronologically as strings', () {
      final early = qrFileName(
        'url',
        DateTime(2026, 1, 2, 3, 4, 5),
        ExportFileType.png,
      );
      final later = qrFileName(
        'url',
        DateTime(2026, 11, 12, 13, 14, 15),
        ExportFileType.png,
      );
      expect(early.compareTo(later), isNegative);
    });

    test('differs second by second, so a second save does not overwrite', () {
      expect(
        qrFileName('vcard', DateTime(2026, 8, 30, 9, 5, 4), ExportFileType.png),
        isNot(
          qrFileName(
            'vcard',
            DateTime(2026, 8, 30, 9, 5, 5),
            ExportFileType.png,
          ),
        ),
      );
    });
  });
}
