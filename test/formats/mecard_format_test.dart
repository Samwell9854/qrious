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
          'address': '12 Analytical Row',
        }),
        'MECARD:N:Ada;TEL:+15550000000;URL:https\\://example.com;'
        'ADR:12 Analytical Row;;',
      );
    });

    test('escapes structure characters inside values', () {
      expect(
        format.buildQrString({'first_name': r'A;b,c:d\e'}),
        r'MECARD:N:A\;b\,c\:d\\e;;',
      );
    });

    test('turns a pasted line break into a space', () {
      expect(
        format.buildQrString({
          'first_name': 'Ada',
          'address': '1 Row\r\nLondon',
        }),
        'MECARD:N:Ada;ADR:1 Row London;;',
      );
    });
  });
}
