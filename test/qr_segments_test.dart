import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/qr_segments.dart';

const _levels = [
  QrErrorCorrectLevel.L,
  QrErrorCorrectLevel.M,
  QrErrorCorrectLevel.Q,
  QrErrorCorrectLevel.H,
];

String _joined(List<QrSegment> s) => s.map((e) => e.text).join();

int _best(String data, int version) => EncodingMode.values
    .where((m) => m.canHold(data))
    .map((m) => bitLength([QrSegment(m, data)], version))
    .reduce((a, b) => a < b ? a : b);

void main() {
  group('canHold', () {
    test('numeric', () {
      expect(EncodingMode.numeric.canHold('0123456789'), isTrue);
      expect(EncodingMode.numeric.canHold('12a'), isFalse);
      expect(EncodingMode.numeric.canHold('1 2'), isFalse);
    });

    test('alphanumeric', () {
      expect(EncodingMode.alphanumeric.canHold('HELLO WORLD'), isTrue);
      expect(EncodingMode.alphanumeric.canHold(r'0-9 $%*+-./:'), isTrue);
      expect(EncodingMode.alphanumeric.canHold('Hello'), isFalse);
      expect(EncodingMode.alphanumeric.canHold('A_B'), isFalse);
      expect(EncodingMode.alphanumeric.canHold('é'), isFalse);
    });

    test('byte takes anything', () {
      expect(EncodingMode.byte.canHold('café ☕ 😀'), isTrue);
    });

    test('empty text fits every mode', () {
      for (final m in EncodingMode.values) {
        expect(m.canHold(''), isTrue);
      }
    });
  });

  group('bitLength', () {
    test('known values', () {
      const numeric = QrSegment(EncodingMode.numeric, '01234567');
      const alnum = QrSegment(EncodingMode.alphanumeric, 'AC-42');
      expect(bitLength([numeric], 1), 4 + 10 + 27);
      expect(bitLength([alnum], 1), 4 + 9 + 28);
      expect(bitLength([const QrSegment(EncodingMode.byte, 'abc')], 1), 36);
      expect(bitLength([], 1), 0);
    });

    test('numeric and alphanumeric remainders', () {
      int n(String s) =>
          bitLength([QrSegment(EncodingMode.numeric, s)], 1) - 14;
      expect([n('1'), n('12'), n('123'), n('1234')], [4, 7, 10, 14]);
      int a(String s) =>
          bitLength([QrSegment(EncodingMode.alphanumeric, s)], 1) - 13;
      expect([a('A'), a('AB'), a('ABC')], [6, 11, 17]);
    });

    test('header widths change at 10 and 27', () {
      for (final (mode, text, widths) in [
        (EncodingMode.numeric, '1', [10, 12, 14]),
        (EncodingMode.alphanumeric, 'A', [9, 11, 13]),
        (EncodingMode.byte, 'a', [8, 16, 16]),
      ]) {
        final body = bitLength([QrSegment(mode, text)], 1) - 4 - widths[0];
        for (final (versions, width) in [
          ([1, 9], widths[0]),
          ([10, 26], widths[1]),
          ([27, 40], widths[2]),
        ]) {
          for (final v in versions) {
            expect(
              bitLength([QrSegment(mode, text)], v),
              4 + width + body,
              reason: '$mode v$v',
            );
          }
        }
      }
    });

    test('byte counts UTF-8 bytes', () {
      const s = QrSegment(EncodingMode.byte, 'café ☕ 😀');
      expect(utf8.encode(s.text).length, 5 + 1 + 3 + 1 + 4);
      expect(bitLength([s], 1), 4 + 8 + 8 * utf8.encode(s.text).length);
    });
  });

  group('segmentsFor', () {
    test('digits are one numeric segment', () {
      expect(segmentsFor('0123456789', 1), [
        const QrSegment(EncodingMode.numeric, '0123456789'),
      ]);
    });

    test('upper case is one alphanumeric segment', () {
      expect(segmentsFor('HELLO WORLD', 1), [
        const QrSegment(EncodingMode.alphanumeric, 'HELLO WORLD'),
      ]);
    });

    test('lower case is byte', () {
      expect(segmentsFor('hello world', 1), [
        const QrSegment(EncodingMode.byte, 'hello world'),
      ]);
    });

    test('empty data gives no segments', () {
      expect(segmentsFor('', 5), isEmpty);
      expect(segmentsFor('', 5, forced: EncodingMode.byte), isEmpty);
    });

    test('a long digit run after text splits', () {
      final digits = '1234567890' * 3;
      expect(segmentsFor('Password: $digits', 1), [
        const QrSegment(EncodingMode.byte, 'Password: '),
        QrSegment(EncodingMode.numeric, digits),
      ]);
    });

    test('a short digit run inside text stays byte', () {
      expect(segmentsFor('abc 42 def', 1), [
        const QrSegment(EncodingMode.byte, 'abc 42 def'),
      ]);
    });

    test('forced gives one segment', () {
      expect(segmentsFor('12345', 1, forced: EncodingMode.byte), [
        const QrSegment(EncodingMode.byte, '12345'),
      ]);
      expect(segmentsFor('12345', 1, forced: EncodingMode.alphanumeric), [
        const QrSegment(EncodingMode.alphanumeric, '12345'),
      ]);
    });

    test('non-ASCII stays whole and byte', () {
      const text = 'café ☕ 😀';
      final s = segmentsFor(text, 1);
      expect(s, [const QrSegment(EncodingMode.byte, text)]);
      expect(bitLength(s, 1), 4 + 8 + 8 * utf8.encode(text).length);
    });

    test('never splits a surrogate pair', () {
      for (final text in ['😀' * 5, '1234567890123😀1234567890123', 'A😀B']) {
        for (final v in [1, 10, 27]) {
          for (final s in segmentsFor(text, v)) {
            expect(() => utf8.encode(s.text), returnsNormally);
            expect(s.text.runes.toList(), isNot(contains(0xFFFD)));
            expect(
              String.fromCharCodes(s.text.runes),
              s.text,
              reason: 'whole code points',
            );
          }
          expect(_joined(segmentsFor(text, v)), text);
        }
      }
    });

    test('concatenates back and never beats the single best mode', () {
      const samples = [
        'HELLO WORLD 1234567890123456',
        'https://example.com/path?q=1234567890123456789',
        'WIFI:T:WPA;S:Net;P:abc12345;;',
        'abcDEF123456789012345678901234567890xyz',
        'A1B2C3 d4e5f6 0000000000 ZZZZ',
        'x',
        '9',
        'ÀÉ12345678901234567890',
      ];
      for (final text in samples) {
        for (final v in [1, 9, 10, 26, 27, 40]) {
          final s = segmentsFor(text, v);
          expect(_joined(s), text);
          expect(
            bitLength(s, v),
            lessThanOrEqualTo(_best(text, v)),
            reason: '$text v$v',
          );
        }
      }
    });

    test('is optimal against brute force on short strings', () {
      // Every partition into runs with every mode assignment, for short mixed text.
      int brute(List<String> chars, int v) {
        var best = 1 << 30;
        final n = chars.length;
        for (var cuts = 0; cuts < 1 << (n - 1); cuts++) {
          final parts = <String>[];
          var cur = chars[0];
          for (var i = 1; i < n; i++) {
            if (cuts >> (i - 1) & 1 == 1) {
              parts.add(cur);
              cur = '';
            }
            cur += chars[i];
          }
          parts.add(cur);
          // Cheapest mode that holds each part.
          var total = 0;
          for (final p in parts) {
            total += EncodingMode.values
                .where((m) => m.canHold(p))
                .map((m) => bitLength([QrSegment(m, p)], v))
                .reduce((a, b) => a < b ? a : b);
          }
          if (total < best) best = total;
        }
        return best;
      }

      const samples = [
        'ab123456cd',
        'AB12345678c',
        'A1234567890B',
        'x1234567890123y',
        'HELLO1234abc',
        'ZZ 99999999 zz',
      ];
      for (final text in samples) {
        for (final v in [1, 10, 27]) {
          final chars = text.split('');
          expect(
            bitLength(segmentsFor(text, v), v),
            brute(chars, v),
            reason: '$text v$v',
          );
        }
      }
    });

    test('handles 3000 characters quickly', () {
      final text = List.generate(
        3000,
        (i) => i % 50 < 20 ? '${i % 10}' : (i % 50 < 35 ? 'A' : 'a'),
      ).join();
      final watch = Stopwatch()..start();
      final s = segmentsFor(text, 40);
      watch.stop();
      expect(_joined(s), text);
      // It runs on every keystroke, in a few ms; the bound is loose so that a busy
      // machine does not fail it, and catches only a cost that grows out of hand.
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('dataCapacityBits', () {
    test('spot values', () {
      expect(dataCapacityBits(1, QrErrorCorrectLevel.L), 19 * 8);
      expect(dataCapacityBits(1, QrErrorCorrectLevel.H), 9 * 8);
      expect(dataCapacityBits(40, QrErrorCorrectLevel.L), 2956 * 8);
      expect(dataCapacityBits(40, QrErrorCorrectLevel.H), 1276 * 8);
    });

    test('a byte payload that exactly fills builds, one more throws', () {
      for (final level in _levels) {
        for (var v = 1; v <= 40; v++) {
          final capacity = dataCapacityBits(v, level);
          var n = 0;
          while (bitLength([QrSegment(EncodingMode.byte, 'a' * (n + 1))], v) <=
              capacity) {
            n++;
          }
          QrImage.withMaskPattern(QrCode(v, level)..addData('a' * n), 0);
          expect(
            () => QrImage.withMaskPattern(
              QrCode(v, level)..addData('a' * (n + 1)),
              0,
            ),
            throwsA(isA<InputTooLongException>()),
            reason: 'v$v level $level',
          );
        }
      }
    });
  });

  group('addSegments', () {
    test('a mixed payload builds at the version bitLength finds', () {
      const data =
          'Password: abcXYZ 12345678901234567890123456789012 HELLO WORLD';
      const level = QrErrorCorrectLevel.M;
      for (var v = 1; v <= 40; v++) {
        final segments = segmentsFor(data, v);
        if (bitLength(segments, v) > dataCapacityBits(v, level)) continue;
        final code = QrCode(v, level);
        addSegments(code, segments);
        expect(() => QrImage.withMaskPattern(code, 0), returnsNormally);
        return;
      }
      fail('no version fits');
    });

    test('41 digits fit v1-L as numeric but not as bytes', () {
      final digits = '1' * 41;
      const level = QrErrorCorrectLevel.L;
      final numeric = QrCode(1, level);
      addSegments(numeric, [QrSegment(EncodingMode.numeric, digits)]);
      expect(() => QrImage.withMaskPattern(numeric, 0), returnsNormally);

      final bytes = QrCode(1, level);
      addSegments(bytes, [QrSegment(EncodingMode.byte, digits)]);
      expect(
        () => QrImage.withMaskPattern(bytes, 0),
        throwsA(isA<InputTooLongException>()),
      );
    });
  });
}
