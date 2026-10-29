import 'dart:convert';

import 'package:qr_flutter/qr_flutter.dart';

/// The QR data modes Qrious writes. Kanji is not supported.
enum EncodingMode {
  numeric('Numeric'),
  alphanumeric('Alphanumeric'),
  byte('Byte');

  const EncodingMode(this.label);

  final String label;

  /// Whether every character of [text] can be written in this mode. Byte takes
  /// anything (as UTF-8). Empty text fits every mode.
  bool canHold(String text) => switch (this) {
    EncodingMode.numeric => text.runes.every(_isDigit),
    EncodingMode.alphanumeric => text.runes.every(_isAlphanumeric),
    EncodingMode.byte => true,
  };
}

bool _isDigit(int rune) => rune >= 0x30 && rune <= 0x39;

// The 45 characters of the spec's alphanumeric table. Upper case only.
const _alphanumericExtras = ' \$%*+-./:';

bool _isAlphanumeric(int rune) =>
    _isDigit(rune) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune < 0x80 && _alphanumericExtras.contains(String.fromCharCode(rune)));

/// A run of the payload written in one mode.
class QrSegment {
  const QrSegment(this.mode, this.text);

  final EncodingMode mode;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is QrSegment && other.mode == mode && other.text == text;

  @override
  int get hashCode => Object.hash(mode, text);

  @override
  String toString() => 'QrSegment(${mode.name}, "$text")';
}

// Width of the character-count field. It grows with the version, in three steps.
int _countBits(EncodingMode mode, int version) {
  final step = version < 10 ? 0 : (version < 27 ? 1 : 2);
  return switch (mode) {
    EncodingMode.numeric => const [10, 12, 14][step],
    EncodingMode.alphanumeric => const [9, 11, 13][step],
    EncodingMode.byte => const [8, 16, 16][step],
  };
}

const _modeIndicatorBits = 4;

/// The segments that write [data] in the fewest bits for a symbol of [version]
/// (1..40; the character-count field width depends on the version range 1–9, 10–26,
/// 27–40). With [forced], the whole payload is one segment in that mode (the caller
/// guarantees `forced.canHold(data)`). Empty data gives an empty list.
///
/// This is a dynamic programme over positions and modes, after Nayuki's
/// `makeSegmentsOptimally`: costs are kept in sixths of a bit so that 3.33 and 5.5
/// bits per character stay exact, and a run is rounded up to whole bits when the mode
/// changes after it.
List<QrSegment> segmentsFor(String data, int version, {EncodingMode? forced}) {
  if (data.isEmpty) return const [];
  if (forced != null) return [QrSegment(forced, data)];

  final runes = data.runes.toList();
  final n = runes.length;
  const modes = EncodingMode.values;
  const inf = 1 << 60;

  final header = [
    for (final m in modes) (_modeIndicatorBits + _countBits(m, version)) * 6,
  ];
  // Sixths of a bit one character costs in each mode.
  int charCost(EncodingMode m, int rune) => switch (m) {
    EncodingMode.numeric => 20,
    EncodingMode.alphanumeric => 33,
    EncodingMode.byte => utf8.encode(String.fromCharCode(rune)).length * 48,
  };
  bool fits(EncodingMode m, int rune) => switch (m) {
    EncodingMode.numeric => _isDigit(rune),
    EncodingMode.alphanumeric => _isAlphanumeric(rune),
    EncodingMode.byte => true,
  };

  // from[i * 3 + m]: the mode the best path was in at character i - 1, or -1 at
  // the start.
  final from = List<int>.filled(n * 3, -1);
  var costs = List<int>.filled(3, inf);
  for (var i = 0; i < n; i++) {
    final next = List<int>.filled(3, inf);
    for (var m = 0; m < 3; m++) {
      if (!fits(modes[m], runes[i])) continue;
      final cc = charCost(modes[m], runes[i]);
      if (i == 0) {
        next[m] = header[m] + cc;
        continue;
      }
      var best = inf;
      var bestFrom = -1;
      for (var p = 0; p < 3; p++) {
        if (costs[p] >= inf) continue;
        final c = p == m
            ? costs[p] + cc
            : (costs[p] + 5) ~/ 6 * 6 + header[m] + cc;
        if (c < best) {
          best = c;
          bestFrom = p;
        }
      }
      next[m] = best;
      from[i * 3 + m] = bestFrom;
    }
    costs = next;
  }

  var mode = 0;
  for (var m = 1; m < 3; m++) {
    if (costs[m] < costs[mode]) mode = m;
  }

  final pathModes = List<int>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    pathModes[i] = mode;
    mode = from[i * 3 + mode];
  }

  final segments = <QrSegment>[];
  var start = 0;
  for (var i = 1; i <= n; i++) {
    if (i == n || pathModes[i] != pathModes[start]) {
      segments.add(
        QrSegment(
          modes[pathModes[start]],
          String.fromCharCodes(runes.sublist(start, i)),
        ),
      );
      start = i;
    }
  }
  return segments;
}

/// Bits the segments take in a symbol of [version], mode indicators and count
/// fields included, terminator excluded.
int bitLength(List<QrSegment> segments, int version) {
  var bits = 0;
  for (final s in segments) {
    final body = switch (s.mode) {
      EncodingMode.numeric => _numericBits(s.text.length),
      EncodingMode.alphanumeric => _alphanumericBits(s.text.length),
      EncodingMode.byte => _byteBits(utf8.encode(s.text).length),
    };
    bits += _modeIndicatorBits + _countBits(s.mode, version) + body;
  }
  return bits;
}

int _numericBits(int digits) => digits ~/ 3 * 10 + const [0, 4, 7][digits % 3];

int _alphanumericBits(int chars) => chars ~/ 2 * 11 + chars % 2 * 6;

int _byteBits(int bytes) => bytes * 8;

/// Data codewords per version (index 0 is version 1) at L, M, Q and H, from
/// ISO/IEC 18004 Table 7, except version 15 at H: the `qr` package's table drops that
/// entry's second block group, so it holds 132 where the standard has 223, and the
/// symbol it draws there does not decode. 132 is below version 14's 197, so sizing
/// never lands on it; see [brokenInQrPackage] for a version chosen by hand.
const _dataCodewords = <List<int>>[
  // L
  [
    19, 34, 55, 80, 108, 136, 156, 194, 232, 274, //
    324, 370, 428, 461, 523, 589, 647, 721, 795, 861,
    932, 1006, 1094, 1174, 1276, 1370, 1468, 1531, 1631, 1735,
    1843, 1955, 2071, 2191, 2306, 2434, 2566, 2702, 2812, 2956,
  ],
  // M
  [
    16, 28, 44, 64, 86, 108, 124, 154, 182, 216, //
    254, 290, 334, 365, 415, 453, 507, 563, 627, 669,
    714, 782, 860, 914, 1000, 1062, 1128, 1193, 1267, 1373,
    1455, 1541, 1631, 1725, 1812, 1914, 1992, 2102, 2216, 2334,
  ],
  // Q
  [
    13, 22, 34, 48, 62, 76, 88, 110, 132, 154, //
    180, 206, 244, 261, 295, 325, 367, 397, 445, 485,
    512, 568, 614, 664, 718, 754, 808, 871, 911, 985,
    1033, 1115, 1171, 1231, 1286, 1354, 1426, 1502, 1582, 1666,
  ],
  // H
  [
    9, 16, 26, 36, 46, 60, 66, 86, 100, 122, //
    140, 158, 180, 197, 132, 253, 283, 313, 341, 385,
    406, 442, 464, 514, 538, 596, 628, 661, 701, 745,
    793, 845, 901, 961, 986, 1054, 1096, 1142, 1222, 1276,
  ],
];

/// Whether the `qr` package draws an unreadable symbol at [version] and [qrLevel].
bool brokenInQrPackage(int version, int qrLevel) =>
    version == 15 && qrLevel == QrErrorCorrectLevel.H;

/// Data bits a symbol of [version] holds at error-correction level [qrLevel]
/// (a `QrErrorCorrectLevel` constant): data codewords × 8.
int dataCapacityBits(int version, int qrLevel) {
  final row = switch (qrLevel) {
    QrErrorCorrectLevel.L => 0,
    QrErrorCorrectLevel.M => 1,
    QrErrorCorrectLevel.Q => 2,
    QrErrorCorrectLevel.H => 3,
    _ => throw ArgumentError('error correction level: $qrLevel'),
  };
  return _dataCodewords[row][version - 1] * 8;
}

/// Adds [segments] to [code] in order, each through the matching `qr` method.
void addSegments(QrCode code, List<QrSegment> segments) {
  for (final s in segments) {
    switch (s.mode) {
      case EncodingMode.numeric:
        code.addNumeric(s.text);
      case EncodingMode.alphanumeric:
        code.addAlphaNumeric(s.text);
      case EncodingMode.byte:
        code.addData(s.text);
    }
  }
}
