//
// bump_build.dart
//
// Advances the +build number in pubspec.yaml when a commit changes app code.
//
// Run from the pre-commit hook in tool/hooks/. The build number is the one part
// of the version with no editorial judgement in it: it is a plain counter that
// must increase on every build submitted to a store, so a machine can own it.
// The version *name* is not automated — yyyy.m.micro and -alpha.N say which
// release is being worked toward, which is a decision a person makes at release
// time. See docs/versioning-and-releases.md.
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
  final String next;
  try {
    next = bumpBuild(current);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }

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

  stdout.writeln('Build number $current -> $next ($because)');
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
