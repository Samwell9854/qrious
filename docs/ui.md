# The UI

Everything lives in [lib/screens/home_screen.dart](../lib/screens/home_screen.dart) — one `StatefulWidget`, no state-management package, no routing.

## State

- `qrFormats` — the registry, imported from [lib/formats/registry.dart](../lib/formats/registry.dart); `qrFormats.first` (Wi-Fi) is the initial selection. The screen holds no format list of its own, which is what keeps adding a format out of this file.
- `_selectedFormat` — current `QrFormat`.
- `_values` — `Map<String, String>`, one entry per field of the current format.
- `_controllers` — `TextEditingController` per *text-like* field only (dropdown and checkbox fields have no controller).
- `_replacement` — the last Clear or read, kept for Undo; `_offer` — the notice a read leaves behind when its code opened as text (see [Reading a code](#reading-a-code)).
- `_errorCorrection` and `_imageSize` — the output choices under the preview, `auto` and `medium` to start. A format switch keeps them: they describe the output, not the content.

`_loadForm([saved])` is the reset point: it disposes old controllers, clears both maps, then seeds each field from `saved`, or with its initial value without it, and attaches a listener that writes controller text back into `_values` and calls `setState`. It runs in `initState` and on every format switch.

A format switch first copies `_values` into `_saved` under the old format's id, then loads the new format from whatever `_saved` holds for it. So each format remembers its values for the session, and picking the wrong format by mistake costs nothing: switching back restores the form. Nothing is written to disk; closing the app forgets it all.

The **Clear** button beside the picker (`_buildFormatRow`) empties the current format only, and is enabled only while `_hasInput` says something differs from a fresh form. It is a word, not an icon: no icon says "empty this form" plainly (`clear_all` was tried, and is known only from Android's notification shade). It asks nothing first, because a confirmation would add a click to every deliberate clear; instead it keeps a snapshot in `_replacement` and offers two ways back. Reading a code replaces the form's content too, so a Clear and a read share the one snapshot (see [Undo](#undo-a-read)):

- *Undo* in the snackbar. A snackbar with an action stays until dismissed by default, so this one sets `persist: false` and leaves after five seconds.
- **Ctrl+Z**, through a `Shortcuts`/`Actions` pair around the scaffold. Clear hands focus to the screen's own node: the field that had focus goes with the Clear, and a click on a button or on empty space focuses nothing, so the key would otherwise reach no shortcut here. The action is enabled only while there is a Clear to undo and the form is still empty; otherwise it reports itself disabled and the key goes on to a focused text field's own undo, which a `CallbackShortcuts` would have swallowed.

`_replacement` is a `_Replacement`: the format and values the replacement removed, the format and values it put there, and what the session memory held for the format it went into. `_canUndo` allows an undo only while the form still holds exactly what the replacement put there, so for a Clear it means "nothing typed yet", and for a read, the code as loaded. Once something has been typed since, restoring would lose that input instead, so the undo is refused. A format switch forgets the snapshot.

The picker itself is filled, unlike the outlined fields under it, because it decides what those fields are and should not pass for one of them. The fill is the same quiet `surfaceContainerHighest` as the payload box, and the emphasis is on the format's icon, in the primary colour, and its name in bold; the open menu stays plain. The menu lists formats under their groups' headings (see [formats.md](formats.md#groups)). A heading is a disabled item with no value, so it cannot be picked, and `selectedItemBuilder` gives it an empty entry to keep its list in step with the items.

`dispose()` disposes the controllers; anything added to `_controllers` must be disposable there.

## Derived getters

- `_qrString` → `_selectedFormat.buildQrString(_values)`, recomputed each build.
- `_errorFor(field)` → the validator's message for a non-empty value, else null. Empty is never an error; see [formats.md](formats.md#validation).
- `_encode(qrString)` → the payload as an `EncodedQr` at `_errorCorrection`, or null when it is too long for the largest symbol at that level. The preview, its caption, **Save** and **Copy image** all go through it, so what is saved is what is shown.
- `_isReady` → every `required` field has a non-empty value **and** no field has an error. The second half is why an optional field that is filled in wrongly still holds the code back.

## Layout

`build` wraps everything in a `SafeArea` + `LayoutBuilder` and picks one of two layouts at the `_wideLayoutBreakpoint` (700 logical px). Both share `_buildFormatPicker`, `_buildField`, and `_buildQrPanel`.

**Wide** (`_buildWideLayout`, 24px padding) — a two-column `Row`:

- Left, fixed 380px: the format dropdown, then an `Expanded` `SingleChildScrollView` of fields.

Each column is wrapped in its own `FocusTraversalGroup`, so Tab runs through every field before crossing to the panel and back. Ordered by position alone, focus zigzags into the panel wherever a field happens to sit level with its dropdowns.
- Right, `Expanded`: the QR panel without a `qrSize`. Everything under the code takes its natural height, and the code gets the rest: the largest square that fits (`_buildFittedCode`). A maximised window gets a large code; a short one gets a small code whose white box stays square rather than stretching to the panel's width. The code stops shrinking at `_minCodeArea` (a 200px code plus its caption), and past that the panel scrolls rather than overflowing. That arrangement is [FillThenScroll](../lib/widgets/fill_then_scroll.dart), a small render object inside a `SingleChildScrollView`: a `Column` cannot do it, because an `Expanded` inside a scroll view has nothing to expand into.

**Narrow** (`_buildNarrowLayout`, 16px padding) — one `SingleChildScrollView` containing the picker, the fields, then the QR panel below them. The preview is padded rather than `Expanded` (an `Expanded` inside an unbounded scroll view would throw), and `qrSize` is the smaller of the column's width and the viewport's height, less 32 for the white container's 16px padding on each side, and never under 120. The height bound keeps a short window able to see the whole code at once.

Fields themselves are dispatched on `field.type` by `_buildField` via a `switch` expression (`_` falls through to a plain `TextFormField`, with a `*` suffix when required). A `group` field goes to `_buildGroup` instead: its entries, then an *Add* button. `_addEntry` and `_removeEntry` keep the count and the entry keys in `_values` and a controller per text part in `_controllers`; removing rebuilds the group's controllers from its values, since each controller is bound to its key. A one-part entry is a single field with the kind as a `PopupMenuButton` in its `prefixIcon` and a remove button as its `suffixIcon`. A many-part entry is a hand-drawn box: a rounded outline with the legend (the kind menu) laid over its top edge on the scaffold background, which reads as a notch. `InputDecorator` would draw that notch itself, but its label never receives a tap, so the legend could not open its menu.

A multiline field starts at four lines and grows with its text up to twelve, then scrolls. A password field has an eye button to show it in the clear; which ones are shown lives in `_revealed`, cleared with everything else on a format switch, so a password is hidden again when its format comes back. Single-line fields stay single-line however long the text, and scroll sideways with the cursor, as in every other app. `_buildField` computes the error once and passes it as `errorText` to each text-bearing branch; dropdowns and checkboxes cannot hold a bad value, so they have none.

An `errorText` grows the field by a line, and that has to hold at 390px as well as on the desktop — [test/field_validation_test.dart](../test/field_validation_test.dart) fills a vCard with every validated field wrong at once to keep the narrow layout honest.

`_buildQrPanel({required double qrSize, required bool expandPreview})` renders the encoded symbol with `QrImageView.withQr` on a forced white rounded container (so it scans in dark mode) when `_isReady` and the payload encodes, a red "too much data" message when it is ready but too long for the chosen level (reachable with a long vCard or free text), and a placeholder prompt otherwise. Under the code, a caption says what was produced: the error correction actually used (prefixed `Auto:` when auto picked it), how much damage that survives, and the image size in pixels.

Below that, `_buildOutputOptions` puts the **Error correction** and **Image size** dropdowns side by side, each in an `Expanded` half of a `Row` with `isExpanded` and ellipsised labels, so the longest choices still fit at 390px ([test/output_options_test.dart](../test/output_options_test.dart) picks them at both widths). Then the buttons, and a `SelectableText` of the raw payload in monospace (named fonts first, Noto Sans Mono then DejaVu and Liberation, because the generic `monospace` can land on a Japanese font such as MS Gothic, which draws the backslash as a yen sign), plus a copy-to-clipboard `IconButton` with a snackbar confirmation. The payload box stops at `_maxDataHeight` (about eight lines) and scrolls inside itself: it is there to glance at, the button copies all of it, and left to grow it would take the code's height. [test/long_input_test.dart](../test/long_input_test.dart) fills a near-maximum payload into desktop, short, small and phone windows to keep both layouts honest.

## Error correction and image size

[lib/qr_encoding.dart](../lib/qr_encoding.dart) owns encoding. The QR spec has exactly four error-correction levels, offered under beginner names with the share of damage each survives: Low (L, 7%), Medium (M, 15%), High (Q, 25%), Highest (H, 30%). **Auto**, the default, takes the smallest symbol that holds the payload at Medium, then raises the level as far as it goes without a larger symbol. Symbols come in 40 fixed sizes and unused room is padding, so the stronger level costs nothing in size or density. Auto drops to Low only for a payload Medium cannot hold at any size.

[lib/qr_png.dart](../lib/qr_png.dart) sizes the image in whole pixels per module (`ImageSize`: 4, 8, 16 or 32), with the spec's four-module quiet zone. Per module rather than per image, so a short URL makes a small file and a dense vCard a large one, and every module edge falls on a pixel boundary instead of anti-aliasing into grey. [lib/qr_svg.dart](../lib/qr_svg.dart) draws the same matrix in module units, one path segment per run of dark modules; `ImageSize` only sets the width and height an SVG opens at.

The spec letters, a freely typed size and the other spec-level knobs belong to expert mode ([#13](https://github.com/Samwell9854/qrious/issues/13)); changing the defaults belongs to settings ([#10](https://github.com/Samwell9854/qrious/issues/10)).

## Showing the code full screen

The code is often scanned straight off the screen by another phone, and the preview shrinks its modules as the payload grows: a long vCard reaches about 100 modules a side, roughly 2.5px each in a phone-width preview. Tapping or clicking the preview opens [FullScreenQr](../lib/widgets/full_screen_qr.dart), the code alone on white at the size of the screen's shorter side, with the spec's four-module quiet zone. A tap anywhere or Esc closes it.

The code itself is the control, not a button beside it. On a desktop it shows a zoom cursor and a *Show full screen* tooltip on hover; on any platform, when the preview's modules fall under `_comfortableModuleMillimetres` (0.5mm) on the screen, a line under the caption says the code is dense and to tap it (Android and iOS) or click it (everything else) to show it full screen. A short code, which scans fine as it is, says nothing.

The judgement is in millimetres, not pixels, because 1080 pixels across a 24" monitor and across a phone are different sizes in the world, and a phone camera sees the world. Flutter does not report a screen's physical size, so [readMillimetresPerPixel](../lib/pixel_size.dart) asks the Linux runner, which divides the monitor's diagonal in millimetres (from GDK, which reads it off the monitor) by its diagonal in logical pixels. Diagonals, because they do not change when a monitor is rotated. It asks again on every metrics change, which covers moving the window to another monitor. A monitor that reports no size, as virtual ones and some projectors do, falls back to the conventional logical pixel: 96 per inch on a desktop, 160 on a phone. The 0.5mm is a judgement from one test: 1.4mm modules scanned instantly from about 1.2m, which is the same angle as 0.45mm at a handheld 40cm.

Full screen means the screen, not just the window. Flutter has no desktop call for it, so [setFullScreen](../lib/full_screen.dart) sends `setFullScreen` on the `qrious/window` channel, which the Linux runner ([my_application.cc](../linux/runner/my_application.cc)) answers with `gtk_window_fullscreen`. A window the user had already made full screen stays that way on close. On a phone it hides the system bars instead. Failure is swallowed: the code still covers the whole window. `HomeScreen` takes `setFullScreen` and `readPixelSize` seams for tests, alongside the other two.

## Saving and copying the code

The preview panel carries **Save** and **Copy image** buttons, both enabled on the same condition as the preview itself, side by side in a `Row` of `Expanded` children so two buttons still fit the phone layout. **Copy image** is only built where [imageClipboardSupported](../lib/image_clipboard.dart) is true, and always copies a PNG.

**Save** opens a menu of [ExportFileType](../lib/qr_export.dart)s, PNG image and SVG image, instead of offering the types as filters in the save dialog: `file_selector_linux` does not report which filter was picked, and GTK does not rename the file when the filter changes. Settings may later let a default type skip the menu ([#10](https://github.com/Samwell9854/qrious/issues/10)). The pick goes to [pickSaveLocation](../lib/save_location.dart), which offers only that type; the returned path gets the type's extension unless it already ends in it, so `code.png` saved as SVG becomes `code.png.svg` rather than an SVG misnamed as a PNG. Then the type renders at the chosen size and the file is written. Cancelling is not a failure and says nothing, and a write that fails reports itself in a snackbar rather than throwing.

The saved image is not the widget on screen. `QrPainter` paints modules and nothing else, so the preview relies on its white `Container` for a background and on the panel's padding for the quiet zone the spec requires — neither of which exists in a file. `renderQrPng` and `renderQrSvg` therefore paint black on an opaque white square with their own margin, whatever the theme is doing, because a transparent PNG dropped on a dark background is a code no scanner can read.

Copying goes around Flutter entirely. `Clipboard.setData` carries `text/plain` and nothing else, so [copyPngToClipboard](../lib/image_clipboard.dart) pipes the PNG to a session clipboard helper on stdin: `wl-copy` on Wayland, `xclip` on X11. A Wayland session without `wl-clipboard` installed falls through to `xclip` rather than giving up, because XWayland makes it work — the common case on a desktop that has one but not the other. Both helpers fork a child to hold the selection and exit immediately, so the exit code is worth waiting for. When neither is installed the error names what to install, and that message reaches the user unchanged.

This is a **Linux-only stopgap**. iOS has an image clipboard that Flutter does not expose, so it will need a platform channel or a package like `super_clipboard`, which works everywhere but requires a Rust toolchain — a cost worth paying once there is a second platform to pay it for, not before. Everything is behind one function to keep that swap cheap.

`HomeScreen` takes `pickSaveLocation` and `copyImage` seams, defaulted to the real dialog and the real clipboard, and for reading a code `pickImageFile`, `readClipboardImage`, `clipboardOffersOnlyImage` and `decodeImage`. Those are the parts that cannot run headless; rendering, writing and the helper choice are exercised for real in [test/save_qr_test.dart](../test/save_qr_test.dart), [test/copy_image_test.dart](../test/copy_image_test.dart) and [test/image_clipboard_test.dart](../test/image_clipboard_test.dart) — the last of which round-trips a PNG through the actual clipboard when a helper is present, and skips itself when there is not one.

## Reading a code

The app bar's **Read a QR code** button opens a menu with two of the three ways to bring a code in from outside; the third has no control.

- **Open image…** (Ctrl+O) opens a file dialog through [pickImageFile](../lib/open_image.dart). The shortcut sits beside Ctrl+Z in the screen's `Shortcuts`, and a text field binds neither, so the key reaches it from a field.
- **Paste image** (Ctrl+V) reads the image on the clipboard, or the file a file manager or image viewer copied (see Ctrl+V below).
- **Drop** an image file anywhere on the window. A `FileDropRegion` ([lib/file_drop.dart](../lib/file_drop.dart)) covers the screen and a "Drop an image to read its QR code" overlay shows while a file is over it. Only the first file is read; the others are ignored. The drag itself is handled by the Linux runner, not a package: it accepts only `text/uri-list` and reports `enter`, `leave` and `drop` (with file paths) on the `qrious/drop` channel. The `desktop_drop` package was dropped because it asks for the `application/vnd.portal.filetransfer` target first, which file managers such as Dolphin offer, and then fetches the files through the FileTransfer portal, which refuses an unsandboxed app ("Invalid transfer"), so nothing arrived. GTK emits a leave right before the drop, so the screen gets leave then drop. A Flatpak build ([#9](https://github.com/Samwell9854/qrious/issues/9)) would receive portal paths and need to revisit this.

The open and save dialogs come from `file_selector`, which on Linux makes a `GtkFileChooserNative`. The runner sets `GTK_USE_PORTAL=1` (unless the user already set it) so GTK asks the XDG desktop portal and the dialog is the user's own desktop's, KDE's or GNOME's; GTK's own dialog drew its filter dropdown wrongly on KDE/Wayland. With no portal running GTK falls back to its own dialog. Only `GtkFileChooserNative` dialogs are affected.

All three go through `_runImport`, which allows one read at a time and clears its `_importing` flag whatever happens, so a failure can never leave the entry points disabled. A file that is not an image, an image with no code in it, and a clipboard with no image each say so in a snackbar.

An SVG file is drawn to pixels first ([svg_raster.dart](../lib/svg_raster.dart)), on a white background and about 1200 pixels on its long side, because the image decoder cannot read SVG and an SVG code is often black paths on a transparent canvas that would have no contrast to decode. The drawing is done by librsvg in the Linux runner ([svg_raster.cc](../linux/runner/svg_raster.cc)), reached over the `qrious/svg` channel: `rasterize` takes the file's bytes (a `Uint8List`) and answers with a PNG, or an error that becomes an `UnreadableImageException`. librsvg rather than a Dart package because it supports the whole format, including the nested `<svg>` elements other generators emit, which flutter_svg drew as a blank image (and so read as a code-less picture); it is the renderer GNOME uses, and GTK 3 already depends on it. The runner takes the size from width and height, else the viewBox, else a square, scales the long side to 1200 pixels (each side at most 4096) and paints white before the SVG. Reading happens in `_importBytes`, ahead of the decoder, for all three entry points; it is a seam of its own (`rasterizeSvgImage`) beside `decodeImage`.

### Ctrl+V

There is no step to arm before pasting. The clipboard labels its contents by type, and `_onKey` watches Ctrl+V through `HardwareKeyboard` and acts only when [clipboardOffersOnlyImage](../lib/image_clipboard.dart) says the clipboard holds an image and no text. That is exactly when a text field's own paste would have had nothing to paste, so the import never takes a paste away from a field. A clipboard with both, as a copied spreadsheet range has, pastes its text as it always did.

A file copied in a file manager or image viewer offers no image data, only its path as `text/plain` and as a `text/uri-list`, so that rule alone would never see it. [clipboardOffersImageFile](../lib/image_clipboard.dart) reads the list, takes the first `file:` URI (skipping comments and other schemes, per RFC 2483) and says whether it has an image extension (png, jpg, jpeg, gif, bmp, webp, svg). Ctrl+V then imports it, but only when no text field has focus: in a field the path is pasted as text, as in every app. Paste image reads the same file; one the decoder cannot open gets the usual "That file isn't an image Qrious can open."

The observer only watches: it returns false, so the key goes on to the focused field either way. It stays out of the way of dialogs (it checks that the screen's route is current) and of a read already under way.

### Several codes

A picture can hold more than one code. When it does, a dialog lists them, each under the name of the format it reads as with its payload below, and the pick is read as if it were the only one. Cancelling reads nothing. How the codes are found is in [lib/qr_decoding.dart](../lib/qr_decoding.dart): [zxing2](https://pub.dev/packages/zxing2), a port of ZXing, tried with its hybrid binarizer and then its global-histogram one, each at full size, half and a quarter, with a port of ZXing's multiple-barcode reader to find the rest. The two binarizers fail on different pictures: the hybrid one failed on a real printed, photographed code with speckle that the global-histogram one read. zxing2 also mangles non-ASCII text, which the decoder repairs.

zxing2 was chosen over flutter_zxing because it is pure Dart. There is no native build, and it runs in `flutter test`, so the decoder is tested against real images. It also exposes the module grid, which a later pass needs (below).

### Exact, or Text

What a read loads is decided by [importPayload](../lib/formats/import.dart), whose rule is in [formats.md](formats.md#importing). The screen shows its outcome in one of two ways.

- When a format reproduces the payload exactly, the form opens in that format with the values filled in, and the snackbar says "Code read into <format>".
- Otherwise the payload opens in **Text**, byte for byte, and a notice above the fields says "Recognised as <format>" and why the text was kept: what that form would drop, what it would reject, or, when nothing would be lost, that it lays the same content out differently, which makes a different code. Its **Open in <format> form** button loads the values the form can hold, trading exactness for fields; the close button dismisses it. The notice also goes away when the text is edited, since it was made for the text as scanned.

Text is the fallback because it is the only form that cannot change a payload. A scanned code is rarely Qrious's own, and quietly rewriting it (reordering the keys of a Wi-Fi code, dropping a vCard's `NOTE`) would make a different code. A payload with nothing lost but laid out differently lands in Text for the same reason. A form that preserves another generator's exact layout, and reproducing a scanned code module for module (the version, mode and mask are not in the decoded text, which alone does not fix the pattern), are a later expert pass on [#4](https://github.com/Samwell9854/qrious/issues/4), alongside [#13](https://github.com/Samwell9854/qrious/issues/13). The camera is another pass.

### Undo a read

A read replaces what the form held, so it takes the same snapshot as a Clear and offers the same two ways back: *Undo* in the snackbar and Ctrl+Z. `_applyImport` also saves the format the read leaves, as a format switch does, and Undo puts back the session memory of the format the code was read into, as if the read had never visited it. Taking the notice's **Open in <format> form** is a second replacement, with its own Undo.

Reading the clipboard is the same Linux-only stopgap as copying to it, for the same reason: Flutter's `Clipboard` carries text only. [clipboardTypes and readImageFromClipboard](../lib/image_clipboard.dart) ask `wl-paste` on Wayland and `xclip` on X11, with the same fall-through to `xclip` under XWayland, and the swap for iOS stays behind the same functions.

## The version badge

The app bar's title is [AppTitle](../lib/widgets/app_title.dart): the app name with a [VersionBadge](../lib/widgets/version_badge.dart) beside it. The badge is there rather than in `actions` because Flutter paints the debug ribbon across the top right corner and it sits on top of anything parked there; it is `Flexible` and ellipsises so a long version cannot overflow the title row on a phone. The badge is a chip showing the running build's version, styled in three states so they cannot be confused: a prerelease is called out in the tertiary container colour, a stable release is quiet, and a version the parser cannot read is flagged as an error rather than passing for a shippable build. It reads asynchronously via `AppVersion.load()` and renders nothing while loading or on failure, so being unable to read the bundle never costs the user their app bar. See [versioning-and-releases.md](versioning-and-releases.md).

## Theming

`main.dart` sets Material 3 with `ColorScheme.fromSeed(seedColor: Colors.indigo)` and a matching dark scheme; the system setting selects between them. Use `Theme.of(context).colorScheme` tokens rather than literal colors — the two deliberate exceptions are the white QR backdrop and the grey placeholder text.
