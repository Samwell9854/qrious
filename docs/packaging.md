# Packaging

*Design rationale for Qrious. Index: [CLAUDE.md](../CLAUDE.md).*

Qrious ships to Arch Linux as **`qrious-bin`** on the AUR: a PKGBUILD that repackages the tarball CI builds from a tag. The template is [packaging/aur/PKGBUILD.in](../packaging/aur/PKGBUILD.in), the tarball is assembled by [.github/workflows/release.yml](../.github/workflows/release.yml), and [packaging/aur/render.sh](../packaging/aur/render.sh) joins the two. This page explains why it is shaped that way; the files themselves say how.

## A `-bin` package, not a source build

An AUR source package would build Qrious on the user's machine, and two Arch rules make that expensive for a Flutter app:

- **`build()` may not reach the network**, and every input has to be listed in `source=()` with a checksum. A Flutter build resolves pub packages, so a compliant source package would list every pub dependency as its own source entry and pre-seed `PUB_CACHE` in `prepare()` — a hand-kept mirror of `pubspec.lock` that breaks on every dependency bump.
- **The Flutter SDK is not in the official repositories.** It would be a `makedepends` pulled from the AUR itself, a multi-gigabyte toolchain installed on every machine that wants a QR code generator.

Neither would be decisive if compiling gained the user something, and here it gains nothing. A Flutter desktop build has no build-time options or optional features; it is AOT-compiled from locked dependencies, so every user's build would produce the same binary CI already produced. A source package earns its keep when the build is configurable, when upstream ships no binary, or when the binary is linked against libraries Arch does not have. None of those hold. On the last one, `-bin` is the safer side: CI builds on Ubuntu 24.04, whose glibc is older than Arch's, and a binary built against an older glibc runs on a newer one, not the reverse.

The PKGBUILD still carries `provides=('qrious')` and `conflicts=('qrious')`, which the AUR expects of any `-bin` package, so a source package could be added beside it later without the two installing over each other. Revisit only if the build ever grows options.

## The AUR before Flatpak

Flatpak would reach more distributions, and most of its inputs already exist: the desktop entry and AppStream file in [packaging/](../packaging/) are the ones a Flatpak manifest would install. What it would break is **Copy image**.

Flutter's clipboard carries text only, so [lib/image_clipboard.dart](../lib/image_clipboard.dart) copies the PNG by running `wl-copy` or `xclip` (see [ui.md](ui.md#saving-and-copying-the-code)). Under pacman that is a plain `exec` of a binary the package lists in `optdepends`. Inside a Flatpak sandbox the host's binaries are not visible, so the call would have to go through `flatpak-spawn --host` — a sandbox hole that needs a permission Flathub reviews closely — or the app would bundle its own `wl-clipboard` and `xclip`. Either is a design change to the copy path, not a packaging step, so Flatpak waits until reach beyond Arch is worth that.

## Install layout

| Path | What |
| --- | --- |
| `/usr/lib/qrious/` | The Flutter bundle, whole: `qrious`, `lib/`, `data/` |
| `/usr/bin/qrious` | A symlink to `/usr/lib/qrious/qrious` |
| `/usr/share/applications/` | `io.github.samwell9854.qrious.desktop` |
| `/usr/share/metainfo/` | `io.github.samwell9854.qrious.metainfo.xml` |
| `/usr/share/icons/hicolor/<size>x<size>/apps/` | The icon at each size from [linux/icons/](../linux/icons/) |
| `/usr/share/licenses/qrious-bin/LICENSE` | The licence text |

**The bundle cannot be split across `/usr/bin` and `/usr/lib`.** The executable finds `lib/` and `data/` relative to its own location: its RUNPATH is `$ORIGIN/lib`, and the Flutter engine reads its assets and ICU data from `data/` beside the executable. Dropping `qrious` into `/usr/bin` would leave it looking for `/usr/bin/lib` and `/usr/bin/data`. Keeping the bundle whole under `/usr/lib/qrious/` is what Arch does for other self-contained application trees, and the symlink puts the command on `PATH`. A symlink works where a copy would not because both the dynamic loader's `$ORIGIN` and the engine resolve the executable's real path, which is inside the bundle.

The same rule applies one level down. Flutter installs plugin libraries into `lib/` as plain copies, so by default they keep the RUNPATH of the machine that built them, an absolute path into its checkout. On the user's machine that path does not exist, or worse, it exists and holds something else. [linux/CMakeLists.txt](../linux/CMakeLists.txt) gives every plugin `$ORIGIN` instead, and CI fails any build whose bundled libraries search outside the bundle. That fix belongs in the build rather than in the PKGBUILD, so every consumer of the tarball gets a relocatable bundle, not just this package.

`depends=()` is the list of libraries the bundle actually links, as `namcap` reports from the built package's ELF headers. It is not a guess at what GTK pulls in. `wl-clipboard` and `xclip` are optional because only **Copy image** needs them, and the app names the missing one when neither is installed.

## How a release flows

1. **Tag.** `version:` in [pubspec.yaml](../pubspec.yaml) is reconciled and committed, and `dart run tool/new_release.dart` derives the tag from it ([versioning-and-releases.md](versioning-and-releases.md)). Pushing the tag starts the release.
2. **Build.** `release.yml` first runs [ci.yml](../.github/workflows/ci.yml) in full, so a tag passes the same format, analysis, test and RUNPATH checks as any push, against the same pinned Flutter. It also refuses a tag that disagrees with `version:`.
3. **Package.** The bundle, desktop entry, metainfo, icons and `LICENSE` are assembled into `qrious-<version>-linux-x86_64/`, already laid out as under `/usr`, so the PKGBUILD's `package()` is copies and a symlink. The metainfo's `<releases>` entry is written at this step from the checked version, because a hand-kept one would go stale. The archive is built with sorted entries and fixed owners and timestamps, so the same tree always gives the same checksum.
4. **Publish.** The tarball and its `.sha256` go up as a GitHub release, marked prerelease when the version carries a label.
5. **Bump the AUR.** `render.sh` downloads the tarball, verifies it against the published `.sha256`, and writes the PKGBUILD and a `.SRCINFO` from `makepkg --printsrcinfo` into the AUR clone. That is committed and pushed by hand.

Only stable releases reach the AUR. A `-preview` build is tested by installing its tarball locally through the same template (`render.sh -t` against a scratch directory, then `makepkg -si`); publishing it would hand others the build whose whole label says it has not been run yet. The AUR's own convention for a testing variant, a `-git` package, is a source build and would bring back the Flutter SDK problem above.

The tarball name carries the architecture, and the PKGBUILD uses `source_x86_64=()` rather than `source=()`, even with one architecture. A second architecture is then a second CI job and a second pair of arrays, not a rename of anything already published.

### Two details of the rendered PKGBUILD

**`pkgver` drops the hyphen from a prerelease name.** pacman forbids hyphens in `pkgver`, and of the two obvious substitutes only removal sorts correctly: `vercmp` puts `2026.10.0preview.1` below `2026.10.0`, but treats `_` as a separator, which puts `2026.10.0_preview.1` above it. The release name is kept separately as `_version`, because the download URL needs the tag exactly as it was pushed.

**The template has no maintainer.** The `# Maintainer:` line is filled at render time from the AUR clone's local git identity. Whoever maintains the package is not necessarily whoever wrote the app, and a name written into this repository would claim they are the same.

## The app ID

The application ID is **`io.github.samwell9854.qrious`**. It is the GTK application ID in [linux/CMakeLists.txt](../linux/CMakeLists.txt), the `StartupWMClass` that lets the desktop group the running window with its launcher, the window's icon name, and the basename of three installed files — the desktop entry, the metainfo and the icon.

Reverse-DNS IDs are meant to start from a domain the project controls. Qrious has no domain of its own, and a `com.` prefix built from a username would claim one that does not exist. `io.github.<user>` is the established form for a project hosted on GitHub, rooted in a namespace the account really does own, and it is the form Flathub accepts. It also says where the source lives, which is what someone checking a package's provenance wants to know.

**The ID is effectively permanent.** It names files on every machine that installed the package, so renaming it later would leave a stale desktop entry and icon behind on each one and break any shortcut or setting keyed on the old name.
