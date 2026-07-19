#!/bin/bash
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg.
# Uses only stock macOS tools: qlmanage (SVG raster), sips (resize), iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

qlmanage -t -s 1024 -o "$TMP" Resources/AppIcon.svg >/dev/null
MASTER="$TMP/AppIcon.svg.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
