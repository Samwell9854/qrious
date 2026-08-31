import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/version_info.dart';

void main() {
  group('affectsApp', () {
    test('is true for app code', () {
      expect(affectsApp(['lib/formats/wifi_format.dart']), isTrue);
      expect(affectsApp(['linux/runner/main.cc']), isTrue);
      expect(affectsApp(['assets/icon.png']), isTrue);
    });

    test('is false for everything that does not ship', () {
      expect(
        affectsApp([
          'docs/formats.md',
          'test/widget_test.dart',
          'tool/new_release.dart',
          'CLAUDE.md',
          'README.md',
          '.github/workflows/ci.yml',
        ]),
        isFalse,
      );
    });

    test('is false for pubspec.yaml alone', () {
      // The version lives there, so counting it would make each bump trigger
      // the next one. A dependency-only change uses --force.
      expect(affectsApp(['pubspec.yaml']), isFalse);
    });

    test('is true when app code is mixed in with anything else', () {
      expect(
        affectsApp(['docs/ui.md', 'lib/main.dart', 'pubspec.yaml']),
        isTrue,
      );
    });

    test('is false for an empty change set', () {
      expect(affectsApp([]), isFalse);
    });

    test('does not match a path that merely contains a prefix', () {
      expect(
        affectsApp(['docs/lib/notes.md', 'tool/lib_helper.dart']),
        isFalse,
      );
    });
  });

  group('bumpBuild', () {
    test('increments the build number and leaves the name alone', () {
      expect(bumpBuild('2026.8.0-alpha.1+1'), '2026.8.0-alpha.1+2');
      expect(bumpBuild('2026.8.0+9'), '2026.8.0+10');
    });

    test('never resets or rolls over', () {
      expect(bumpBuild('2026.12.3-alpha.7+99'), '2026.12.3-alpha.7+100');
    });

    test('throws when there is no build number', () {
      expect(() => bumpBuild('2026.8.0-alpha.1'), throwsStateError);
    });

    test('throws when the build number is not a number', () {
      expect(() => bumpBuild('2026.8.0+beta'), throwsStateError);
    });

    test('produces a version the release tooling still accepts', () {
      final (name: name, build: build) = splitVersion(
        bumpBuild(readPubspecVersion(File('pubspec.yaml'))),
      );
      expect(isCalendarVersion(name), isTrue);
      expect(int.tryParse(build), isNotNull);
    });
  });

  group('writePubspecVersion', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('qrious'));
    tearDown(() => temp.deleteSync(recursive: true));

    File pubspecWith(String body) =>
        File('${temp.path}/pubspec.yaml')..writeAsStringSync(body);

    test('replaces the version and nothing else', () {
      final file = pubspecWith(
        'name: qrious\n'
        'version: 2026.8.0-alpha.1+1\n'
        '\n'
        'environment:\n'
        '  sdk: ^3.11.5\n',
      );
      writePubspecVersion(file, '2026.8.0-alpha.1+2');
      expect(
        file.readAsStringSync(),
        'name: qrious\n'
        'version: 2026.8.0-alpha.1+2\n'
        '\n'
        'environment:\n'
        '  sdk: ^3.11.5\n',
      );
    });

    test('round-trips through readPubspecVersion', () {
      final file = pubspecWith('version: 2026.8.0+1\n');
      writePubspecVersion(file, '2026.9.0-alpha.1+2');
      expect(readPubspecVersion(file), '2026.9.0-alpha.1+2');
    });

    test('refuses a pubspec with no version line', () {
      expect(
        () => writePubspecVersion(pubspecWith('name: qrious\n'), '2026.8.0+2'),
        throwsStateError,
      );
    });

    test('refuses a pubspec with two version lines', () {
      final file = pubspecWith('version: 2026.8.0+1\nversion: 2026.8.0+2\n');
      expect(() => writePubspecVersion(file, '2026.8.0+3'), throwsStateError);
    });
  });
}
