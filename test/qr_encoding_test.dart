import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/qr_encoding.dart';

/// The smallest version that holds [data] at [level], straight from the package.
int versionAt(String data, ErrorCorrection level) =>
    QrCode.fromData(data: data, errorCorrectLevel: level.qrLevel!).typeNumber;

void main() {
  group('a chosen level', () {
    test('is used as given', () {
      for (final level in ErrorCorrection.values.skip(1)) {
        final qr = encodeQr('https://example.com', level);
        expect(qr.errorCorrection, level);
        expect(qr.version, versionAt('https://example.com', level));
      }
    });

    test('throws when the payload does not fit the largest symbol', () {
      // Version 40 holds 2331 bytes at medium.
      expect(
        () => encodeQr('x' * 2500, ErrorCorrection.medium),
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
}
