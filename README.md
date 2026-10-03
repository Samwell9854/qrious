# Qrious

A QR code generator built with Flutter. Pick a format, fill in the fields, and the QR code plus its raw payload update live as you type. The layout adapts from a two-column desktop window to a single scrolling column at phone width.

> **This project is AI-written.** The code, tests and documentation are written by Claude, Anthropic's AI model, working under my direction. I decide what gets built and how it should behave, and I install and test every release myself before it ships. I do not write the code, and I do not review it either: I don't read Dart, so I judge the app by what it does, not by its source. That is vibe coding, and you can decide with that in mind. Every commit Claude contributed to carries a `Co-Authored-By` trailer, so the history shows it too.

## Installing

On Arch Linux, from the AUR:

```bash
paru -S qrious-bin
```

Each [GitHub release](https://github.com/Samwell9854/qrious/releases) also carries the Linux build as a tarball.

## Formats

| Format | Payload |
| --- | --- |
| WiFi | `WIFI:` network credentials (WPA/WPA2, WEP, or open; hidden networks supported) |
| Contact | vCard 3.0 |
| URL / Website | the URL as-is |
| Email | `mailto:` with optional subject and body |
| Phone Number | `tel:` |
| Plain Text | the text as-is |

The encoded string is shown beneath the code and can be selected or copied to the clipboard.

## Image export

The code can be saved as a file or, on Linux, copied to the clipboard as an image. These are the file types considered, and why each is or is not offered. The ones marked *not planned* stay that way unless a new feature changes the reasoning.

| File type | Status | Why |
| --- | --- | --- |
| PNG | Supported | Lossless, so module edges stay sharp, and readable by everything. |
| SVG | Supported | Vector, so it scales to posters and signage without blurring. |
| PDF | Parked ([#12](https://github.com/Samwell9854/qrious/issues/12)) | Vector and print-ready, but a PDF is a page, so it brings page size, orientation and placement choices that SVG avoids. |
| JPEG | Not planned | Lossy compression blurs the edges between modules, which makes the code harder to scan. |
| WebP, AVIF | Not planned | No gain over PNG for a two-colour image, and less widely supported. |
| EPS | Not planned | A legacy print format that SVG and PDF have replaced. |

## Running it

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.41+, Dart `^3.11.5`). Only the Linux desktop target is scaffolded. iOS is on indefinite hold: Apple's paid developer subscription isn't worth it for a free single-purpose app.

```bash
flutter pub get
flutter run -d linux
```

## Development

```bash
flutter analyze
flutter test
dart format lib test tool
```

Adding a new QR format takes one file in `lib/formats/` and one line in the format registry — see [docs/formats.md](docs/formats.md). The screen's state and its two layouts are described in [docs/ui.md](docs/ui.md).

Versions are calendar-based (`yyyy.m.micro`) and tags are derived from `version:` in `pubspec.yaml` by `dart run tool/new_release.dart` — never typed by hand. See [docs/versioning-and-releases.md](docs/versioning-and-releases.md).

Releases are built by CI from a tag and packaged for Arch Linux as `qrious-bin` on the AUR. Why it is packaged that way is in [docs/packaging.md](docs/packaging.md).

## License

Copyright © 2026 Samuel Giroux.

Qrious is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version (`GPL-3.0-or-later`). It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for the full text.
