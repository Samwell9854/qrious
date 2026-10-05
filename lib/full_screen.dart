/// Taking the whole screen for the full-screen code, not just the app's window.
///
/// Flutter has no desktop call for this. On Linux the runner answers a small
/// method channel by asking GTK to fullscreen the window (see
/// `linux/runner/my_application.cc`); on a phone, hiding the system bars is the
/// equivalent. Everything is behind [setFullScreen] so the screen can be tested
/// without either.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Enters full screen when [on] is true and leaves it when false. A typedef so the
/// screen can be tested without touching the real window.
typedef FullScreenSetter = Future<void> Function(bool on);

const windowChannel = MethodChannel('qrious/window');

/// Best effort: a platform that cannot go full screen still shows the code across
/// the whole window, which is most of the benefit, so a failure is swallowed
/// rather than costing the user the view.
Future<void> setFullScreen(bool on) async {
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android || TargetPlatform.iOS:
        await SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      case TargetPlatform.linux:
        await windowChannel.invokeMethod<void>('setFullScreen', on);
      default:
        return;
    }
  } on PlatformException {
    return;
  } on MissingPluginException {
    return;
  }
}
