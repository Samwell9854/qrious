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
          'street': '',
          'city': '',
          'region': '',
          'postal_code': '',
          'country': '',
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
          'street': '12 Baker St',
          'city': 'London',
          'postal_code': 'NW1 6XE',
          'country': 'UK',
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
ADR:;;12 Baker St;London;;NW1 6XE;UK
END:VCARD''');
      });

      test('each address part fills its own ADR: slot', () {
        expect(
          format.buildQrString({
            'street': '10011 Renaude-Lapointe',
            'city': 'Anjou',
            'region': 'QC',
            'postal_code': 'H1H 1H1',
            'country': 'Canada',
          }),
          contains('ADR:;;10011 Renaude-Lapointe;Anjou;QC;H1H 1H1;Canada'),
        );
      });

      test('a city alone still makes an ADR:', () {
        expect(
          format.buildQrString({'city': 'Anjou'}),
          contains('ADR:;;;Anjou;;;'),
        );
      });

      test('a phone number keeps its pause unescaped', () {
        expect(
          format.buildQrString({'phone': '+15145550000,274'}),
          contains('TEL:+15145550000,274\n'),
        );
      });

      test('the phone and email types become TYPE= parameters', () {
        for (final (choice, expected) in [
          ('Mobile', 'TEL;TYPE=CELL:5550000'),
          ('Home', 'TEL;TYPE=HOME:5550000'),
          ('Work', 'TEL;TYPE=WORK:5550000'),
          ('Other', 'TEL:5550000'),
        ]) {
          expect(
            format.buildQrString({'phone': '5550000', 'phone_type': choice}),
            contains(expected),
          );
        }
        for (final (choice, expected) in [
          ('Home', 'EMAIL;TYPE=HOME:a@x.io'),
          ('Work', 'EMAIL;TYPE=WORK:a@x.io'),
          ('Other', 'EMAIL:a@x.io'),
        ]) {
          expect(
            format.buildQrString({'email': 'a@x.io', 'email_type': choice}),
            contains(expected),
          );
        }
      });

      test('a type with no number or address adds nothing', () {
        expect(
          format.buildQrString({'phone_type': 'Work', 'email_type': 'Work'}),
          isNot(contains('TYPE=')),
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

      test('a pasted newline stays inside the ADR: property', () {
        final payload = format.buildQrString({'street': '12 Baker St\nFlat 2'});
        expect(payload, contains(r'ADR:;;12 Baker St\nFlat 2;;;;'));
        // BEGIN, VERSION, N, FN, ADR, END — a raw newline would add a seventh.
        expect(payload.split('\n'), hasLength(6));
      });

      test('a carriage return or CRLF also becomes a literal \\n', () {
        expect(
          format.buildQrString({'street': 'a\r\nb\rc'}),
          contains(r'ADR:;;a\nb\nc;;;;'),
        );
      });

      test('a semicolon inside an address part does not split ADR:', () {
        expect(
          format.buildQrString({'street': 'Unit 4; Rear'}),
          contains(r'ADR:;;Unit 4\; Rear;;;;'),
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
