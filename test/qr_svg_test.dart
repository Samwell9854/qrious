import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_png.dart';
import 'package:qrious/qr_svg.dart';

void main() {
  // Version 2 at auto: 25 modules a side, 33 with the quiet zone.
  final qr = encodeQr('https://example.com', ErrorCorrection.auto);

  test('opens at the PNG size, drawn in module units', () {
    for (final size in ImageSize.values) {
      final svg = renderQrSvg(qr, size: size);
      final pixels = size.pixelsFor(qr);
      expect(svg, contains('width="$pixels" height="$pixels"'));
      expect(svg, contains('viewBox="0 0 33 33"'));
    }
  });

  test('paints a white background under the modules', () {
    expect(
      renderQrSvg(qr),
      contains('<rect width="33" height="33" fill="#ffffff"/>'),
    );
  });

  test('draws exactly the dark modules, inside the quiet zone', () {
    final d = RegExp(r' d="([^"]*)"').firstMatch(renderQrSvg(qr))!.group(1)!;
    final drawn = <(int, int)>{};
    for (final run in RegExp(r'M(\d+) (\d+)h(\d+)v1h-\3z').allMatches(d)) {
      final x = int.parse(run.group(1)!);
      final y = int.parse(run.group(2)!);
      for (var i = 0; i < int.parse(run.group(3)!); i++) {
        drawn.add((y - quietZoneModules, x + i - quietZoneModules));
      }
    }
    // Every segment matched the run pattern, so nothing else is in the path.
    expect(d.replaceAll(RegExp(r'M\d+ \d+h(\d+)v1h-\1z'), ''), isEmpty);

    final dark = {
      for (var row = 0; row < qr.moduleCount; row++)
        for (var col = 0; col < qr.moduleCount; col++)
          if (qr.image.isDark(row, col)) (row, col),
    };
    expect(drawn, dark);
  });
}
