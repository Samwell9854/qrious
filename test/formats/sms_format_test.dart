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
}
