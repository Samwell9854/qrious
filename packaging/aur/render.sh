#!/usr/bin/env bash
#
# render.sh
#
# Renders PKGBUILD.in into a buildable qrious-bin PKGBUILD and its .SRCINFO.
#
#   render.sh [-v VERSION] [-t TARBALL] [-m MAINTAINER] OUTDIR
#
#   -v VERSION   the release name, e.g. 2026.10.0-preview.1. Defaults to version:
#                in pubspec.yaml, without its +build.
#   -t TARBALL   a locally built qrious-<version>-linux-x86_64.tar.gz. Its checksum
#                is used and it is copied into OUTDIR, so makepkg finds it there
#                instead of downloading. Without -t the tarball is downloaded from
#                the GitHub release, checked against the .sha256 published beside
#                it, and discarded; makepkg downloads it again itself.
#   -m MAINTAINER  "Name <email>" for the # Maintainer: line. Defaults to the
#                user.name and user.email set locally in OUTDIR, which is how the
#                AUR clone carries its identity. Without either, the line is left
#                out, which is fine for a scratch build.
#
# The maintainer is never written into the template: whoever packages this is not
# necessarily whoever wrote it, and this repository should not say otherwise.
#
# OUTDIR must lie outside this repository: only the template lives here, and a
# rendered copy is either a scratch build or the AUR clone.
#
# Requires curl and sha256sum, and makepkg for the .SRCINFO.

set -euo pipefail

here=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
repo=$(realpath "$here/../..")
url=https://github.com/Samwell9854/qrious

usage() {
  sed -n '7,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

version=
tarball=
maintainer=
while getopts 'v:t:m:h' opt; do
  case $opt in
    v) version=$OPTARG ;;
    t) tarball=$OPTARG ;;
    m) maintainer=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage

outdir=$(realpath -m "$1")
case $outdir/ in
  "$repo"/*)
    echo "error: $outdir is inside the repository; render outside it." >&2
    exit 1
    ;;
esac
mkdir -p "$outdir"

if [ -z "$version" ]; then
  version=$(sed -n 's/^version:[[:space:]]*//p' "$repo/pubspec.yaml")
  version=${version%%+*}
fi

# pkgver may not contain a hyphen. Dropping it, rather than turning it into "_",
# keeps 2026.10.0preview.1 below 2026.10.0 in vercmp.
case $version in
  *-*-* | *+* | '')
    echo "error: '$version' is not a release name." >&2
    exit 1
    ;;
esac
pkgver=${version/-/}

dist=qrious-$version-linux-x86_64.tar.gz

if [ -n "$tarball" ]; then
  if [ "$(basename "$tarball")" != "$dist" ]; then
    echo "error: expected a tarball named $dist, got $(basename "$tarball")." >&2
    exit 1
  fi
  sha256=$(sha256sum "$tarball" | cut -d' ' -f1)
  if [ "$(realpath "$(dirname "$tarball")")" != "$outdir" ]; then
    cp "$tarball" "$outdir/$dist"
  fi
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  release=$url/releases/download/v$version
  curl -fsSL -o "$tmp/$dist" "$release/$dist"
  curl -fsSL -o "$tmp/$dist.sha256" "$release/$dist.sha256"
  (cd "$tmp" && sha256sum --check --quiet "$dist.sha256")
  sha256=$(cut -d' ' -f1 "$tmp/$dist.sha256")
fi

# --local only: a fallback to the global identity would sign the package with the
# author's name.
if [ -z "$maintainer" ] && git -C "$outdir" rev-parse --git-dir > /dev/null 2>&1; then
  name=$(git -C "$outdir" config --local user.name || true)
  email=$(git -C "$outdir" config --local user.email || true)
  if [ -n "$name" ] && [ -n "$email" ]; then
    maintainer="$name <$email>"
  fi
fi

# The AUR's habit of spelling the address out, as user at host dot tld.
if [ -n "$maintainer" ]; then
  address=${maintainer##*<}
  address=${address%>}
  spelled=$(sed -e 's/@/ at /' -e 's/\./ dot /g' <<< "$address")
  maintainer_edit="s|^# Maintainer: @MAINTAINER@\$|# Maintainer: ${maintainer%%<*}<$spelled>|"
else
  echo "note: no maintainer given or set in $outdir; leaving the line out." >&2
  maintainer_edit='/^# Maintainer: @MAINTAINER@$/{N;d}'
fi

sed -e "$maintainer_edit" \
  -e "s|@VERSION@|$version|" \
  -e "s|@PKGVER@|$pkgver|" \
  -e "s|@SHA256@|$sha256|" \
  "$here/PKGBUILD.in" > "$outdir/PKGBUILD"

(cd "$outdir" && makepkg --printsrcinfo > .SRCINFO)

echo "Rendered qrious-bin $pkgver into $outdir"
