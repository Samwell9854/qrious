# Qrious

A QR code generator built with Flutter. Pick a format, fill in the fields, and the QR code plus its raw payload update live as you type. The layout adapts from a two-column desktop window to a single scrolling column at phone width.

**Status: alpha.** Not yet something to hand to anyone — see [docs/versioning-and-releases.md](docs/versioning-and-releases.md).

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
