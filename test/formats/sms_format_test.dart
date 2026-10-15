import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/sms_format.dart';

void main() {
  final format = SmsFormat();

  group('SmsFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(format.buildQrString({}), 'SMSTO:');
    });

    test('omits the message when it is empty', () {
      expect(
        format.buildQrString({'phone': '+15550000000', 'message': ''}),
        'SMSTO:+15550000000',
      );
    });

    test('appends the message after a colon', () {
      expect(
        format.buildQrString({'phone': '+15550000000', 'message': 'On my way'}),
        'SMSTO:+15550000000:On my way',
      );
    });

    test('leaves colons in the message alone', () {
      expect(
        format.buildQrString({'phone': '5550000', 'message': 'Meet at 10:30'}),
        'SMSTO:5550000:Meet at 10:30',
      );
    });
  });

  group('SmsFormat.parse', () {
    test('reads back what it builds, colons in the message included', () {
      final values = {'phone': '+15550000000', 'message': 'a:b;c,d\\e'};
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, values);
      expect(parsed.unsupported, isEmpty);
    });

    test('reads a payload with no message', () {
      expect(format.parse('smsto:555')!.values, {
        'phone': '555',
        'message': '',
      });
    });

    test('does not throw on malformed input', () {
      for (final payload in ['SMSTO:', 'SMSTO::', 'SMSTO::::x']) {
        expect(() => format.parse(payload), returnsNormally);
      }
    });

    test('returns null for another prefix', () {
      expect(format.parse('sms:555?body=x'), isNull);
      expect(format.parse('tel:555'), isNull);
    });
  });
}
