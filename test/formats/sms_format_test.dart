import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/sms_format.dart';
import 'package:qrious/models/qr_field.dart';

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

  group('the sms: form', () {
    final uri = {'form': 'sms:', 'phone': '+1 555 000 0000'};

    test('writes the number without spaces, and the body encoded', () {
      expect(format.buildQrString(uri), 'sms:+15550000000');
      expect(
        format.buildQrString({...uri, 'message': 'On my way & 10:30?'}),
        'sms:+15550000000?body=On%20my%20way%20%26%2010%3A30%3F',
      );
    });

    test('writes every recipient, skipping a blank one', () {
      expect(
        format.buildQrString({
          ...uri,
          'recipients': '2',
          'recipients.0.number': '555 0001',
          'recipients.1.number': '',
        }),
        'sms:+15550000000,5550001',
      );
    });

    test('encodes # so it does not start a fragment', () {
      expect(
        format.buildQrString({'form': 'sms:', 'phone': '*123#'}),
        'sms:*123%23',
      );
    });

    test('reads back what it writes, recipients and body included', () {
      final values = {
        'form': 'sms:',
        'phone': '+15550000000',
        'recipients': '2',
        'recipients.0.number': '5550001',
        'recipients.1.number': '*12#',
        'message': 'a:b;c,d e?&=',
      };
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, {...values, 'apple': 'false'});
      expect(parsed.unsupported, isEmpty);
    });

    test("writes Apple's form only for several numbers when asked", () {
      final two = {
        ...uri,
        'recipients': '1',
        'recipients.0.number': '555 0001',
        'message': 'hi there',
      };
      expect(format.buildQrString(two), startsWith('sms:+15550000000,'));
      expect(
        format.buildQrString({...two, 'apple': 'true'}),
        'sms://open?addresses=+15550000000,5550001&body=hi%20there',
      );
      // One number opens everywhere in the standard form, so it keeps it.
      expect(
        format.buildQrString({...uri, 'apple': 'true'}),
        'sms:+15550000000',
      );
    });

    test("reads Apple's form back, with one slash or two", () {
      for (final payload in [
        'sms://open?addresses=+15550000000,5550001&body=hi%20there',
        'SMS:/open?body=hi%20there&addresses=+15550000000,5550001',
      ]) {
        final parsed = format.parse(payload)!;
        expect(parsed.values, {
          'form': 'sms:',
          'apple': 'true',
          'phone': '+15550000000',
          'recipients': '1',
          'recipients.0.number': '5550001',
          'message': 'hi there',
        });
        expect(parsed.unsupported, isEmpty);
      }
    });

    test("Apple's choice is expert, shown only with sms:", () {
      expect(
        QrForm.shown(format.fields, {
          'form': 'sms:',
        }, expert: true).map((f) => f.id),
        contains('apple'),
      );
      expect(
        QrForm.shown(format.fields, {
          'form': 'SMSTO:',
        }, expert: true).map((f) => f.id),
        isNot(contains('apple')),
      );
      expect(
        QrForm.shown(format.fields, {
          'form': 'sms:',
        }, expert: false).map((f) => f.id),
        isNot(contains('apple')),
      );
    });

    test('lists query parameters other than body', () {
      final parsed = format.parse('SMS:555?body=hi&foo=1')!;
      expect(parsed.values['message'], 'hi');
      expect(parsed.unsupported, ['foo']);
    });

    test('is written only in expert mode, extra recipients only with it', () {
      final fields = format.fields;
      final values = {
        ...uri,
        'recipients': '1',
        'recipients.0.number': '5550001',
      };
      expect(
        format.buildQrString(QrForm.applied(fields, values, expert: false)),
        'SMSTO:+1 555 000 0000',
      );
      final smsto = {...values, 'form': 'SMSTO:'};
      expect(
        QrForm.shown(fields, smsto, expert: true).map((f) => f.id),
        isNot(contains('recipients')),
      );
    });

    test('numbers take no pause, which would split a recipient', () {
      expect(SmsFormat.validateSmsNumber('555,123'), isNotNull);
      expect(SmsFormat.validateSmsNumber('+1 (555) 000-0000'), isNull);
    });
  });

  group('SmsFormat.parse', () {
    test('reads back what it builds, colons in the message included', () {
      final values = {'phone': '+15550000000', 'message': 'a:b;c,d\\e'};
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, {
        ...values,
        'form': 'SMSTO:',
        'recipients': '0',
        'apple': 'false',
      });
      expect(parsed.unsupported, isEmpty);
    });

    test('reads a payload with no message', () {
      expect(format.parse('smsto:555')!.values, {
        'form': 'SMSTO:',
        'phone': '555',
        'recipients': '0',
        'apple': 'false',
        'message': '',
      });
    });

    test('does not throw on malformed input', () {
      for (final payload in ['SMSTO:', 'SMSTO::', 'SMSTO::::x']) {
        expect(() => format.parse(payload), returnsNormally);
      }
    });

    test('returns null for another prefix', () {
      expect(format.parse('tel:555'), isNull);
      expect(format.parse('smsx:555'), isNull);
    });
  });
}
