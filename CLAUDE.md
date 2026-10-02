# Qrious

Flutter app that generates QR codes from structured input. Pick a format (WiFi, vCard, URL, …), fill in its fields, and a QR code plus the raw encoded string render live as you type.

- Flutter 3.41 stable / Dart SDK `^3.11.5`
- The only platform scaffolded so far is **Linux** (`linux/`). iOS is on indefinite hold — see Known rough edges.
- Dependencies: `qr_flutter` (rendering), `file_selector` (the save dialog), `package_info_plus` (reads the running build's version), `pub_semver` (parsing).

## Commands

```bash
flutter run -d linux                      # run the app
flutter analyze                           # lints (flutter_lints 6); must be clean
flutter test                              # format, widget, layout and version tests
dart format lib test tool                 # before committing
dart run tool/new_release.dart --dry-run  # release checks without tagging
git config core.hooksPath tool/hooks       # once per clone: auto-bump the version
```

## Layout

| Path | Purpose |
| --- | --- |
| [lib/main.dart](lib/main.dart) | `QriousApp` — MaterialApp, Material 3, indigo seed, light + dark themes |
| [lib/models/](lib/models/) | `QrFormat` interface and `QrField` descriptor |
| [lib/formats/](lib/formats/) | One file per supported QR format, plus `registry.dart` (the list the UI reads) and `validators.dart` (rules shared across formats) |
| [lib/screens/home_screen.dart](lib/screens/home_screen.dart) | The whole UI: format picker, generated form, QR preview |
| [lib/widgets/version_badge.dart](lib/widgets/version_badge.dart) | The version chip in the app bar |
| [lib/qr_png.dart](lib/qr_png.dart) | Renders the QR code to a PNG for saving — black on white, with a quiet zone |
| [lib/save_location.dart](lib/save_location.dart) | The save dialog, behind a typedef the screen can stub in tests |
| [lib/image_clipboard.dart](lib/image_clipboard.dart) | Copies a PNG to the clipboard by piping it to `wl-copy` or `xclip` |
| [lib/version.dart](lib/version.dart) | Reads and parses the running build's version |
| [tool/](tool/) | Release tooling — the version format rule, the tagging script, and the build-number bump |
| [packaging/](packaging/) | The desktop entry and AppStream metadata, and in `aur/` the `qrious-bin` PKGBUILD template with `render.sh`, which fills it from a release tarball — rendered copies live outside this repo |

## Core idea

Formats are **data-driven**. A format declares its fields; the UI builds itself from that declaration and never hardcodes anything format-specific. Adding a format means adding one file in `lib/formats/` and registering it — no UI edits.

See [docs/formats.md](docs/formats.md) for the contract and a walkthrough of adding one, and [docs/ui.md](docs/ui.md) for the screen's state and its two layouts.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org): `type(scope): summary` — `fix`, `feat`, `docs`, `test`, `refactor`, `chore`. Scope is usually the area (`wifi`, `vcard`, `home`, `layout`, `version`). Body is short imperative bullets (`Add`, `Fix`, `Remove`, `Update`), roughly ten lines at most. End with `Co-Authored-By`; no issue refs, no hash lists.

Adopt the **format only**. Conventional Commits normally drives semver bumps from `feat` / `BREAKING CHANGE`, and that mapping is meaningless here — versions are calendar-based and nothing consumes this project as a dependency.

**Do not restate design rationale in the message.** Why a thing is built the way it is belongs in a code comment or a `docs/` page, where it stays next to the code and gets read again. A commit that re-explains it is both duplicated and instantly stale. Say what changed and, when it is not obvious, what it fixes.

## Versioning and releases

Calendar versioning (`yyyy.m.micro`), the `-alpha.N` counter, the `+build` number (it and the calendar rollover are applied automatically by a pre-commit hook when app code changes; `micro`, dropping `-alpha` and tagging stay manual), and the release procedure: [docs/versioning-and-releases.md](docs/versioning-and-releases.md). `version:` in [pubspec.yaml](pubspec.yaml) is the single source of truth; tags are derived from it by `dart run tool/new_release.dart`, never typed by hand. Reading and parsing live in `lib/`, validating in `tool/` — the app must still open on a malformed version, and the tooling must refuse to tag one.

## Conventions

- All field values live in a single `Map<String, String>`; non-text types serialize into strings too (checkbox = `'true'`/`'false'`).
- `buildQrString` must tolerate missing or empty keys — it is called on every keystroke, including before required fields are filled.
- Omit optional fields from the payload entirely when empty rather than emitting empty values.
- Escape and encode per the target spec (`Uri.encodeComponent` for mailto, backslash escaping for the WiFi payload).
- Dart 3 `switch` expressions are used throughout; match that style.
- **Every layout change has to hold at phone width as well as desktop.** The breakpoint is 700px and both paths are covered by tests — a `RenderFlex` overflow fails the suite.
- **Markdown is not hard-wrapped: one line per paragraph, list item or table row.** Every reader of these files renders them, and a renderer wraps to the width it has. A hard wrap fixes the text at one column that is right for nobody else's window, and it makes every later edit re-flow the lines below it, so a one-word change arrives as a paragraph-sized diff.
- **Comments in code keep their manual wrapping, at roughly 90 columns.** The opposite medium: nothing re-flows a comment, and it is read beside code that is already wrapped. Reflowing prose and wrapping comments are the same rule — let the reader's width decide where it can, pick a sane width where it cannot.

## Known rough edges

- **Copying the QR image is Linux-only.** It shells out to `wl-copy` or `xclip`, because Flutter's `Clipboard` carries text only. iOS would need a platform channel or `super_clipboard` (which requires a Rust toolchain); the whole thing sits behind `copyPngToClipboard` so the swap is cheap if iOS ever happens.
- **iOS is on indefinite hold.** There is no `ios/` directory. Apple's Developer Program is a paid annual subscription (~$120 CAD/year), which isn't worth it for a free single-purpose app; free sideloading via a personal Apple ID exists but expires every 7 days and requires re-signing from a Mac, which isn't a viable distribution path either. Linux remains the primary target. Revisit only if the cost/reach tradeoff changes.
