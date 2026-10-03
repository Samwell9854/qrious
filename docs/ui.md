# The UI

Everything lives in [lib/screens/home_screen.dart](../lib/screens/home_screen.dart) — one `StatefulWidget`, no state-management package, no routing.

## State

- `qrFormats` — the registry, imported from [lib/formats/registry.dart](../lib/formats/registry.dart); `qrFormats.first` (WiFi) is the initial selection. The screen holds no format list of its own, which is what keeps adding a format out of this file.
- `_selectedFormat` — current `QrFormat`.
- `_values` — `Map<String, String>`, one entry per field of the current format.
- `_controllers` — `TextEditingController` per *text-like* field only (dropdown and checkbox fields have no controller).
- `_errorCorrection` and `_imageSize` — the output choices under the preview, `auto` and `medium` to start. A format switch keeps them: they describe the output, not the content.

`_initControllers()` is the reset point: it disposes old controllers, clears both maps, then seeds each field's initial value and attaches a listener that writes controller text back into `_values` and calls `setState`. It runs in `initState` and again on every format switch — a format change discards all entered values by design.

`dispose()` disposes the controllers; anything added to `_controllers` must be disposable there.

## Derived getters

- `_qrString` → `_selectedFormat.buildQrString(_values)`, recomputed each build.
- `_errorFor(field)` → the validator's message for a non-empty value, else null. Empty is never an error; see [formats.md](formats.md#validation).
- `_encode(qrString)` → the payload as an `EncodedQr` at `_errorCorrection`, or null when it is too long for the largest symbol at that level. The preview, its caption, **Save PNG** and **Copy image** all go through it, so what is saved is what is shown.
- `_isReady` → every `required` field has a non-empty value **and** no field has an error. The second half is why an optional field that is filled in wrongly still holds the code back.

## Layout

`build` wraps everything in a `SafeArea` + `LayoutBuilder` and picks one of two layouts at the `_wideLayoutBreakpoint` (700 logical px). Both share `_buildFormatPicker`, `_buildField`, and `_buildQrPanel`.

**Wide** (`_buildWideLayout`, 24px padding) — a two-column `Row`:

- Left, fixed 380px: the format dropdown, then an `Expanded` `SingleChildScrollView` of fields.
- Right, `Expanded`: the QR panel with `expandPreview: true`, so the preview absorbs the leftover vertical space, and a fixed 260px code.

**Narrow** (`_buildNarrowLayout`, 16px padding) — one `SingleChildScrollView` containing the picker, the fields, then the QR panel below them. The preview is padded rather than `Expanded` (an `Expanded` inside an unbounded scroll view would throw), and `qrSize` is derived from the available width — `(width - 32).clamp(120, 260)`, the 32 accounting for the white container's 16px padding on each side.

Fields themselves are dispatched on `field.type` by `_buildField` via a `switch` expression (`_` falls through to a plain `TextFormField`, with a `*` suffix when required). `_buildField` computes the error once and passes it as `errorText` to each text-bearing branch; dropdowns and checkboxes cannot hold a bad value, so they have none.

An `errorText` grows the field by a line, and that has to hold at 390px as well as on the desktop — [test/field_validation_test.dart](../test/field_validation_test.dart) fills a vCard with every validated field wrong at once to keep the narrow layout honest.

`_buildQrPanel({required double qrSize, required bool expandPreview})` renders the encoded symbol with `QrImageView.withQr` on a forced white rounded container (so it scans in dark mode) when `_isReady` and the payload encodes, a red "too much data" message when it is ready but too long for the chosen level (reachable with a long vCard or free text), and a placeholder prompt otherwise. Under the code, a caption says what was produced: the error correction actually used (prefixed `Auto:` when auto picked it), how much damage that survives, and the image size in pixels.

Below that, `_buildOutputOptions` puts the **Error correction** and **Image size** dropdowns side by side, each in an `Expanded` half of a `Row` with `isExpanded` and ellipsised labels, so the longest choices still fit at 390px ([test/output_options_test.dart](../test/output_options_test.dart) picks them at both widths). Then the buttons, and a `SelectableText` of the raw payload in monospace, plus a copy-to-clipboard `IconButton` with a snackbar confirmation.

## Error correction and image size

[lib/qr_encoding.dart](../lib/qr_encoding.dart) owns encoding. The QR spec has exactly four error-correction levels, offered under beginner names with the share of damage each survives: Low (L, 7%), Medium (M, 15%), High (Q, 25%), Highest (H, 30%). **Auto**, the default, takes the smallest symbol that holds the payload at Medium, then raises the level as far as it goes without a larger symbol. Symbols come in 40 fixed sizes and unused room is padding, so the stronger level costs nothing in size or density. Auto drops to Low only for a payload Medium cannot hold at any size.

[lib/qr_png.dart](../lib/qr_png.dart) sizes the image in whole pixels per module (`ImageSize`: 4, 8, 16 or 32), with the spec's four-module quiet zone. Per module rather than per image, so a short URL makes a small file and a dense vCard a large one, and every module edge falls on a pixel boundary instead of anti-aliasing into grey.

The spec letters, a freely typed size and the other spec-level knobs belong to expert mode ([#13](https://github.com/Samwell9854/qrious/issues/13)); changing the defaults belongs to settings ([#10](https://github.com/Samwell9854/qrious/issues/10)).

## Saving and copying the code

The preview panel carries **Save PNG** and **Copy image** buttons, both enabled on the same condition as the preview itself, side by side in a `Row` of `Expanded` children so two buttons still fit the phone layout. **Copy image** is only built where [imageClipboardSupported](../lib/image_clipboard.dart) is true. It asks where to save through [pickPngSaveLocation](../lib/save_location.dart), renders the image with [renderQrPng](../lib/qr_png.dart) at the chosen size and writes it; cancelling is not a failure and says nothing, and a write that fails reports itself in a snackbar rather than throwing.

The saved image is not the widget on screen. `QrPainter` paints modules and nothing else, so the preview relies on its white `Container` for a background and on the panel's padding for the quiet zone the spec requires — neither of which exists in a file. `renderQrPng` therefore paints black on an opaque white square with its own margin, whatever the theme is doing, because a transparent PNG dropped on a dark background is a code no scanner can read.

Copying goes around Flutter entirely. `Clipboard.setData` carries `text/plain` and nothing else, so [copyPngToClipboard](../lib/image_clipboard.dart) pipes the PNG to a session clipboard helper on stdin: `wl-copy` on Wayland, `xclip` on X11. A Wayland session without `wl-clipboard` installed falls through to `xclip` rather than giving up, because XWayland makes it work — the common case on a desktop that has one but not the other. Both helpers fork a child to hold the selection and exit immediately, so the exit code is worth waiting for. When neither is installed the error names what to install, and that message reaches the user unchanged.

This is a **Linux-only stopgap**. iOS has an image clipboard that Flutter does not expose, so it will need a platform channel or a package like `super_clipboard`, which works everywhere but requires a Rust toolchain — a cost worth paying once there is a second platform to pay it for, not before. Everything is behind one function to keep that swap cheap.

`HomeScreen` takes `pickSaveLocation` and `copyImage` seams, defaulted to the real dialog and the real clipboard. Those are the parts that cannot run headless; rendering, writing and the helper choice are exercised for real in [test/save_qr_test.dart](../test/save_qr_test.dart), [test/copy_image_test.dart](../test/copy_image_test.dart) and [test/image_clipboard_test.dart](../test/image_clipboard_test.dart) — the last of which round-trips a PNG through the actual clipboard when a helper is present, and skips itself when there is not one.

## The version badge

The app bar's title is [AppTitle](../lib/widgets/app_title.dart): the app name with a [VersionBadge](../lib/widgets/version_badge.dart) beside it. The badge is there rather than in `actions` because Flutter paints the debug ribbon across the top right corner and it sits on top of anything parked there; it is `Flexible` and ellipsises so a long version cannot overflow the title row on a phone. The badge is a chip showing the running build's version, styled in three states so they cannot be confused: a prerelease is called out in the tertiary container colour, a stable release is quiet, and a version the parser cannot read is flagged as an error rather than passing for a shippable build. It reads asynchronously via `AppVersion.load()` and renders nothing while loading or on failure, so being unable to read the bundle never costs the user their app bar. See [versioning-and-releases.md](versioning-and-releases.md).

## Theming

`main.dart` sets Material 3 with `ColorScheme.fromSeed(seedColor: Colors.indigo)` and a matching dark scheme; the system setting selects between them. Use `Theme.of(context).colorScheme` tokens rather than literal colors — the two deliberate exceptions are the white QR backdrop and the grey placeholder text.
