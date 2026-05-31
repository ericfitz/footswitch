#!/usr/bin/env bash
#
# Build the app icon (AppIcon.icns) from Resources/icon/footswitch-source.png.
# Composites the pedal onto a Big Sur-style gradient rounded-rect tile (see
# Resources/icon/makeicon.swift), generates every required size, and assembles
# the .icns into Sources/Footswitch/Resources/.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/icon/footswitch-source.png"
GEN_SRC="$ROOT/Resources/icon/makeicon.swift"
OUT_ICNS="$ROOT/Sources/Footswitch/Resources/AppIcon.icns"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Compiling icon compositor"
swiftc -O -o "$WORK/makeicon" "$GEN_SRC" -framework AppKit

echo "==> Rendering 1024 master tile"
"$WORK/makeicon" "$SRC" "$WORK/master.png" 1024

echo "==> Generating iconset"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
# name              size  (Apple's required set: 16,32,128,256,512 @1x and @2x)
gen() { sips -z "$2" "$2" "$WORK/master.png" --out "$ICONSET/$1" >/dev/null; }
gen "icon_16x16.png"        16
gen "icon_16x16@2x.png"     32
gen "icon_32x32.png"        32
gen "icon_32x32@2x.png"     64
gen "icon_128x128.png"      128
gen "icon_128x128@2x.png"   256
gen "icon_256x256.png"      256
gen "icon_256x256@2x.png"   512
gen "icon_512x512.png"      512
gen "icon_512x512@2x.png"   1024

echo "==> Building $OUT_ICNS"
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"

echo "Done: $OUT_ICNS"
