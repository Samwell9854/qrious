//
// new_release.dart
//
// Tags the current commit with the version recorded in pubspec.yaml.
//
// Reads the version: field, checks it against the yyyy.m.micro calendar-version
// format, and creates the matching annotated tag. The version is edited by hand in
// pubspec.yaml; this only derives the tag from it, so the two cannot disagree.
//
// Nothing is pushed — the command to do that is printed instead.
//
// Usage:
//   dart run tool/new_release.dart              tag the current commit
//   dart run tool/new_release.dart --dry-run    run every check, create no tag
//   dart run tool/new_release.dart --allow-dirty
//   dart run tool/new_release.dart --message "..."
//

import 'dart:io';

import 'version_info.dart';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final allowDirty = args.contains('--allow-dirty');
  final messageIndex = args.indexOf('--message');
  final message = messageIndex >= 0 && messageIndex + 1 < args.length
      ? args[messageIndex + 1]
      : null;

  final root = repositoryRoot().path;
  final pubspec = pubspecFile(Directory(root));
  final full = readPubspecVersion(pubspec);
  final (name: name, build: build) = splitVersion(full);

  if (!isCalendarVersion(name)) {
    _fail(
      "Version '$name' in ${pubspec.path} is not a valid calendar version.\n"
      'Expected yyyy.m.micro with an unpadded month, optionally '
      '-alpha|beta|preview|rc.N (for example 2026.8.0 or 2026.11.2-alpha.1).',
    );
  }
  if (build.isEmpty) {
    _fail(
      'Version $full has no +build number. iOS and Android both require one, '
      'and it must increase on every build submitted.',
    );
  }

  final tag = 'v$name';

  if (_git(root, ['rev-parse', '--git-dir']).exitCode != 0) {
    _fail("'$root' is not a git repository.");
  }
  if (_git(root, ['rev-parse', 'HEAD']).exitCode != 0) {
    _fail('The repository has no commits yet, so there is nothing to tag.');
  }
  if (_stdout(_git(root, ['tag', '--list', tag])).isNotEmpty) {
    _fail(
      "Tag '$tag' already exists. Bump version: in ${pubspec.path} before "
      'releasing again.',
    );
  }

  final dirty = _stdout(_git(root, ['status', '--porcelain']));
  if (dirty.isNotEmpty && !allowDirty) {
    _fail(
      "Working tree has uncommitted changes, so '$tag' would not point at what "
      'you are releasing.\nCommit them first, or pass --allow-dirty if that is '
      'deliberate.\n$dirty',
    );
  }

  final preRelease = name.contains('-') ? name.split('-').last : '';
  if (preRelease.isNotEmpty) {
    stderr.writeln(
      'Warning: $tag is a prerelease ($preRelease) — not for release.',
    );
  }

  if (dryRun) {
    stdout.writeln('Would create $tag on ${_head(root)} (--dry-run).');
    _printFollowUp(root, tag, name, build);
    return;
  }

  final tagged = _git(root, [
    'tag',
    '-a',
    tag,
    '-m',
    message ?? 'qrious $full',
  ]);
  if (tagged.exitCode != 0) {
    _fail(
      'git tag failed with exit code ${tagged.exitCode}.\n${tagged.stderr}',
    );
  }

  stdout.writeln('Created $tag on ${_head(root)}');
  _printFollowUp(root, tag, name, build);
}

void _printFollowUp(String root, String tag, String name, String build) {
  stdout.writeln('Push it with: git push origin $tag');

  // The version in pubspec.yaml never keeps a version that has shipped — see
  // docs/versioning-and-releases.md. Printed rather than done here: this script
  // validates and tags, and writing to the repo would make it the only tool in
  // tool/ that does.
  final next = nextPreRelease(name) ?? '<next version>';
  stdout.writeln(
    'Then open the next version: set version: to $next+${int.parse(build) + 1} '
    'in pubspec.yaml and commit.',
  );

  // iOS rejects a prerelease label in CFBundleShortVersionString.
  if (name.contains('-')) {
    final numeric = name.split('-').first;
    stdout.writeln(
      'iOS build for this tag: flutter build ipa --build-name=$numeric '
      '--build-number=$build',
    );
  }
}

ProcessResult _git(String root, List<String> args) =>
    Process.runSync('git', ['-C', root, ...args]);

String _stdout(ProcessResult result) => (result.stdout as String).trim();

String _head(String root) =>
    _stdout(_git(root, ['rev-parse', '--short', 'HEAD']));

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
