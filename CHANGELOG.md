# Changelog

What each release changes, for the people using the app. Each section becomes that version's GitHub release notes, so it is written before the release is tagged. Earlier releases predate this file.

## 2026.11.0

Expert mode: everything the QR spec allows, from the symbol version to every vCard phone type. Beginner codes also get smaller.

### Expert mode

- **Turn on Expert mode** at the top of Settings. Beginner mode stays as it was; Expert mode names things as the spec does and offers the rest. Turning it off keeps your expert choices, unused, for when you turn it back on. ([#13](https://github.com/Samwell9854/qrious/issues/13))
- **Error correction by its letter**, as in *Q – High (25%)*, with Auto still on offer.
- **Any image size**, as a number of pixels per module from 1, up to an image of 32,768 pixels a side.
- **The quiet zone**, the white margin around the code, from 0 modules up. The spec's 4 is the default, and the preview, full screen, saved files and copied images all use it.
- **The version** (1 to 40, the code's size), **the mask** (0 to 7) and **the encoding mode** (numeric, alphanumeric or byte for the whole text), each Auto by default.
- **Nothing impossible is offered.** A choice the text cannot take is greyed out with the reason, such as *Numeric · digits only*. When the text outgrows a choice you made, the code uses the nearest that fits and says so under the code, and your choice comes back once the text is short enough.
- **The caption under the code** shows the version and its size, the mask, the modes used and the quiet zone. It no longer says *Auto*; instead, in either mode, whatever you changed from Settings for this code is highlighted.
- Each of these has a launch default in Settings, shown in Expert mode.
- Version 15 at H is greyed out: the QR library Qrious uses draws that combination wrong, and it has been reported.

### Formats, in expert mode

- **Location:** altitude and uncertainty, in metres.
- **Contact (MeCard):** nickname, name reading, video phone, birthday (with a calendar) and note.
- **Text Message (SMS):** the `sms:` form, which can text several people at once.
- **Contact (vCard):** every phone and email type from the vCard spec, such as Voice, Pager or Internet, several at once, and *Main* to mark the main number or address.
- **Reading a code** with any of these opens it in its form in Expert mode. In Beginner mode it opens as text, and the notice says Expert mode has the fields for it.

### Codes and images

- **Smaller codes.** Digits and upper-case text are now written in the QR spec's compact modes, so a code with a long number in it can come out a size smaller.
- **The preview's white margin is the quiet zone**, so the code fills more of the box. What you see is exactly what is saved.
- **Saved and copied PNGs are made differently**: black and white, smaller files, and quicker to make at large sizes.
- An SMS number no longer takes a pause (`,`), which means nothing to a text message.

### Issues

Fixes #13.

## 2026.10.5

Settings for what each new code starts with, and codes shown light on dark now read.

### Settings

- **Settings**, behind the gear in the title bar, choose the error correction and image size each launch starts with. The choices beside the code still change the code in front of you. ([#10](https://github.com/Samwell9854/qrious/issues/10))
- **Save without the menu.** Set *Save as* to *Always PNG image* or *Always SVG image*, and the button becomes **Save PNG** or **Save SVG** and goes straight to the save dialog. *Ask each time* keeps the menu.
- Each setting marks its built-in choice, such as *Auto (default)*, and **Reset to defaults** puts all of them back at once.
- Changes apply as you make them and are kept in `~/.config/qrious/settings.json`.

### Reading a code

- **Light-on-dark codes read**, from an image file, a pasted image or the camera. A code drawn in light squares on a dark background, as dark-themed apps and web pages often show them, was reported as "No QR code found". A picture holding one of each kind offers both.

### Issues

Fixes #10.

## 2026.10.4

Scan a QR code with your webcam.

### Reading a code

- **Scan with camera.** Use **Read a QR code** in the title bar, then **Scan with camera…**, and hold the code up to the webcam. The preview shows it like a mirror, and the first code it reads opens in the form. With several cameras, pick one from the list. ([#4](https://github.com/Samwell9854/qrious/issues/4))
- **Choose the moment yourself.** When the camera keeps reading the wrong code first, for example while you move one code into view past another, turn off **Read automatically**, then press **Capture** (or Space) once the right code is in view. When the picture holds several codes, Qrious asks which one to read, as it does for an image.
- **Every code in a picture is offered**, from the camera or from an image file. A phone screen and a printed code in the same picture each need different processing to read, and only the first one found was offered.
- Scanning needs GStreamer's good plugins (`gst-plugins-good` on Arch). Without them, the scanner says what to install; everything else works as before.

### Issues

Part of #4, which stays open: reproducing a scanned code module for module comes later.

## 2026.10.3

Read a QR code back from a picture, and edit it as a form.

### Reading a code

- **Read a QR code from an image.** Use **Read a QR code** in the title bar, then **Open image…** (Ctrl+O) to pick a file, or **Paste image** (Ctrl+V). You can also **drop an image file** on the window. The code opens in the form for its format, so you can change it and make a new one. ([#4](https://github.com/Samwell9854/qrious/issues/4))
- **Ctrl+V reads an image on the clipboard** without any extra step. It only does so when the clipboard holds an image and no text, so pasting text into a field works as before.
- **SVG files read too**, including the ones Qrious saves itself and those from other apps. This needs `librsvg`, which most Linux desktops already have.
- **Pasting a copied image file works.** Copy an image in your file manager or image viewer, then press Ctrl+V (with no text field focused) or choose **Paste image**.
- **An image with several codes** asks which one to read.
- A photo of a printed code reads too, even when the print is speckled. Text in any language comes out intact.
- **When a code opens as plain text.** If a form could not write the code back exactly (it would drop a field it has no place for, or lay the same content out differently, which makes a different code), the code opens in Text with its text exactly as scanned. A note says which format it was recognised as and why, and **Open in <format> form** loads it into that form anyway, at the cost of that difference. The code drawn from that text can still look different from the original: the same text can be drawn many valid ways, and matching the original pattern comes later.
- **Undo** (the button or Ctrl+Z) brings back what the form held before a code was read, as it does after Clear.
- Copying and reading the clipboard both need `wl-clipboard` on Wayland or `xclip` on X11.

### Everyday use

- **Open and Save show your desktop's own file dialog** (KDE's on Plasma, GNOME's on GNOME) instead of GTK's, which drew its file-type menu wrongly on KDE under Wayland. Where no desktop portal is running, the GTK dialog is used as before.

### Issues

Part of #4, which stays open: reading from the camera and reproducing a scanned code module for module come later.

## 2026.10.2

A full-screen view for scanning, three new formats, and contacts with as many phones, emails and addresses as you need.

### Scanning from the screen

- **Show the code full screen** by clicking or tapping it, at the largest size the screen allows. Click anywhere or press Esc to close. ([#11](https://github.com/Samwell9854/qrious/issues/11))
- When a code is too dense to scan comfortably at its current size, a note under it says so. The threshold is the code's size in millimetres on your actual screen, read from the monitor. ([#11](https://github.com/Samwell9854/qrious/issues/11))
- The preview now uses the space it has: it grows with the window and stays square at any size.

### Formats

- **New formats:** Text Message (SMS), Location (latitude and longitude), and Contact (MeCard, compact), a contact card that makes a smaller code than a vCard. ([#3](https://github.com/Samwell9854/qrious/issues/3))
- **The format picker groups formats** by what scanning the code does (Connect, Contact, Call or message, Web & maps, Show text), with an icon beside each.
- **Each format remembers what you typed** until the app closes, so picking the wrong one by mistake loses nothing. A **Clear** button empties the current format, with Undo, and Ctrl+Z also works afterwards.
- "WiFi" is now spelled "Wi-Fi".

### Contacts

- **Add as many phones, emails and addresses as you need** to a vCard, each labelled Mobile, Home, Work and so on. None are shown until you add one.
- The postal address is split into street, city, province or state, postal code and country, so phones import each part into the right place.
- Phone numbers accept `,` for a pause (an extension, like `+15145550000,274`), and `*` and `#` for service codes. vCard numbers also accept `;` for a wait.
- Fixed MeCard websites importing as `http://https\://…` on the iPhone.

### Everyday use

- **Show a password** with the eye button beside it.
- Multi-line fields (plain text, email body) grow as you type.
- Tab goes through every field before moving to the code panel.
- A long payload no longer pushes the code off the screen or overflows the window: the panel scrolls instead.

### Issues

Implements #11.

Control over how the code is built, SVG export for print, and a title bar that matches the rest of the desktop.

### Error correction and image size

- **Choose the error correction level.** Auto, the default, guarantees Medium and raises it to High or Highest whenever that keeps the code the same size. Until now every code used Low, the weakest level. ([#5](https://github.com/Samwell9854/qrious/issues/5))
- **Choose the image size**, from Small to Extra large. Sizes are whole pixels per module, so a short URL makes a small file, a long contact card a large one, and every module edge is pixel-sharp. ([#5](https://github.com/Samwell9854/qrious/issues/5))
- A caption under the code shows the level in use, how much damage it survives, and the image size.
- Content too long for the chosen level now says so, instead of failing to draw.

### SVG export

- **Save as SVG** as well as PNG, from the Save button's menu. Being vector, it prints at any size without blurring. ([#6](https://github.com/Samwell9854/qrious/issues/6))

### Desktop

- **Outside GNOME, the desktop now draws the title bar**, so it matches other apps' height and shows the app icon. ([#1](https://github.com/Samwell9854/qrious/issues/1), [#2](https://github.com/Samwell9854/qrious/issues/2))
- The window title reads "Qrious" instead of "qrious".

### Issues

Fixes #1 and #2. Implements #5 and #6.
