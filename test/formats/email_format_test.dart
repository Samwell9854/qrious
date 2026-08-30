import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/email_format.dart';

void main() {
  final format = EmailFormat();

  group('EmailFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(format.buildQrString({}), 'mailto:');
    });

    test('an address alone produces a bare mailto:', () {
      expect(
        format.buildQrString({'to': 'ada@example.com'}),
        'mailto:ada%40example.com',
      );
    });

    test('a subject becomes the only query parameter', () {
      expect(
        format.buildQrString({'to': 'ada@example.com', 'subject': 'Hello'}),
        'mailto:ada%40example.com?subject=Hello',
      );
    });

    test('a body becomes the only query parameter', () {
      expect(
        format.buildQrString({'to': 'ada@example.com', 'body': 'Hi'}),
        'mailto:ada%40example.com?body=Hi',
      );
    });

    test('subject and body are joined with &, subject first', () {
      expect(
        format.buildQrString({
          'to': 'ada@example.com',
          'subject': 'Hello',
          'body': 'Hi',
        }),
        'mailto:ada%40example.com?subject=Hello&body=Hi',
      );
    });

    test('empty optional fields are omitted, and so is the ? separator', () {
      expect(
        format.buildQrString({
          'to': 'ada@example.com',
          'subject': '',
          'body': '',
        }),
        'mailto:ada%40example.com',
      );
    });

    group('URI encoding', () {
      test('encodes spaces and punctuation in the subject', () {
        expect(
          format.buildQrString({'subject': 'Q3 report & notes'}),
          'mailto:?subject=Q3%20report%20%26%20notes',
        );
      });

      test('encodes newlines in the body', () {
        expect(
          format.buildQrString({'body': 'line one\nline two'}),
          'mailto:?body=line%20one%0Aline%20two',
        );
      });

      test('encodes a value that would otherwise open a new parameter', () {
        expect(
          format.buildQrString({'subject': 'a&body=injected'}),
          'mailto:?subject=a%26body%3Dinjected',
        );
      });
    });
  });
}
