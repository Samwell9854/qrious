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

    test('a phone pause stays as typed', () {
      expect(
        format.buildQrString({
          'first_name': 'Ada',
          'phone': '+15145550000,274',
        }),
        contains('TEL:+15145550000,274;'),
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

  group('MeCardFormat.parse', () {
    test('reads back what it builds, escapes included', () {
      final values = {
        'first_name': r'A;n,a',
        'last_name': r'B\b',
        'phone': '+1 555 000 0000',
        'email': 'a@example.com',
        'url': r'https://example.com/a\;b',
        'street': '1, Main; St',
        'city': 'Town',
        'region': 'QC',
        'postal_code': 'H0H 0H0',
        'country': 'CA',
      };
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, values);
      expect(parsed.unsupported, isEmpty);
    });

    test('ignores the prefix case', () {
      expect(format.parse('mecard:N:Doe,Jo;;')!.values['last_name'], 'Doe');
    });

    test('reads a lone name as the first name', () {
      final values = format.parse('MECARD:N:Jo;;')!.values;
      expect(values['first_name'], 'Jo');
      expect(values['last_name'], '');
    });

    test('lists what the form lacks, once each', () {
      final parsed = format.parse(
        'MECARD:N:Doe,Jo;NICKNAME:J;BDAY:19900101;TEL:111;TEL:222;TEL-AV:333;'
        'NOTE:x;NOTE:y;SOUND:z;;',
      )!;
      expect(parsed.values['phone'], '111');
      expect(parsed.unsupported, [
        'NICKNAME',
        'BDAY',
        'TEL',
        'TEL-AV',
        'NOTE',
        'SOUND',
      ]);
    });

    test('lists a PO box and extended address', () {
      final parsed = format.parse('MECARD:N:Jo;ADR:box,ext,Street,City;;')!;
      expect(parsed.values['street'], 'Street');
      expect(parsed.unsupported, ['ADR (PO box)', 'ADR (extended address)']);
    });

    test('does not throw on malformed input', () {
      for (final payload in [
        'MECARD:',
        'MECARD:;;',
        r'MECARD:N:a\',
        'MECARD:x',
      ]) {
        expect(() => format.parse(payload), returnsNormally);
      }
    });

    test('returns null for another prefix', () {
      expect(format.parse('WIFI:S:x;;'), isNull);
      expect(format.parse('BEGIN:VCARD'), isNull);
    });
  });
}
