# The UI

Everything lives in [lib/screens/home_screen.dart](../lib/screens/home_screen.dart) — one `StatefulWidget`, no state-management package, no routing.

## State

- `_formats` — the registry; `_formats.first` (WiFi) is the initial selection.
- `_selectedFormat` — current `QrFormat`.
- `_values` — `Map<String, String>`, one entry per field of the current format.
- `_controllers` — `TextEditingController` per *text-like* field only (dropdown and checkbox fields have no controller).

`_initControllers()` is the reset point: it disposes old controllers, clears both maps, then seeds each field's initial value and attaches a listener that writes controller text back into `_values` and calls `setState`. It runs in `initState` and again on every format switch — a format change discards all entered values by design.

`dispose()` disposes the controllers; anything added to `_controllers` must be disposable there.

## Derived getters

- `_qrString` → `_selectedFormat.buildQrString(_values)`, recomputed each build.
- `_isReady` → every `required` field has a non-empty value.

## Layout

`build` wraps everything in a `SafeArea` + `LayoutBuilder` and picks one of two layouts at the `_wideLayoutBreakpoint` (700 logical px). Both share `_buildFormatPicker`, `_buildField`, and `_buildQrPanel`.

**Wide** (`_buildWideLayout`, 24px padding) — a two-column `Row`:

- Left, fixed 380px: the format dropdown, then an `Expanded` `SingleChildScrollView` of fields.
- Right, `Expanded`: the QR panel with `expandPreview: true`, so the preview absorbs the leftover vertical space, and a fixed 260px code.

**Narrow** (`_buildNarrowLayout`, 16px padding) — one `SingleChildScrollView` containing the picker, the fields, then the QR panel below them. The preview is padded rather than `Expanded` (an `Expanded` inside an unbounded scroll view would throw), and `qrSize` is derived from the available width — `(width - 32).clamp(120, 260)`, the 32 accounting for the white container's 16px padding on each side.

Fields themselves are dispatched on `field.type` by `_buildField` via a `switch` expression (`_` falls through to a plain `TextFormField`, with a `*` suffix when required).

`_buildQrPanel({required double qrSize, required bool expandPreview})` renders the `QrImageView` on a forced white rounded container (so it scans in dark mode) when `_isReady && qrString.isNotEmpty`, otherwise a placeholder prompt. Below it: a `SelectableText` of the raw payload in monospace, plus a copy-to-clipboard `IconButton` with a snackbar confirmation. `errorStateBuilder` handles payloads too large to encode (reachable with a long vCard or free text).

## Saving the code

The preview panel carries a **Save PNG** button, enabled on the same condition as the preview itself. It asks where to save through [pickPngSaveLocation](../lib/save_location.dart), renders the image with [renderQrPng](../lib/qr_png.dart) and writes it; cancelling is not a failure and says nothing, and a write that fails reports itself in a snackbar rather than throwing.

The saved image is not the widget on screen. `QrPainter` paints modules and nothing else, so the preview relies on its white `Container` for a background and on the panel's padding for the quiet zone the spec requires — neither of which exists in a file. `renderQrPng` therefore paints black on an opaque white square with its own margin, whatever the theme is doing, because a transparent PNG dropped on a dark background is a code no scanner can read.

`HomeScreen` takes a `pickSaveLocation` seam, defaulted to the real dialog. The dialog is the one part of saving that cannot run headless; rendering and writing are exercised for real in [test/save_qr_test.dart](../test/save_qr_test.dart), against a temp directory.

## The version badge

The app bar's title is [AppTitle](../lib/widgets/app_title.dart): the app name with a [VersionBadge](../lib/widgets/version_badge.dart) beside it. The badge is there rather than in `actions` because Flutter paints the debug ribbon across the top right corner and it sits on top of anything parked there; it is `Flexible` and ellipsises so a long version cannot overflow the title row on a phone. The badge is a chip showing the running build's version, styled in three states so they cannot be confused: a prerelease is called out in the tertiary container colour, a stable release is quiet, and a version the parser cannot read is flagged as an error rather than passing for a shippable build. It reads asynchronously via `AppVersion.load()` and renders nothing while loading or on failure, so being unable to read the bundle never costs the user their app bar. See [versioning-and-releases.md](versioning-and-releases.md).

## Theming

`main.dart` sets Material 3 with `ColorScheme.fromSeed(seedColor: Colors.indigo)` and a matching dark scheme; the system setting selects between them. Use `Theme.of(context).colorScheme` tokens rather than literal colors — the two deliberate exceptions are the white QR backdrop and the grey placeholder text.
