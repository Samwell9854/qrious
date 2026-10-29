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
  EncodedQr._(this.code, this.image, this.errorCorrection, this.segments);

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

  /// The one mode the whole payload is written in, or null when it is split.
  EncodingMode? get mode => switch (segments) {
    [final only] => only.mode,
    _ => null,
  };
}

/// What [ErrorCorrection.auto] guarantees when the payload allows it.
const _autoFloor = ErrorCorrection.medium;

const _strongestFirst = [
  ErrorCorrection.highest,
  ErrorCorrection.high,
  ErrorCorrection.medium,
  ErrorCorrection.low,
];

/// Encodes [data] as asked, or as near to it as [data] allows, throwing
/// [InputTooLongException] only when no symbol can hold it at all.
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
///
/// The expert choices are null for automatic. [version] is the smallest version to
/// use, [mask] the mask pattern, and [mode] one mode for the whole payload. A choice
/// that [data] cannot take gets the nearest that it can: a mode it cannot be written
/// in gives way to the automatic split, a level it is too long for to the next weaker
/// one, and a version too small for it to the next larger one. What was used is on the
/// result, for the caller to compare with what was asked; [canEncode] says beforehand
/// whether a choice can be taken as it is.
EncodedQr encodeQr(
  String data,
  ErrorCorrection choice, {
  int? version,
  int? mask,
  EncodingMode? mode,
}) {
  final from = version ?? 1;
  final forced =
      mode != null && _fit(data, ErrorCorrection.low, mode, 1) != null
      ? mode
      : null;
  final level = switch (choice) {
    ErrorCorrection.auto => _resolveAuto(data, forced, from),
    _ =>
      _strongestFirst
          .skipWhile((level) => level != choice)
          .firstWhere(
            (level) => _fit(data, level, forced, from) != null,
            orElse: () => choice,
          ),
  };
  final fit = _fit(data, level, forced, from);
  if (fit == null) {
    final segments = segmentsFor(data, 40);
    throw InputTooLongException(
      bitLength(segments, 40),
      dataCapacityBits(40, ErrorCorrection.low.qrLevel!),
    );
  }
  final (fitted, segments) = fit;
  final code = QrCode(fitted, level.qrLevel!);
  addSegments(code, segments);
  final image = mask == null
      ? QrImage(code)
      : QrImage.withMaskPattern(code, mask);
  return EncodedQr._(code, image, level, segments);
}

/// Whether [data] can be encoded exactly as asked, with no choice giving way: at
/// [level] (any, for auto), at exactly [version] when one is given, and all in [mode]
/// when one is given. The mask is not asked about, because every mask fits.
bool canEncode(
  String data,
  ErrorCorrection level, {
  int? version,
  EncodingMode? mode,
}) {
  if (mode != null && !mode.canHold(data)) return false;
  final levels = level == ErrorCorrection.auto ? _strongestFirst : [level];
  return levels.any((level) {
    if (version == null) return _fit(data, level, mode, 1) != null;
    return _holds(data, level, mode, version) != null;
  });
}

ErrorCorrection _resolveAuto(String data, EncodingMode? mode, int from) {
  final floor = _fit(data, _autoFloor, mode, from) != null
      ? _autoFloor
      : ErrorCorrection.low;
  final base = _fit(data, floor, mode, from);
  if (base == null) {
    // Too long at every level; encoding at low throws the exception that says so.
    return ErrorCorrection.low;
  }
  return _strongestFirst.firstWhere((level) {
    final fit = _fit(data, level, mode, from);
    return fit != null && fit.$1 <= base.$1;
  });
}

/// The smallest version from [from] up that holds [data] at [level], all in [mode]
/// when given, with the runs it is written in there; null when none does.
(int, List<QrSegment>)? _fit(
  String data,
  ErrorCorrection level,
  EncodingMode? mode,
  int from,
) {
  if (mode != null && !mode.canHold(data)) return null;
  // The best split depends on the version only through the width of the count
  // fields, which changes twice, so there are three splits to work out at most.
  List<QrSegment>? segments;
  for (var version = from; version <= 40; version++) {
    if (segments == null || version == 10 || version == 27) {
      segments = _segments(data, version, mode);
    }
    if (_room(level, version) case final room?
        when bitLength(segments, version) <= room) {
      return (version, segments);
    }
  }
  return null;
}

/// The runs [data] is written in at exactly [version], or null when it does not fit.
List<QrSegment>? _holds(
  String data,
  ErrorCorrection level,
  EncodingMode? mode,
  int version,
) {
  final segments = _segments(data, version, mode);
  final room = _room(level, version);
  return room != null && bitLength(segments, version) <= room ? segments : null;
}

/// The data bits [version] holds at [level], or null where the `qr` package cannot
/// draw a readable symbol, which is then never chosen.
int? _room(ErrorCorrection level, int version) =>
    brokenInQrPackage(version, level.qrLevel!)
    ? null
    : dataCapacityBits(version, level.qrLevel!);

/// [segmentsFor], remembered for the last payload. The split depends only on the
/// payload, the mode and which of the three count-field widths the version has, and
/// the screen asks about every version and mode on each keystroke to grey out the
/// ones that cannot be had, which would otherwise redo the same split 40 times.
List<QrSegment> _segments(String data, int version, EncodingMode? mode) {
  if (data != _cachedData) {
    _cache.clear();
    _cachedData = data;
  }
  final width = version < 10 ? 0 : (version < 27 ? 1 : 2);
  return _cache.putIfAbsent((
    width,
    mode,
  ), () => segmentsFor(data, version, forced: mode));
}

String? _cachedData;
final _cache = <(int, EncodingMode?), List<QrSegment>>{};
