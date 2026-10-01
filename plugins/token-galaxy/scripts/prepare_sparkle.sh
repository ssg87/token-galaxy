#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION=2.10.0
SHA=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
CACHE="$ROOT/Outputs/dependencies"
DEST="$CACHE/sparkle-$VERSION"
ARCHIVE="$CACHE/Sparkle-$VERSION.tar.xz"
mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 2 --silent --show-error "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.partial"
  mv "$ARCHIVE.partial" "$ARCHIVE"
fi
ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
[[ "$ACTUAL" == "$SHA" ]] || { print -u2 'Sparkle download checksum mismatch; refusing dependency.'; exit 1; }
if [[ ! -f "$DEST/Sparkle.framework/Versions/B/Sparkle" ]]; then
  mkdir -p "$DEST"
  tar -xJf "$ARCHIVE" -C "$DEST"
fi
print "$DEST"
