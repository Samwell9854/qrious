//
// version.dart
//
// The `version:` field in pubspec.yaml is the single source of truth for the app
// version. It is read back at runtime from the bundle rather than duplicated in a
// constant here, so a build on a device can identify itself and the release tooling
// cannot drift from what shipped.
//
// This file reads and parses; tool/version_info.dart validates the calendar-version
// format and derives the tag. Keeping the validator out of lib/ means the app never
// carries release policy it does not use, and exactly one place decides what a valid
// version looks like. The dependency only runs one way: tool/ may read lib/, not the
// reverse.
//

import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

/// The version and build number of the running build, e.g. `2026.8.0-alpha.1+1`.
class AppVersion {
  final String version;
  final String buildNumber;

  const AppVersion({required this.version, required this.buildNumber});

  static Future<AppVersion> load() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(version: info.version, buildNumber: info.buildNumber);
  }

  /// `alpha` out of `2026.8.0-alpha.2`; null for a stable release.
  ///
  /// A parser, not a validator: anything unparseable returns null rather than
  /// throwing, so a malformed version can never stop the window from opening.
  /// Rejecting it is `isCalendarVersion`'s job over in tool/, which is what fails
  /// the test suite and refuses to tag.
  String? get preReleaseLabel {
    final parsed = tryParseVersion(version);
    if (parsed == null || parsed.preRelease.isEmpty) return null;
    return parsed.preRelease.first.toString();
  }

  /// Whether the string is a version at all — not whether it satisfies this
  /// project's calendar-version rules, which stays tool/'s job.
  ///
  /// The distinction exists for the display: [preReleaseLabel] returns null both
  /// for a clean stable release and for something that is not a version, and those
  /// two must not be styled the same way.
  bool get isParsable => tryParseVersion(version) != null;

  @override
  String toString() => buildNumber.isEmpty ? version : '$version+$buildNumber';
}

/// [Version.parse] without the throw. Returns null on anything it cannot read.
Version? tryParseVersion(String? version) {
  if (version == null || version.isEmpty) return null;
  try {
    return Version.parse(version);
  } on FormatException {
    return null;
  }
}
