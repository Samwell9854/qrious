import 'package:flutter/material.dart';

import '../version.dart';

/// Shows the running build's version beside the app title.
///
/// It is placed there, and not in the app bar's actions, because Flutter paints
/// the debug ribbon across the top right corner in a debug build.
///
/// Three states, deliberately styled apart: a prerelease is called out so an alpha
/// on someone's device is obvious at a glance, a stable release is quiet, and a
/// version the parser cannot read is flagged as an error rather than passing for
/// the one build safe to hand out.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key, this.future});

  /// Injectable for tests; defaults to reading the real bundle.
  final Future<AppVersion>? future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersion>(
      future: future ?? AppVersion.load(),
      builder: (context, snapshot) {
        // Nothing to say while loading, and a failure to read the bundle must not
        // cost the user their app bar.
        if (!snapshot.hasData) return const SizedBox.shrink();
        return _badge(context, snapshot.data!);
      },
    );
  }

  Widget _badge(BuildContext context, AppVersion version) {
    final scheme = Theme.of(context).colorScheme;
    final label = version.preReleaseLabel;

    final (Color background, Color foreground) = switch (version) {
      _ when !version.isParsable => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      _ when label != null => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Tooltip(
      message: 'Build ${version.buildNumber}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          version.version,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: label != null ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
