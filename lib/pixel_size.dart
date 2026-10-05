/// How large a logical pixel is on the screen the app is showing on.
///
/// Whether a code is comfortable to scan depends on how big its modules are in
/// the world, not in pixels: 1080 pixels across a 24" monitor and across a 5" phone
/// are very different things. Flutter does not report a screen's physical size, so
/// on Linux the runner answers from GDK, which reads it from the monitor itself
/// (see `linux/runner/my_application.cc`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'full_screen.dart';

/// Reads the size of a logical pixel in millimetres, or null when the platform
/// cannot say. A typedef so the screen can be tested without a real monitor.
typedef PixelSizeReader = Future<double?> Function();

/// Linux asks the runner, which knows the monitor the window is on; elsewhere
/// there is nothing to ask yet.
Future<double?> readMillimetresPerPixel() async {
  if (defaultTargetPlatform != TargetPlatform.linux) return null;
  try {
    final mm = await windowChannel.invokeMethod<double>('millimetresPerPixel');
    // Projectors and some virtual monitors report nonsense, or nothing.
    return mm != null && mm > 0.05 && mm < 2 ? mm : null;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// What a logical pixel is by convention, when the monitor does not say: 160 per
/// inch on Android and iOS, the 96 per inch desktops assume everywhere else.
double fallbackMillimetresPerPixel() => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => 25.4 / 160,
  _ => 25.4 / 96,
};
