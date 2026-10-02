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

/// The `flutter build ipa` command for [name] and [build], or null when [name]
/// is stable and a plain `flutter build ipa` already does the right thing.
///
/// iOS rejects a prerelease label in CFBundleShortVersionString, and Flutter passes
/// the part of the version before `+` straight through, so a prerelease build needs
/// the numeric version spelled out. Dormant while there is no iOS runner — see
/// CLAUDE.md "Known rough edges". Both values are derived from what the caller read
/// out of pubspec.yaml; test/version_test.dart holds it to that, so the command
/// cannot drift from the version it is printed for.
String? iosBuildCommand(String name, String build) {
  if (!name.contains('-')) return null;
  final numeric = name.split('-').first;
  return 'flutter build ipa --build-name=$numeric --build-number=$build';
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

/// [name] reconciled with the calendar on [now], or null when it already agrees
/// or when the answer is a decision rather than an increment.
///
/// The numeric version names the release being worked toward, so work started in
/// August but committed in September is `2026.9.0-alpha.1`, not `2026.8.0`. The
/// prerelease counter is scoped to the numeric version, so it restarts at 1; the
/// label itself is kept, since alpha-versus-preview is a judgement this does not
/// get to make.
///
/// Returns null for a stable version. A stable release that has fallen behind the
/// calendar is followed by a decision about what ships next — see
/// docs/versioning-and-releases.md — and guessing at it here would invent a
/// release nobody planned. Also returns null for a version dated in the future,
/// which is a mistake to report rather than quietly walk backwards.
String? reconcileWithCalendar(String name, DateTime now) {
  final match = RegExp(
    r'^(\d{4})\.(\d{1,2})\.(\d+)(?:-([a-z]+)\.(\d+))?$',
  ).firstMatch(name);
  if (match == null) return null;

  final label = match.group(4);
  if (label == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  if (year == now.year && month == now.month) return null;
  if (year > now.year || (year == now.year && month > now.month)) return null;

  return '${now.year}.${now.month}.0-$label.1';
}
