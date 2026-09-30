#!/usr/bin/env bash
#
# make_icons.sh
#
# Builds the Linux icon set from the artwork in assets/icon/.
#
#   48 px and up   downscaled from the master, assets/icon/qrious.png
#   16 to 32 px    rendered from the pixel-grid drawings in assets/icon/pixel/
#
# Below 48 px a downscaled master is a blur: its QR modules fall between pixels
# and the "WIFI:" in the lens smears into a white bar. The small sizes are drawn
# per size instead, with every module, finder and text bar on whole pixels, so
# only the lens ring and the handle are anti-aliased. The lens holds two lines of
# "text" at 22 to 32 px and nothing at 16 px. Edit those SVGs by hand; they are
# the source for their size, not generated from the master.
#
# Output goes to linux/icons/hicolor/<size>x<size>/apps/, the layout it installs
# to under /usr/share/icons/, named after the application ID.
#
# Requires ImageMagick 7 (`magick`) and librsvg (`rsvg-convert`).
#
# Usage:
#   tool/make_icons.sh
#

set -euo pipefail
cd "$(dirname "$0")/.."

app_id=io.github.samwell9854.qrious
master=assets/icon/qrious.png
pixel=assets/icon/pixel
out=linux/icons/hicolor

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The exported master is about 99% opaque across the plate; make the plate fully
# opaque while keeping the anti-aliased edge of the rounded corners.
magick "$master" -channel A -level 0,97% +channel "$work/full.png"

for size in 16 22 24 32 48 64 128 256 512; do
  dir=$out/${size}x${size}/apps
  mkdir -p "$dir"
  case $size in
    16 | 22 | 24 | 32)
      rsvg-convert -w "$size" -h "$size" "$pixel/qrious_$size.svg" -o "$work/$size.png"
      magick "$work/$size.png" -strip "PNG32:$dir/$app_id.png"
      ;;
    *)
      magick "$work/full.png" -filter Lanczos -resize "${size}x${size}" \
        -strip "PNG32:$dir/$app_id.png"
      ;;
  esac
done

echo "Wrote $out"
