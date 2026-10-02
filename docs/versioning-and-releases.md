# Versioning and releases

*Design rationale for Qrious. Index: [CLAUDE.md](../CLAUDE.md). Adapted from the same scheme in ncpa-helper.*

The app uses **calendar versioning**: `yyyy.m.micro`, where `micro` counts *shipped* releases within that month (`2026.8.0`, `2026.8.1`, then `2026.11.0`). There is no major/minor/patch meaning — nothing consumes this project as a dependency, so a compatibility digit would be carrying no information. Do not zero-pad the month: a semver parser reads `2026.08.0` and `2026.8.0` as the same release while the two strings tag differently, which is exactly the drift a single source of truth exists to prevent.

While the app is not yet something to hand to a user, every release carries `-alpha.N`. That suffix is dropped permanently at the first build that ships — a one-time transition, not a per-release judgement. Afterwards `-preview.N` is available for its own case: a build whose tests pass but that has not been run on a real device. The two never coexist.

**The numeric version names the release being worked toward; the prerelease counter tracks builds on the way there.** The numeric part does not move until something ships, so during alpha `micro` stays `0` — the month rollover resets it first — and `alpha.N` does the counting. `alpha.N` is scoped to its numeric version and therefore restarts whenever that changes: `2026.8.0-alpha.2` is followed by `2026.9.0-alpha.1`, not `-alpha.3`. Alpha builds never consume micro numbers, which is what stops the first stable release from landing at an arbitrary `2026.9.14`.

Tag whenever the answer to *"if a device had this build on it, would I need to tell it apart from the last one?"* is yes — per meaningful capability change, not per commit. Because the version must be correct *in* the commit it ships in, reconcile `version:` with the calendar immediately before committing: work started in August but committed in September becomes `2026.9.0-alpha.1`.

**`version:` moves to the next counter immediately after a tag is created — it never keeps a version that has already shipped.** A tree between tags therefore names something *unreleased*, and a tagged version string permanently means the artifact that tag points at. The alternative — leaving it on the last release until the next is prepared — makes an untagged build claim a tested, tagged identity it does not have, which is the dangerous direction: a build on a phone has no git, so the in-bundle string is the only identifier that device has. This follows the Linux kernel (mainline becomes `6.8-rc0` the moment 6.7 ships), Maven's `-SNAPSHOT`, and Debian's `UNRELEASED`. Skipped counters are fine — a bump to `alpha.12` that is never tagged costs nothing.

## The build number

Unlike ncpa-helper, the version string carries a `+N` build number: `2026.8.0-alpha.1+1`. Both the App Store and Play require one, and require it to **increase on every submitted build**, independent of the version name. So it is a plain counter that never resets — not `micro`, not `alpha.N`. Both stores are on indefinite hold (CLAUDE.md "Known rough edges"); the counter is kept deliberately anyway. It costs nothing, it identifies a build when the version string cannot, and it is already correct if a store target is ever added. It has no editorial judgement in it, which is why [tool/bump_build.dart](../tool/bump_build.dart) advances it from a pre-commit hook whenever a commit touches app code.

**iOS rejects a prerelease label in `CFBundleShortVersionString`.** Dormant while iOS is on hold, and kept for the day a runner is added. Flutter passes the part before `+` straight through, so `2026.8.0-alpha.1` would fail at upload. An iOS build needs the numeric version only: `flutter build ipa --build-name=2026.8.0 --build-number=1`. `tool/new_release.dart` prints that command for the tag it creates, built by `iosBuildCommand` from the version it read rather than written out, and [test/version_test.dart](../test/version_test.dart) checks it against `pubspec.yaml`, so the dormant line cannot quietly go stale.

### Bumping it automatically

Enable the hook once per clone — git does not version `.git/hooks`, so this is the one setup step:

```bash
git config core.hooksPath tool/hooks
```

From then on, any commit that stages a change under `lib/`, `assets/` or a platform directory (`linux/`, `ios/`, …) advances `+build` and stages `pubspec.yaml` along with it. A commit that only touches `docs/`, `test/`, `tool/` or `CLAUDE.md` leaves it alone: the build on a device is not a different build because a doc changed. `git commit --no-verify` skips the hook, and `dart run tool/bump_build.dart --dry-run` says what it would do without doing it.

The same commit also reconciles the calendar. A version left over from last month names a release that is no longer the one being worked toward, so an app-code commit in September against `2026.8.0-alpha.4` rewrites it to `2026.9.0-alpha.1` — micro back to `0`, the counter restarted because it is scoped to the numeric version, the label kept. A stable version is left alone however stale it is: what follows a shipped release is a decision, not an increment.

**What is automated is what has no judgement in it.** The build number is a counter the stores require to increase; the calendar rollover is a rule stated above, not a choice. What `micro` should be, when `-alpha` is dropped, and whether a commit deserves a tag are decisions made at release time by a person who knows whether a build needs telling apart from the last one. A counter that advanced those on every commit would answer that question with "always", which is the same as not answering it.

`pubspec.yaml` is deliberately not in the trigger list: the version lives there, so counting it as app code would make each bump trigger the next one. A change that is *only* a dependency edit therefore needs `dart run tool/bump_build.dart --force` — in practice a dependency changes because something in `lib/` is about to use it, and that commit triggers the bump on its own.

Because the commit that opens the next version after a tag touches nothing but `pubspec.yaml`, it neither bumps nor reconciles; the next app-code commit does. So `new_release.dart` prints the next version name with the build number unchanged.

## The source of truth

**The `version:` field in [pubspec.yaml](../pubspec.yaml) is the single source of truth.** Git tags are derived from it, never typed by hand, so the two cannot drift; Flutter also bakes it into the bundle, so the app can read it back and identify itself without git.

The three pieces and the line between them:

| File | Role |
| --- | --- |
| [lib/version.dart](../lib/version.dart) | **Reads and parses.** `AppVersion.load()` pulls the version out of the bundle via `package_info_plus`; `preReleaseLabel` and `isParsable` are parsers that return null/false rather than throwing. |
| [tool/version_info.dart](../tool/version_info.dart) | **Validates.** `calendarVersionPattern` and `isCalendarVersion` state the format rule once, plus the pubspec reader and the next-counter helper. |
| [tool/new_release.dart](../tool/new_release.dart) | **Tags.** Validates, refuses, tags, prints. |

Keeping the validator out of `lib/` means the app never carries release policy it does not use, and exactly one place decides what a valid version looks like. The dependency runs one way only: `tool/` may read `lib/`, not the reverse. The practical payoff is in the display — a malformed version must never stop the window from opening, so the app parses leniently while the tooling rejects strictly.

## Releasing

```bash
# 1. Reconcile version: in pubspec.yaml with the calendar, and commit.
flutter test                                  # version_test.dart guards the format
dart run tool/new_release.dart --dry-run      # every check, no tag
dart run tool/new_release.dart                # creates the annotated tag
git push origin v2026.8.0-alpha.1             # the script prints this line
# 2. Set version: to the next counter (the script prints that too) and commit.
```

Step 2 changes the version name only — the build number is already where the hook left it.

The script refuses a malformed version, a version with no build number, a dirty tree (`--allow-dirty` overrides), a tag that already exists, and a repository with no commits. It **never pushes and never writes to the repo** — it validates and tags; opening the next version is a commit you make, which keeps the one tool that touches git history from also editing files.

The format rule lives once, in `tool/version_info.dart`, and is used by both the release script and [test/version_test.dart](../test/version_test.dart) — which also asserts the version currently in pubspec.yaml is well-formed, carries a build number, and is not dated in the future, so a typo fails `flutter test` instead of surfacing at release time.
