#!/bin/zsh

set -euo pipefail

PROJECT_DIR=${0:A:h:h}
ICNS_PATH="$PROJECT_DIR/AppBundle/Resources/AppIcon.icns"
WORK_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/paperpdf-icon.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

MASTER="$WORK_DIR/AppIcon-1024.png"
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

swift "$PROJECT_DIR/Tools/generate_app_icon.swift" "$MASTER" >/dev/null

for entry in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
  128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x \
  512:icon_512x512 1024:icon_512x512@2x; do
  size=${entry%%:*}
  name=${entry#*:}
  sips --resampleHeightWidth "$size" "$size" "$MASTER" --out "$ICONSET/$name.png" >/dev/null
done

mkdir -p "${ICNS_PATH:h}"
iconutil --convert icns "$ICONSET" --output "$ICNS_PATH"

print "作成しました: $ICNS_PATH"
