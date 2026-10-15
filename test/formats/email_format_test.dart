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
        'mailto:ada@example.com',
      );
    });

    test('a subject becomes the only query parameter', () {
      expect(
        format.buildQrString({'to': 'ada@example.com', 'subject': 'Hello'}),
        'mailto:ada@example.com?subject=Hello',
      );
    });

    test('a body becomes the only query parameter', () {
      expect(
        format.buildQrString({'to': 'ada@example.com', 'body': 'Hi'}),
        'mailto:ada@example.com?body=Hi',
      );
    });

    test('subject and body are joined with &, subject first', () {
      expect(
        format.buildQrString({
          'to': 'ada@example.com',
          'subject': 'Hello',
          'body': 'Hi',
        }),
        'mailto:ada@example.com?subject=Hello&body=Hi',
      );
    });

    test('empty optional fields are omitted, and so is the ? separator', () {
      expect(
        format.buildQrString({
          'to': 'ada@example.com',
          'subject': '',
          'body': '',
        }),
        'mailto:ada@example.com',
      );
    });

    test('leaves @ and + literal in the address', () {
      // RFC 6068 allows both in the addr-spec, and %2B breaks plus-addressing
      // in enough clients to matter.
      expect(
        format.buildQrString({'to': 'ada+qr@example.com'}),
        'mailto:ada+qr@example.com',
      );
    });

    test('still encodes what is not allowed in an address', () {
      expect(
        format.buildQrString({'to': 'a b@example.com'}),
        'mailto:a%20b@example.com',
      );
    });

    test(
      'a + in the subject stays encoded, where it could read as a space',
      () {
        expect(
          format.buildQrString({'to': 'ada@example.com', 'subject': 'a+b'}),
          'mailto:ada@example.com?subject=a%2Bb',
        );
      },
    );

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

  group('EmailFormat.parse', () {
    test('reads back what it builds', () {
      final values = {
        'to': 'a+b@example.com',
        'subject': 'Hi & bye; 100%',
        'body': 'Line one\nLine two, ünï',
      };
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, values);
      expect(parsed.unsupported, isEmpty);
    });

    test('ignores the prefix case', () {
      expect(format.parse('MAILTO:a@b.co')!.values['to'], 'a@b.co');
    });

    test('lists headers the form lacks', () {
      final parsed = format.parse(
        'mailto:a@b.co?cc=c@d.co&subject=S&bcc=e@f.co&cc=x',
      )!;
      expect(parsed.values['subject'], 'S');
      expect(parsed.unsupported, ['cc', 'bcc']);
    });

    test('does not throw on malformed input', () {
      for (final payload in [
        'mailto:',
        'mailto:%zz?subject=%',
        'mailto:?&=&',
      ]) {
        expect(() => format.parse(payload), returnsNormally);
      }
    });

    test('returns null for another prefix', () {
      expect(format.parse('https://example.com'), isNull);
      expect(format.parse('a@b.co'), isNull);
    });
  });
}
