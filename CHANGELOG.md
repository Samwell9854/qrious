# Changelog

What each release changes, for the people using the app. Each section becomes that version's GitHub release notes, so it is written before the release is tagged. Earlier releases predate this file.

## 2026.10.1

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
