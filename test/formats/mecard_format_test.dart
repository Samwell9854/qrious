import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/mecard_format.dart';

void main() {
  final format = MeCardFormat();

  group('MeCardFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(format.buildQrString({}), 'MECARD:N:;;');
    });

    test('a first name alone needs no separator', () {
      expect(format.buildQrString({'first_name': 'Ada'}), 'MECARD:N:Ada;;');
    });

    test('N: is last name first, separated by a comma', () {
      expect(
        format.buildQrString({'first_name': 'Ada', 'last_name': 'Lovelace'}),
        'MECARD:N:Lovelace,Ada;;',
      );
    });

    test('adds the optional properties that are filled in, in order', () {
      expect(
        format.buildQrString({
          'first_name': 'Ada',
          'phone': '+15550000000',
          'email': '',
          'url': 'https://example.com',
          'street': '12 Analytical Row',
        }),
        'MECARD:N:Ada;TEL:+15550000000;URL:https://example.com;'
        'ADR:,,12 Analytical Row,,,,;;',
      );
    });

    test('leaves the colon of a URL alone', () {
      expect(
        format.buildQrString({'first_name': 'Ada', 'url': 'https://google.ca'}),
        contains('URL:https://google.ca;'),
      );
    });

    test('each address part fills its own ADR: slot', () {
      expect(
        format.buildQrString({
          'first_name': 'Ada',
          'street': '10011 Renaude-Lapointe',
          'city': 'Anjou',
          'region': 'QC',
          'postal_code': 'H1H 1H1',
          'country': 'Canada',
        }),
        contains('ADR:,,10011 Renaude-Lapointe,Anjou,QC,H1H 1H1,Canada;'),
      );
    });

    test('a phone pause stays as typed; a wait is escaped', () {
      expect(
        format.buildQrString({
          'first_name': 'Ada',
          'phone': '+15145550000,274',
        }),
        contains('TEL:+15145550000,274;'),
      );
      expect(
        format.buildQrString({'first_name': 'Ada', 'phone': '5550000;1'}),
        contains(r'TEL:5550000\;1;'),
      );
    });

    test('escapes semicolons and backslashes everywhere', () {
      expect(
        format.buildQrString({'first_name': 'Ada', 'email': r'a;b\c@x.io'}),
        contains(r'EMAIL:a\;b\\c@x.io;'),
      );
    });

    test('escapes commas only where they separate components', () {
      expect(
        format.buildQrString({'first_name': 'A,b', 'street': '1, Row'}),
        r'MECARD:N:A\,b;ADR:,,1\, Row,,,,;;',
      );
    });

    test('turns a pasted line break into a space', () {
      expect(
        format.buildQrString({'first_name': 'Ada', 'street': '1 Row\r\nRear'}),
        'MECARD:N:Ada;ADR:,,1 Row Rear,,,,;;',
      );
    });
  });
}
