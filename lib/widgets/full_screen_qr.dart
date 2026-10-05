import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../qr_encoding.dart';

/// "Tap" on a phone, "Click" everywhere else. A touchscreen laptop is the one case
/// this gets wrong, and it is wrong harmlessly: clicking and tapping both work.
String pointerVerb() => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => 'Tap',
  _ => 'Click',
};

/// The code alone, as large as the screen allows, for another device to scan.
///
/// White whatever the theme, like the preview, because a scanner needs dark
/// modules on a light ground. Tapping anywhere or pressing Esc closes it, so there
/// is no button to aim for.
class FullScreenQr extends StatelessWidget {
  const FullScreenQr({super.key, required this.qr});

  final EncodedQr qr;

  /// The spec's quiet zone, in modules, on each side of the symbol.
  static const _quietZone = 4;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    final closeHint = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => 'Tap anywhere to close',
      _ => 'Click anywhere or press Esc to close',
    };

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          // Material rather than a bare box, so the text has a theme to style it.
          child: Material(
            color: Colors.white,
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = min(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        final module = side / (qr.moduleCount + 2 * _quietZone);
                        return Center(
                          child: QrImageView.withQr(
                            qr: qr.code,
                            size: side,
                            padding: EdgeInsets.all(module * _quietZone),
                            backgroundColor: Colors.white,
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      closeHint,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
