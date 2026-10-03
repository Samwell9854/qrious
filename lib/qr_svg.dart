import 'qr_encoding.dart';
import 'qr_png.dart';

/// Renders [qr] as an SVG document, black on white with the spec's quiet zone,
/// for the same reasons [renderQrPng] does.
///
/// Drawn in module units, so the `viewBox` is the symbol plus its quiet zone and
/// the code stays exact at any scale. [size] only sets the `width` and `height`
/// it opens at, matching the PNG of the same size. Each row's runs of dark modules
/// become one path segment, which keeps the file small, and `crispEdges` stops
/// viewers anti-aliasing the seams between neighbouring runs.
String renderQrSvg(EncodedQr qr, {ImageSize size = ImageSize.medium}) {
  final side = qr.moduleCount + quietZoneModules * 2;
  final pixels = size.pixelsFor(qr);
  final path = StringBuffer();
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
      final x = start + quietZoneModules;
      final y = row + quietZoneModules;
      path.write('M$x ${y}h${col - start}v1h-${col - start}z');
    }
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" '
      'width="$pixels" height="$pixels" viewBox="0 0 $side $side" '
      'shape-rendering="crispEdges">\n'
      '<rect width="$side" height="$side" fill="#ffffff"/>\n'
      '<path d="$path" fill="#000000"/>\n'
      '</svg>\n';
}
