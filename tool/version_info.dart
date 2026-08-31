//
// version_info.dart
//
// The `version:` field in pubspec.yaml is the single source of truth for the app
// version; the git tag is derived from it. The format rule is stated here once so
// that new_release.dart and test/version_test.dart cannot disagree about it.
//
// Reading and parsing the version lives in lib/version.dart, because the app needs
// it to display its own version and the app has to work without tool/ present.
//

import 'dart:io';

/// yyyy.m.micro, optionally with a prerelease label: 2026.8.0, 2026.11.2,
/// 2026.8.0-alpha.1
///
/// The month is never zero-padded. Semver parsing silently accepts `2026.08.0`
/// and would then render it as written, so a padded month tags one string while
/// sorting like another — the drift the single source of truth exists to prevent.
final RegExp calendarVersionPattern = RegExp(
  r'^\d{4}\.([1-9]|1[0-2])\.(0|[1-9]\d*)(-(alpha|beta|preview|rc)\.[1-9]\d*)?$',
);

bool isCalendarVersion(String? version) =>
    version != null && calendarVersionPattern.hasMatch(version);

/// The repository root, derived from this file's location.
Directory repositoryRoot() =>
    Directory(File.fromUri(Platform.script).parent.parent.path);

File pubspecFile([Directory? root]) =>
    File('${(root ?? repositoryRoot()).path}/pubspec.yaml');

/// The full `version:` value from pubspec.yaml, build number included:
/// `2026.8.0-alpha.1+1`.
///
/// Throws rather than returning null: being unable to read the version is a
/// failure, and new_release.dart must not tag a version it could not confirm.
String readPubspecVersion([File? pubspec]) {
  final file = pubspec ?? pubspecFile();
  if (!file.existsSync()) {
    throw StateError('pubspec.yaml not found at ${file.path}.');
  }

  final matches = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).allMatches(file.readAsStringSync()).toList();
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one top-level version: line in ${file.path}, '
      'found ${matches.length}.',
    );
  }

  return matches.single.group(1)!;
}

/// Splits `2026.8.0-alpha.1+1` into its name and build number.
({String name, String build}) splitVersion(String version) {
  final plus = version.indexOf('+');
  if (plus < 0) return (name: version, build: '');
  return (name: version.substring(0, plus), build: version.substring(plus + 1));
}

/// The next prerelease counter for [name], or null when it has no counter to
/// advance — a stable release is followed by a decision, not an increment.
String? nextPreRelease(String name) {
  final match = RegExp(r'^(.*\.)(\d+)$').firstMatch(name);
  if (match == null || !name.contains('-')) return null;
  return '${match.group(1)}${int.parse(match.group(2)!) + 1}';
}

/// Path prefixes whose contents end up in the shipped app, and so change what a
/// build *does*. Everything else — docs/, test/, tool/, CLAUDE.md — can change
/// freely without the build on a device becoming a different build.
///
/// pubspec.yaml is deliberately absent. It is where the version itself lives, so
/// treating it as app code would make every bump trigger another one. A change
/// that is only a dependency edit therefore needs `--force`; in practice a
/// dependency changes because something in lib/ is about to use it, and that
/// commit triggers the bump on its own.
const appPathPrefixes = [
  'lib/',
  'assets/',
  'android/',
  'ios/',
  'linux/',
  'macos/',
  'web/',
  'windows/',
];

/// Whether any of [paths] is app code — see [appPathPrefixes].
bool affectsApp(Iterable<String> paths) =>
    paths.any((path) => appPathPrefixes.any(path.startsWith));

/// [version] with its build number incremented: `2026.8.0-alpha.1+1` becomes
/// `2026.8.0-alpha.1+2`.
///
/// Throws when there is no build number to advance. The stores require one and
/// require it to increase, so silently carrying on without it would produce
/// exactly the build that gets rejected at upload.
String bumpBuild(String version) {
  final (name: name, build: build) = splitVersion(version);
  final current = int.tryParse(build);
  if (current == null) {
    throw StateError(
      "Version '$version' has no numeric +build number to increment.",
    );
  }
  return '$name+${current + 1}';
}

/// Replaces the `version:` line in [pubspec] with [version].
void writePubspecVersion(File pubspec, String version) {
  final contents = pubspec.readAsStringSync();
  // [^\S\n] is horizontal whitespace only: \s* would run past the end of the
  // line and the replacement would swallow the blank line after it.
  final pattern = RegExp(r'^version:[^\S\n]*\S+[^\S\n]*$', multiLine: true);
  if (pattern.allMatches(contents).length != 1) {
    throw StateError(
      'Expected exactly one top-level version: line in ${pubspec.path}.',
    );
  }
  pubspec.writeAsStringSync(
    contents.replaceFirst(pattern, 'version: $version'),
  );
}
