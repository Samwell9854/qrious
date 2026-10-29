import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/qr_decoding.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_segments.dart';

/// The smallest version that holds [data] at [level], straight from the package.
int versionAt(String data, ErrorCorrection level) =>
    QrCode.fromData(data: data, errorCorrectLevel: level.qrLevel!).typeNumber;

/// What a reader makes of [qr], drawn black on white at 4 pixels per module.
List<String> readBack(EncodedQr qr) {
  const unit = 4, quiet = 4;
  final side = (qr.moduleCount + 2 * quiet) * unit;
  final image = img.Image(width: side, height: side, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var r = 0; r < qr.moduleCount; r++) {
    for (var c = 0; c < qr.moduleCount; c++) {
      if (!qr.image.isDark(r, c)) continue;
      img.fillRect(
        image,
        x1: (c + quiet) * unit,
        y1: (r + quiet) * unit,
        x2: (c + quiet + 1) * unit - 1,
        y2: (r + quiet + 1) * unit - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return decodeQrCodes(img.encodePng(image));
}

void main() {
  group('segments', () {
    test('digits and upper case take less room than bytes', () {
      final digits = encodeQr('1' * 40, ErrorCorrection.low);
      expect(digits.segments, [QrSegment(EncodingMode.numeric, '1' * 40)]);
      expect(digits.version, 1);
      expect(versionAt('1' * 40, ErrorCorrection.low), 3);
    });

    test('a long digit run in text gets a run of its own', () {
      final qr = encodeQr(
        'WIFI:T:WPA;S:home;P:${'7' * 30};;',
        ErrorCorrection.medium,
      );
      expect(qr.segments.map((s) => s.mode), contains(EncodingMode.numeric));
    });

    // Lengths that land in each of the three widths of the count fields.
    for (final (name, data) in [
      ('numeric', '0123456789' * 3),
      ('alphanumeric', 'HELLO WORLD \$%*+-./:' * 2),
      ('mixed', 'Call +1 514 555 0000, code ABC-123, ${'9' * 25} ok'),
      ('non-ASCII', 'café ☕ 😀 Ünïcödé 123456789012'),
      ('mixed, version 10 to 26', 'Order 4711: ${'8' * 400} SHIPPED ' * 2),
      ('mixed, version 27 to 40', 'Serial ${'5' * 1500} BATCH-A1 note ' * 2),
    ]) {
      test('$name text reads back as written', () {
        final qr = encodeQr(data, ErrorCorrection.auto);
        expect(readBack(qr), [data], reason: 'version ${qr.version}');
        if (name.contains('version')) {
          final low = int.parse(name.split(' ')[2]);
          expect(qr.version, greaterThanOrEqualTo(low));
        }
      });
    }
  });

  group('a chosen level', () {
    test('is used as given', () {
      for (final level in ErrorCorrection.values.skip(1)) {
        final qr = encodeQr('https://example.com', level);
        expect(qr.errorCorrection, level);
        expect(qr.version, versionAt('https://example.com', level));
      }
    });

    test('gives way to the next weaker level that holds the payload', () {
      // Version 40 holds 2331 bytes at medium and 2953 at low.
      final qr = encodeQr('x' * 2500, ErrorCorrection.medium);
      expect(qr.errorCorrection, ErrorCorrection.low);
      expect(canEncode('x' * 2500, ErrorCorrection.medium), isFalse);
      expect(canEncode('x' * 2500, ErrorCorrection.low), isTrue);
    });

    test('throws when no level holds the payload', () {
      expect(
        () => encodeQr('x' * 3000, ErrorCorrection.medium),
        throwsA(isA<InputTooLongException>()),
      );
    });
  });

  group('auto', () {
    test('raises the level as far as the same symbol size allows', () {
      // 19 bytes: version 2 holds 26 at medium and 20 at high, but only 14 at
      // highest, so high is free and highest is not.
      final qr = encodeQr('https://example.com', ErrorCorrection.auto);
      expect(qr.version, 2);
      expect(qr.errorCorrection, ErrorCorrection.high);
    });

    test('never makes the symbol larger than medium would', () {
      for (final length in [1, 10, 20, 50, 100, 300, 1000, 2000]) {
        final data = 'x' * length;
        final qr = encodeQr(data, ErrorCorrection.auto);
        expect(
          qr.version,
          versionAt(data, ErrorCorrection.medium),
          reason: '$length bytes',
        );
        expect(
          qr.errorCorrection.index,
          greaterThanOrEqualTo(ErrorCorrection.medium.index),
          reason: '$length bytes',
        );
      }
    });

    test('drops to low only when medium cannot hold the payload at all', () {
      // Too long for medium at any version, so not just for the one low needs.
      final data = 'x' * 2500;
      final qr = encodeQr(data, ErrorCorrection.auto);
      expect(qr.errorCorrection, ErrorCorrection.low);
      expect(qr.version, versionAt(data, ErrorCorrection.low));
    });

    test('throws when nothing can hold the payload', () {
      expect(
        () => encodeQr('x' * 3000, ErrorCorrection.auto),
        throwsA(isA<InputTooLongException>()),
      );
    });
  });

  test('every level but auto names its recovery share', () {
    expect(ErrorCorrection.auto.recoveryPercent, isNull);
    expect(
      ErrorCorrection.values.skip(1).map((level) => level.recoveryPercent),
      [7, 15, 25, 30],
    );
  });

  group('expert choices', () {
    const data = 'https://example.com';

    test('a larger version than needed is used as given', () {
      final qr = encodeQr(data, ErrorCorrection.medium, version: 7);
      expect(qr.version, 7);
      expect(readBack(qr), [data]);
      expect(canEncode(data, ErrorCorrection.medium, version: 7), isTrue);
    });

    test('a version too small gives way to the smallest that fits', () {
      expect(canEncode(data, ErrorCorrection.highest, version: 1), isFalse);
      final qr = encodeQr(data, ErrorCorrection.highest, version: 1);
      expect(qr.version, encodeQr(data, ErrorCorrection.highest).version);
    });

    test(
      'auto at a chosen version raises the level as that version allows',
      () {
        final qr = encodeQr(data, ErrorCorrection.auto, version: 10);
        expect(qr.version, 10);
        expect(qr.errorCorrection, ErrorCorrection.highest);
      },
    );

    test('version 15 at H is never used, as the qr package draws it wrong', () {
      expect(canEncode(data, ErrorCorrection.highest, version: 15), isFalse);
      expect(encodeQr(data, ErrorCorrection.highest, version: 15).version, 16);
      final auto = encodeQr(data, ErrorCorrection.auto, version: 15);
      expect(auto.version, 15);
      expect(auto.errorCorrection, ErrorCorrection.high);
      expect(canEncode(data, ErrorCorrection.auto, version: 15), isTrue);
    });

    test('every mask is drawn as asked and reads back', () {
      for (var mask = 0; mask < 8; mask++) {
        final qr = encodeQr(data, ErrorCorrection.medium, mask: mask);
        expect(qr.mask, mask);
        expect(readBack(qr), [data], reason: 'mask $mask');
      }
    });

    test('a forced mode writes the whole payload in it', () {
      const digits = '0123456789';
      for (final mode in EncodingMode.values) {
        final qr = encodeQr(digits, ErrorCorrection.medium, mode: mode);
        expect(qr.mode, mode);
        expect(readBack(qr), [digits], reason: mode.name);
      }
    });

    test('a mode that cannot write the text gives way to the split', () {
      expect(
        canEncode(data, ErrorCorrection.medium, mode: EncodingMode.numeric),
        isFalse,
      );
      final qr = encodeQr(
        data,
        ErrorCorrection.medium,
        mode: EncodingMode.alphanumeric,
      );
      expect(qr.mode, EncodingMode.byte);
      expect(readBack(qr), [data]);
    });

    test('the largest version, every level, reads back', () {
      for (final level in ErrorCorrection.values.skip(1)) {
        final qr = encodeQr(data, level, version: 40);
        expect(qr.version, 40);
        expect(readBack(qr), [data], reason: level.name);
      }
    });
  });
}
