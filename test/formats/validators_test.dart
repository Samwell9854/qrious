import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/validators.dart';

void main() {
  group('validateEmail', () {
    test('accepts ordinary and plus-addressed addresses', () {
      expect(validateEmail('a@example.com'), isNull);
      expect(validateEmail('first.last+tag@sub.example.co.uk'), isNull);
      expect(validateEmail('  a@example.com  '), isNull);
    });

    test('rejects what no mail server would take', () {
      expect(validateEmail('example.com'), isNotNull);
      expect(validateEmail('a@example'), isNotNull);
      expect(validateEmail('a b@example.com'), isNotNull);
      expect(validateEmail('a@@example.com'), isNotNull);
    });
  });

  group('validateUrl', () {
    test('accepts an absolute URL', () {
      expect(validateUrl('https://example.com'), isNull);
      expect(validateUrl('http://example.com/a?b=c#d'), isNull);
    });

    test('rejects a scheme-less host, which scans as plain text', () {
      expect(validateUrl('example.com'), isNotNull);
      expect(validateUrl('www.example.com/path'), isNotNull);
    });

    test('rejects whitespace and schemes with no host', () {
      expect(validateUrl('https://exa mple.com'), isNotNull);
      expect(validateUrl('https://'), isNotNull);
    });
  });

  group('validatePhone', () {
    test('accepts the punctuation people actually type', () {
      expect(validatePhone('+1 555 000 0000'), isNull);
      expect(validatePhone('(555) 000-0000'), isNull);
      expect(validatePhone('5550000000'), isNull);
    });

    test('rejects letters and too few digits', () {
      expect(validatePhone('555-CALL'), isNotNull);
      expect(validatePhone('12'), isNotNull);
    });
  });

  group('validateSsid', () {
    test('accepts a name at the 32-byte limit', () {
      expect(validateSsid('a' * 32), isNull);
    });

    test('counts bytes, not characters', () {
      // 16 three-byte characters is 48 bytes, well under 32 characters.
      expect(validateSsid('あ' * 16), isNotNull);
      expect(validateSsid('あ' * 10), isNull);
      expect(validateSsid('a' * 33), isNotNull);
    });
  });
}
