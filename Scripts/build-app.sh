#!/bin/zsh

set -euo pipefail

if (( $# > 1 )) || [[ "${1:-debug}" != (debug|release) ]]; then
  print -u2 "使い方: $0 [debug|release]"
  exit 64
fi

CONFIGURATION=${1:-debug}
PROJECT_DIR=${0:A:h:h}
BUILD_DIR=${PAPERPDF_BUILD_DIR:-"$PROJECT_DIR/.build"}
APP_DIR=${PAPERPDF_APP_DIR:-"$PROJECT_DIR/PaperPDFPrototype.app"}
SWIFTPM_CACHE_DIR="$BUILD_DIR/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$BUILD_DIR/swiftpm-config"
SWIFTPM_SECURITY_DIR="$BUILD_DIR/swiftpm-security"
CLANG_CACHE_DIR="$BUILD_DIR/clang-module-cache"
mkdir -p "$BUILD_DIR"
# Build the bundle outside Documents so file-provider provenance metadata is
# not inherited before signing. That metadata makes codesign reject an
# otherwise valid ad-hoc bundle as containing Finder detritus.
STAGING_PARENT=${PAPERPDF_STAGING_DIR:-${TMPDIR:-/private/tmp}}
mkdir -p "$STAGING_PARENT"
STAGING_ROOT=$(mktemp -d "$STAGING_PARENT/paperpdf-app-bundle.XXXXXX")
STAGED_APP_DIR="$STAGING_ROOT/PaperPDFPrototype.app"
PREVIOUS_APP_DIR="$STAGING_ROOT/previous.app"
trap 'rm -rf "$STAGING_ROOT"' EXIT

BUILD_ARGUMENTS=(
  --disable-sandbox
  --configuration "$CONFIGURATION"
  --package-path "$PROJECT_DIR"
  --scratch-path "$BUILD_DIR"
  --cache-path "$SWIFTPM_CACHE_DIR"
  --config-path "$SWIFTPM_CONFIG_DIR"
  --security-path "$SWIFTPM_SECURITY_DIR"
)

CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" swift build "${BUILD_ARGUMENTS[@]}"

BIN_DIR=$(CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" swift build \
  "${BUILD_ARGUMENTS[@]}" \
  --show-bin-path)

mkdir -p "$STAGED_APP_DIR/Contents/MacOS"
cp "$PROJECT_DIR/AppBundle/Info.plist" "$STAGED_APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/AppBundle/PkgInfo" "$STAGED_APP_DIR/Contents/PkgInfo"
cp "$BIN_DIR/PaperPDFPrototype" "$STAGED_APP_DIR/Contents/MacOS/PaperPDFPrototype"
mkdir -p "$STAGED_APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/AppBundle/Resources/AppIcon.icns" "$STAGED_APP_DIR/Contents/Resources/AppIcon.icns"
chmod +x "$STAGED_APP_DIR/Contents/MacOS/PaperPDFPrototype"
plutil -lint "$STAGED_APP_DIR/Contents/Info.plist"
xattr -cr "$STAGED_APP_DIR"
codesign --force --deep --sign - "$STAGED_APP_DIR"
codesign --verify --deep --strict "$STAGED_APP_DIR"

# Finder and file providers can attach metadata to an opened app. Sign a fresh
# bundle in the build directory, then replace the generated app atomically.
mkdir -p "${APP_DIR:h}"
if [[ -e "$APP_DIR" ]]; then
  mv "$APP_DIR" "$PREVIOUS_APP_DIR"
fi

if ! mv "$STAGED_APP_DIR" "$APP_DIR"; then
  if [[ -e "$PREVIOUS_APP_DIR" ]]; then
    mv "$PREVIOUS_APP_DIR" "$APP_DIR"
  fi
  exit 1
fi

if ! codesign --verify --deep --strict "$APP_DIR"; then
  mv "$APP_DIR" "$STAGING_ROOT/failed.app"
  if [[ -e "$PREVIOUS_APP_DIR" ]]; then
    mv "$PREVIOUS_APP_DIR" "$APP_DIR"
  fi
  exit 1
fi

print "作成しました: $APP_DIR"
