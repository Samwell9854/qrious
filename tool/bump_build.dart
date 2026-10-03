//
// bump_build.dart
//
// Advances the version in pubspec.yaml when a commit changes app code.
//
// Run from the pre-commit hook in tool/hooks/. It owns the parts of the version
// with no editorial judgement in them: the +build counter, which must increase on
// every build submitted to a store; opening the next version once the current one
// has been tagged; and the calendar rollover, which
// docs/versioning-and-releases.md states as a rule — work started in August but
// committed in September is 2026.9.0-alpha.1.
//
// What it does not own: what micro should be, when -alpha is dropped, and when a
// commit deserves a tag. Those are decisions a person makes at release time.
//
// Usage:
//   dart run tool/bump_build.dart              bump if staged changes touch app code
//   dart run tool/bump_build.dart --dry-run    report what it would do
//   dart run tool/bump_build.dart --force      bump regardless of what is staged
//

import 'dart:io';

import 'version_info.dart';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final force = args.contains('--force');

  final root = repositoryRoot().path;
  final pubspec = pubspecFile(Directory(root));

  final staged = _stagedPaths(root);
  final triggers = staged.where((p) => affectsApp([p])).toList();
  if (!force && triggers.isEmpty) {
    if (dryRun) {
      stdout.writeln('No staged app code; the build number stays put.');
    }
    return;
  }

  final current = readPubspecVersion(pubspec);
  String next;
  try {
    next = bumpBuild(current);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }

  // A version that has been tagged has shipped, and this commit changes the app,
  // so the build it makes is no longer that release. Opened here rather than in a
  // commit of its own straight after tagging, which would change nothing else.
  final shipped = splitVersion(next).name;
  final opened = openAfterShipped(
    shipped,
    (tag) => _stdout(_git(root, ['tag', '--list', tag])).isNotEmpty,
  );
  if (opened != null) next = '$opened+${splitVersion(next).build}';

  // The calendar rollover is a stated rule, not a judgement, so it is applied
  // here too: a version left over from last month names a release that is no
  // longer the one being worked toward. What micro should be, and when -alpha
  // gets dropped, stay with the person releasing.
  final (name: name, build: build) = splitVersion(next);
  final reconciled = reconcileWithCalendar(name, DateTime.now());
  if (reconciled != null) next = '$reconciled+$build';

  final because = force
      ? '--force'
      : '${triggers.first}${triggers.length > 1 ? ' +${triggers.length - 1} more' : ''}';

  if (dryRun) {
    stdout.writeln('Would bump $current -> $next ($because).');
    return;
  }

  writePubspecVersion(pubspec, next);

  // Stage it, or the commit being written would not contain the bump it earned.
  final added = _git(root, ['add', '--', pubspec.path]);
  if (added.exitCode != 0) {
    stderr.writeln(
      'Bumped to $next but could not stage pubspec.yaml:\n'
      '${added.stderr}',
    );
    exit(1);
  }

  if (opened != null) {
    stdout.writeln('Version $current -> $next ($because)');
    stdout.writeln(
      'v$shipped is tagged, so this commit opens the next version. Check that '
      '${splitVersion(next).name} is the release you mean to be working toward.',
    );
  } else if (reconciled != null) {
    stdout.writeln('Version $current -> $next ($because)');
    stdout.writeln(
      'The calendar moved on, so the version name was reset with it. Check that '
      '$reconciled is the release you mean to be working toward.',
    );
  } else {
    stdout.writeln('Build number $current -> $next ($because)');
  }
}

/// Paths staged for the commit being written, ignoring deletions — a deleted
/// file still changes the app, but `git diff` reports it and nothing needs to
/// read it.
List<String> _stagedPaths(String root) {
  final result = _git(root, [
    'diff',
    '--cached',
    '--name-only',
    '--diff-filter=ACMR',
  ]);
  if (result.exitCode != 0) return const [];
  return (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

ProcessResult _git(String root, List<String> args) =>
    Process.runSync('git', ['-C', root, ...args]);

String _stdout(ProcessResult result) => (result.stdout as String).trim();
