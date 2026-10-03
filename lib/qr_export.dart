import 'dart:convert';
import 'dart:typed_data';

import 'qr_encoding.dart';
import 'qr_png.dart';
import 'qr_svg.dart';

/// The file types the code can be saved as. Why these and not others is in the
/// README's image export table.
enum ExportFileType {
  png('PNG image', 'png'),
  svg('SVG image', 'svg');

  const ExportFileType(this.label, this.extension);

  final String label;
  final String extension;

  /// The file's bytes for [qr] at [size].
  Future<Uint8List> render(EncodedQr qr, ImageSize size) async =>
      switch (this) {
        png => await renderQrPng(qr, size: size),
        svg => utf8.encode(renderQrSvg(qr, size: size)),
      };

  /// [path] with this type's extension added unless it already ends in it.
  ///
  /// The GTK dialog does not append the extension when the user removes it, and a
  /// name typed with the other type's extension gets this one appended rather than
  /// trusted, so the file's name never misstates its contents.
  String withExtension(String path) =>
      path.toLowerCase().endsWith('.$extension') ? path : '$path.$extension';
}

/// A filename for [formatId] that sorts by when it was made: `qrious-wifi.png`
/// with a timestamp, so saving several in a row does not overwrite one file.
String qrFileName(String formatId, DateTime when, ExportFileType type) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${when.year}${two(when.month)}${two(when.day)}'
      '-${two(when.hour)}${two(when.minute)}${two(when.second)}';
  return 'qrious-$formatId-$stamp.${type.extension}';
}
