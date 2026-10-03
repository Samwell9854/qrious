import 'package:qr_flutter/qr_flutter.dart';

/// The error-correction choices offered to the user.
///
/// The QR spec defines exactly four levels, each restoring a fixed share of a
/// damaged symbol. The names here are the beginner wording; the spec letters (L, M,
/// Q, H) are kept for expert mode, which does not exist yet.
enum ErrorCorrection {
  auto('Auto', null, null),
  low('Low', QrErrorCorrectLevel.L, 7),
  medium('Medium', QrErrorCorrectLevel.M, 15),
  high('High', QrErrorCorrectLevel.Q, 25),
  highest('Highest', QrErrorCorrectLevel.H, 30);

  const ErrorCorrection(this.label, this.qrLevel, this.recoveryPercent);

  final String label;

  /// The `qr` package's constant for this level; null for [auto], which resolves
  /// to one of the others per payload.
  final int? qrLevel;

  /// Roughly how much of the symbol can be damaged and still read.
  final int? recoveryPercent;
}

/// A payload encoded into a QR symbol, with the error correction it ended up at.
class EncodedQr {
  EncodedQr._(this.code, this.errorCorrection) : image = QrImage(code);

  final QrCode code;

  /// The module matrix: which squares are dark.
  final QrImage image;

  /// The level actually used; never [ErrorCorrection.auto].
  final ErrorCorrection errorCorrection;

  /// The symbol version, 1 to 40, which fixes its size.
  int get version => code.typeNumber;

  /// Modules along one side, excluding the quiet zone.
  int get moduleCount => code.moduleCount;
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
  final code = QrCode.fromData(data: data, errorCorrectLevel: level.qrLevel!);
  return EncodedQr._(code, level);
}

ErrorCorrection _resolveAuto(String data) {
  final floor = _versionFor(data, _autoFloor) != null
      ? _autoFloor
      : ErrorCorrection.low;
  final base = _versionFor(data, floor);
  if (base == null) {
    // Too long at every level; encoding at low throws the exception that says so.
    return ErrorCorrection.low;
  }
  return _strongestFirst.firstWhere((level) {
    final version = _versionFor(data, level);
    return version != null && version <= base;
  });
}

/// The smallest version that holds [data] at [level], or null when none does.
int? _versionFor(String data, ErrorCorrection level) {
  final code = QrCode.fromData(data: data, errorCorrectLevel: level.qrLevel!);
  // The package stops searching at version 40 without checking that it fits;
  // building the matrix is what checks it.
  if (code.typeNumber == 40) {
    try {
      QrImage(code);
    } on InputTooLongException {
      return null;
    }
  }
  return code.typeNumber;
}
