//
// version_test.dart
//
// Guards the version: field that the git tag is derived from. A malformed version
// is otherwise only noticed at release time, when it is most annoying.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/version.dart';

import '../tool/version_info.dart';

void main() {
  // Parsing lives in lib/ so the app can label itself; validating lives in tool/ so
  // the app never carries release policy. These assert that split holds: the parser
  // stays quiet on input the validator is responsible for rejecting.
  group('AppVersion.preReleaseLabel', () {
    for (final entry in {
      '2026.8.0-alpha.2': 'alpha',
      '2026.8.0-alpha.1': 'alpha',
      '2026.12.10-preview.3': 'preview',
      '2027.3.0-rc.12': 'rc',
    }.entries) {
      test('reads ${entry.value} out of ${entry.key}', () {
        expect(
          AppVersion(version: entry.key, buildNumber: '1').preReleaseLabel,
          entry.value,
        );
      });
    }

    for (final version in ['2026.8.0', '2026.11.2']) {
      test('returns null for the stable version $version', () {
        expect(
          AppVersion(version: version, buildNumber: '1').preReleaseLabel,
          isNull,
        );
      });
    }

    // The window must still open when the version is wrong; isCalendarVersion is
    // what fails the suite and blocks the tag.
    for (final version in ['2026.8.0b1', 'v2026.8.0', 'garbage', '']) {
      test('returns null instead of throwing for unparseable "$version"', () {
        final subject = AppVersion(version: version, buildNumber: '1');
        expect(() => subject.preReleaseLabel, returnsNormally);
        expect(subject.preReleaseLabel, isNull);
      });
    }
  });

  // preReleaseLabel returns null for a stable release and for something that is not
  // a version at all. This is what tells those two apart, so the display can style
  // them differently — a typo'd version must not look like a shippable build.
  group('AppVersion.isParsable', () {
    // These parse as versions but several break this project's rules. That is the
    // point of the split — 2026.08.0 parses fine and is exactly the drift
    // isCalendarVersion exists to reject.
    for (final version in [
      '2026.8.0',
      '2026.8.0-alpha.2',
      '2026.08.0',
      '1.2.3',
    ]) {
      test('accepts $version', () {
        expect(
          AppVersion(version: version, buildNumber: '1').isParsable,
          isTrue,
        );
      });
    }

    for (final version in [
      'garbage',
      '2026.8.0b1',
      'v2026.8.0',
      '2026.8',
      '',
    ]) {
      test('rejects "$version", which is not a version at all', () {
        expect(
          AppVersion(version: version, buildNumber: '1').isParsable,
          isFalse,
        );
      });
    }
  });

  group('isCalendarVersion', () {
    // Expected results are spelled out rather than generated from the pattern,
    // which is the thing being checked.
    for (final version in [
      '2026.8.0',
      '2026.11.2',
      '2026.1.0-alpha.1',
      '2026.12.10-preview.3',
      '2027.3.0-rc.12',
    ]) {
      test('accepts $version', () {
        expect(isCalendarVersion(version), isTrue);
      });
    }

    for (final version in [
      '2026.08.0', // padded month — sorts and tags inconsistently
      '2026.13.0', // not a month
      '2026.0.1', // not a month
      '1.0.0', // the old semver-style scheme
      '2026.8', // missing micro
      '2026.8.0-alpha', // prerelease label with no counter
      '2026.8.0-alpha.0',
      '2026.8.0b1',
      'v2026.8.0', // the tag, not the version
      '2026.8.0+1', // the build number belongs to the pubspec field, not the tag
      '',
    ]) {
      test('rejects "$version"', () {
        expect(isCalendarVersion(version), isFalse);
      });
    }
  });

  group('nextPreRelease', () {
    test('advances the counter', () {
      expect(nextPreRelease('2026.8.0-alpha.1'), '2026.8.0-alpha.2');
      expect(nextPreRelease('2026.8.0-alpha.9'), '2026.8.0-alpha.10');
    });

    test('has nothing to advance on a stable release', () {
      expect(nextPreRelease('2026.8.0'), isNull);
    });
  });

  group('the version recorded in pubspec.yaml', () {
    late String name;
    late String build;

    setUpAll(() {
      final full = readPubspecVersion(File('pubspec.yaml'));
      (name: name, build: build) = splitVersion(full);
    });

    test('is a well-formed calendar version', () {
      expect(
        isCalendarVersion(name),
        isTrue,
        reason: "'$name' is what tool/new_release.dart will tag",
      );
    });

    test('round-trips through the semver parser unchanged', () {
      expect(tryParseVersion(name).toString(), name);
    });

    test('carries a build number, which iOS and Android both require', () {
      expect(int.tryParse(build), isNotNull);
    });

    test('is not dated in the future', () {
      final parsed = tryParseVersion(name)!;
      final dated = DateTime(parsed.major, parsed.minor);
      expect(dated.isAfter(DateTime.now()), isFalse);
    });
  });
}
