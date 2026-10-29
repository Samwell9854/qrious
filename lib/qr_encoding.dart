import 'package:qr_flutter/qr_flutter.dart';

import 'qr_segments.dart';

/// The error-correction choices offered to the user.
///
/// The QR spec defines exactly four levels, each restoring a fixed share of a
/// damaged symbol. The names here are the beginner wording; expert mode puts the
/// spec letters (L, M, Q, H) in front of them.
enum ErrorCorrection {
  auto('Auto', null, null, null),
  low('Low', 'L', QrErrorCorrectLevel.L, 7),
  medium('Medium', 'M', QrErrorCorrectLevel.M, 15),
  high('High', 'Q', QrErrorCorrectLevel.Q, 25),
  highest('Highest', 'H', QrErrorCorrectLevel.H, 30);

  const ErrorCorrection(
    this.label,
    this.letter,
    this.qrLevel,
    this.recoveryPercent,
  );

  final String label;

  /// The spec's name for the level; null for [auto].
  final String? letter;

  /// The `qr` package's constant for this level; null for [auto], which resolves
  /// to one of the others per payload.
  final int? qrLevel;

  /// Roughly how much of the symbol can be damaged and still read.
  final int? recoveryPercent;

  /// How the level is offered in a menu: `High (25%)`, or `Q – High (25%)` in
  /// expert mode. Auto is `Auto` in both.
  String choiceLabel({required bool expert}) =>
      switch ((letter, recoveryPercent)) {
        (final letter?, final percent?) =>
          expert ? '$letter – $label ($percent%)' : '$label ($percent%)',
        _ => label,
      };
}

/// A payload encoded into a QR symbol, with the choices it ended up at.
class EncodedQr {
  EncodedQr._(this.code, this.errorCorrection, this.segments)
    : image = QrImage(code);

  final QrCode code;

  /// The module matrix: which squares are dark.
  final QrImage image;

  /// The level actually used; never [ErrorCorrection.auto].
  final ErrorCorrection errorCorrection;

  /// The payload as written, run by run in each run's mode.
  final List<QrSegment> segments;

  /// The symbol version, 1 to 40, which fixes its size.
  int get version => code.typeNumber;

  /// Modules along one side, excluding the quiet zone.
  int get moduleCount => code.moduleCount;

  /// The mask pattern, 0 to 7, that the matrix was drawn with.
  int get mask => image.maskPattern;
}

/// What [ErrorCorrection.auto] guarantees when the payload allows it.
const _autoFloor = ErrorCorrection.medium;

const _strongestFirst = [
  ErrorCorrection.highest,
  ErrorCorrection.high,
  ErrorCorrection.medium,
  ErrorCorrection.low,
];

/// Encodes [data] at [choice], throwing [InputTooLongException] when it does not
/// fit even the largest symbol at that level.
///
/// The payload is split into runs of numeric, alphanumeric and byte mode wherever
/// that is shorter than writing it all as bytes (see `qr_segments.dart`), so digits
/// and upper-case text take the room the spec says they need and no more.
///
/// [ErrorCorrection.auto] takes the smallest symbol that holds [data] at medium
/// (or at low, when medium cannot hold it at all), then raises the level as far as
/// it goes without needing a larger symbol. A symbol's size comes in fixed steps
/// and the room a payload does not use is filled with padding, so the stronger
/// level spends that padding on repair data and costs nothing in size or density.
EncodedQr encodeQr(String data, ErrorCorrection choice) {
  final level = switch (choice) {
    ErrorCorrection.auto => _resolveAuto(data),
    _ => choice,
  };
  final fit = _fit(data, level);
  if (fit == null) {
    final segments = segmentsFor(data, 40);
    throw InputTooLongException(
      bitLength(segments, 40),
      dataCapacityBits(40, level.qrLevel!),
    );
  }
  final (version, segments) = fit;
  final code = QrCode(version, level.qrLevel!);
  addSegments(code, segments);
  return EncodedQr._(code, level, segments);
}

ErrorCorrection _resolveAuto(String data) {
  final floor = _fit(data, _autoFloor) != null
      ? _autoFloor
      : ErrorCorrection.low;
  final base = _fit(data, floor);
  if (base == null) {
    // Too long at every level; encoding at low throws the exception that says so.
    return ErrorCorrection.low;
  }
  return _strongestFirst.firstWhere((level) {
    final fit = _fit(data, level);
    return fit != null && fit.$1 <= base.$1;
  });
}

/// The smallest version that holds [data] at [level], with the runs it is written
/// in there, or null when none does.
(int, List<QrSegment>)? _fit(String data, ErrorCorrection level) {
  // The best split depends on the version only through the width of the count
  // fields, which changes twice, so there are three splits to work out at most.
  List<QrSegment>? segments;
  for (var version = 1; version <= 40; version++) {
    if (segments == null || version == 10 || version == 27) {
      segments = segmentsFor(data, version);
    }
    if (bitLength(segments, version) <=
        dataCapacityBits(version, level.qrLevel!)) {
      return (version, segments);
    }
  }
  return null;
}
