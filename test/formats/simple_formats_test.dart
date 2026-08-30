import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/phone_format.dart';
import 'package:qrious/formats/text_format.dart';
import 'package:qrious/formats/url_format.dart';

void main() {
  group('PhoneFormat.buildQrString', () {
    final format = PhoneFormat();

    test('tolerates an empty map', () {
      expect(format.buildQrString({}), 'tel:');
    });

    test('prefixes the number with the tel: scheme', () {
      expect(
        format.buildQrString({'phone': '+15550000000'}),
        'tel:+15550000000',
      );
    });

    test('passes the number through verbatim', () {
      expect(
        format.buildQrString({'phone': '+1 555 000 0000'}),
        'tel:+1 555 000 0000',
      );
    });
  });

  group('UrlFormat.buildQrString', () {
    final format = UrlFormat();

    test('tolerates an empty map', () {
      expect(format.buildQrString({}), '');
    });

    test('emits the URL verbatim', () {
      expect(
        format.buildQrString({'url': 'https://example.com/a?b=c#d'}),
        'https://example.com/a?b=c#d',
      );
    });
  });

  group('TextFormat.buildQrString', () {
    final format = TextFormat();

    test('tolerates an empty map', () {
      expect(format.buildQrString({}), '');
    });

    test('emits the text verbatim, newlines included', () {
      expect(
        format.buildQrString({'text': 'line one\nline two'}),
        'line one\nline two',
      );
    });
  });
}
