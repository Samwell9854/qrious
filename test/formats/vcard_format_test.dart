import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/vcard_format.dart';

void main() {
  final format = VCardFormat();

  group('VCardFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(
        format.buildQrString({}),
        'BEGIN:VCARD\nVERSION:3.0\nN:;;;;\nFN:\nEND:VCARD',
      );
    });

    group('name lines', () {
      test('a first name alone fills the given-name slot', () {
        final lines = format.buildQrString({'first_name': 'Ada'}).split('\n');
        expect(lines, containsAllInOrder(['N:;Ada;;;', 'FN:Ada']));
      });

      test('a last name alone fills the family-name slot', () {
        final lines = format
            .buildQrString({'last_name': 'Lovelace'})
            .split('\n');
        expect(lines, containsAllInOrder(['N:Lovelace;;;;', 'FN:Lovelace']));
      });

      test('N: is family-first and FN: is given-first', () {
        final lines = format
            .buildQrString({'first_name': 'Ada', 'last_name': 'Lovelace'})
            .split('\n');
        expect(
          lines,
          containsAllInOrder(['N:Lovelace;Ada;;;', 'FN:Ada Lovelace']),
        );
      });
    });

    group('optional fields', () {
      test('are omitted entirely when absent', () {
        final payload = format.buildQrString({'first_name': 'Ada'});
        for (final tag in [
          'ORG:',
          'TITLE:',
          'TEL:',
          'EMAIL:',
          'URL:',
          'ADR:',
        ]) {
          expect(payload, isNot(contains(tag)));
        }
      });

      test('are omitted when present but empty', () {
        final payload = format.buildQrString({
          'first_name': 'Ada',
          'org': '',
          'title': '',
          'phone': '',
          'email': '',
          'url': '',
          'address': '',
        });
        expect(
          payload,
          'BEGIN:VCARD\nVERSION:3.0\nN:;Ada;;;\nFN:Ada\nEND:VCARD',
        );
      });

      test('are emitted in declaration order between FN: and END:', () {
        final payload = format.buildQrString({
          'first_name': 'Ada',
          'last_name': 'Lovelace',
          'org': 'Analytical Engines',
          'title': 'Mathematician',
          'phone': '+15550000000',
          'email': 'ada@example.com',
          'url': 'https://example.com',
          'address': '12 Baker St',
        });
        expect(payload, '''
BEGIN:VCARD
VERSION:3.0
N:Lovelace;Ada;;;
FN:Ada Lovelace
ORG:Analytical Engines
TITLE:Mathematician
TEL:+15550000000
EMAIL:ada@example.com
URL:https://example.com
ADR:;;12 Baker St;;;;
END:VCARD''');
      });

      test('the address sits in the street slot of ADR:', () {
        expect(
          format.buildQrString({'address': '12 Baker St'}),
          contains('ADR:;;12 Baker St;;;;'),
        );
      });
    });

    group('escaping', () {
      test('a semicolon in a name does not split the N: components', () {
        final lines = format
            .buildQrString({'first_name': 'Ada', 'last_name': 'Lovelace; Jr'})
            .split('\n');
        expect(lines, contains(r'N:Lovelace\; Jr;Ada;;;'));
        expect(lines, contains(r'FN:Ada Lovelace\; Jr'));
      });

      test('a newline in the address stays inside the ADR: property', () {
        final payload = format.buildQrString({
          'address': '12 Baker St\nLondon',
        });
        expect(payload, contains(r'ADR:;;12 Baker St\nLondon;;;;'));
        // BEGIN, VERSION, N, FN, ADR, END — a raw newline would add a seventh.
        expect(payload.split('\n'), hasLength(6));
      });

      test('a carriage return or CRLF also becomes a literal \\n', () {
        expect(
          format.buildQrString({'address': 'a\r\nb\rc'}),
          contains(r'ADR:;;a\nb\nc;;;;'),
        );
      });

      test('escapes backslash, semicolon and comma in a text value', () {
        expect(
          format.buildQrString({'org': r'A\B;C,D'}),
          contains(r'ORG:A\\B\;C\,D'),
        );
      });

      test('escapes the backslash before it can escape its own escapes', () {
        // Naive ordering would turn "\" into "\\" and then "\\\\".
        expect(format.buildQrString({'org': r'\'}), contains(r'ORG:\\'));
      });

      test('leaves ordinary punctuation alone', () {
        expect(
          format.buildQrString({'org': "O'Neil & Sons (Ltd.)"}),
          contains("ORG:O'Neil & Sons (Ltd.)"),
        );
      });
    });

    test('always opens with BEGIN and closes with END', () {
      final lines = format.buildQrString({'first_name': 'Ada'}).split('\n');
      expect(lines.first, 'BEGIN:VCARD');
      expect(lines.last, 'END:VCARD');
    });
  });
}
