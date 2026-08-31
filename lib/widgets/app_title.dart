import 'package:flutter/material.dart';

import '../version.dart';
import 'version_badge.dart';

/// The app bar's title: the app name with the version badge beside it.
///
/// The badge lives here rather than in the app bar's `actions` because Flutter
/// paints the debug ribbon across the top right corner in a debug build, and it
/// sits on top of anything parked there.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key, this.versionFuture});

  /// Injectable for tests; the badge reads the real bundle when this is null.
  final Future<AppVersion>? versionFuture;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Qrious'),
        const SizedBox(width: 12),
        // Flexible so a long version ellipsises instead of overflowing the title
        // row on a narrow phone.
        Flexible(child: VersionBadge(future: versionFuture)),
      ],
    );
  }
}
