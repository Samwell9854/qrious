import 'package:flutter/material.dart';

import '../qr_encoding.dart';

/// The encoded symbol drawn on screen: exactly the module matrix that is saved, black
/// on white, with [quietZone] modules of white around it.
///
/// qr_flutter's own view is not used because its painter works out the mask again
/// from the code, which would show a different symbol from the saved one as soon as
/// the mask is chosen rather than picked by the library.
class QrSymbol extends StatelessWidget {
  const QrSymbol({
    super.key,
    required this.qr,
    required this.size,
    this.quietZone = 0,
  });

  final EncodedQr qr;

  /// The width and height, quiet zone included.
  final double size;

  /// The margin on each side, in modules.
  final int quietZone;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SymbolPainter(qr, quietZone)),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.qr, this.quietZone);

  final EncodedQr qr;
  final int quietZone;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final unit = size.shortestSide / (qr.moduleCount + 2 * quietZone);
    // One path of each row's dark runs, as the SVG has: neighbouring modules drawn as
    // separate squares leave hairline seams wherever their edges fall between pixels.
    final path = Path();
    for (var row = 0; row < qr.moduleCount; row++) {
      var col = 0;
      while (col < qr.moduleCount) {
        if (!qr.image.isDark(row, col)) {
          col++;
          continue;
        }
        final start = col;
        while (col < qr.moduleCount && qr.image.isDark(row, col)) {
          col++;
        }
        path.addRect(
          Rect.fromLTWH(
            (start + quietZone) * unit,
            (row + quietZone) * unit,
            (col - start) * unit,
            // A sliver taller than the module, so rows meet without a seam either;
            // the last row has none to close and must not spill out of the box.
            row == qr.moduleCount - 1 ? unit : unit + 0.5,
          ),
        );
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      old.qr != qr || old.quietZone != quietZone;
}
