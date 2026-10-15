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

  group('PhoneFormat.parse', () {
    final format = PhoneFormat();

    test('reads back what it builds', () {
      expect(format.parse('tel:+1 555 000 0000')!.values, {
        'phone': '+1 555 000 0000',
      });
    });

    test('ignores the prefix case and tolerates an empty number', () {
      expect(format.parse('TEL:5')!.values['phone'], '5');
      expect(format.parse('tel:')!.values['phone'], '');
    });

    test('returns null for another prefix', () {
      expect(format.parse('SMSTO:555'), isNull);
      expect(format.parse('555'), isNull);
    });
  });

  group('UrlFormat.parse', () {
    final format = UrlFormat();

    test('claims http and https in any case', () {
      expect(format.parse('https://example.com/a?b=c')!.values, {
        'url': 'https://example.com/a?b=c',
      });
      expect(
        format.parse('HTTP://EXAMPLE.COM')!.values['url'],
        'HTTP://EXAMPLE.COM',
      );
    });

    test('leaves every other scheme alone', () {
      for (final payload in [
        'geo:1,2',
        'mailto:a@b.co',
        'tel:555',
        'ftp://example.com',
        'example.com',
        ' https://example.com',
        '',
      ]) {
        expect(format.parse(payload), isNull, reason: payload);
      }
    });
  });

  group('TextFormat.parse', () {
    test('claims nothing', () {
      final format = TextFormat();
      for (final payload in [
        '',
        'hello',
        'https://example.com',
        'WIFI:S:x;;',
      ]) {
        expect(format.parse(payload), isNull);
      }
    });
  });
}
