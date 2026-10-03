#!/bin/zsh

set -euo pipefail

if (( $# > 1 )); then
  print -u2 "使い方: $0 [vX.Y.Z]"
  exit 64
fi

PROJECT_DIR=${0:A:h:h}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_DIR/AppBundle/Info.plist")
VERSION_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if [[ ! "$VERSION" =~ "$VERSION_PATTERN" ]]; then
  print -u2 "CFBundleShortVersionStringはX.Y.Z形式にしてください: $VERSION"
  exit 64
fi

RELEASE_TAG=${1:-"v$VERSION"}
if [[ "$RELEASE_TAG" != "v$VERSION" ]]; then
  print -u2 "タグとアプリのバージョンが一致しません: $RELEASE_TAG / $VERSION"
  exit 64
fi
if [[ ! -s "$PROJECT_DIR/releases/$RELEASE_TAG.md" ]]; then
  print -u2 "リリースノートがありません: releases/$RELEASE_TAG.md"
  exit 64
fi
if [[ "$(uname -m)" != arm64 ]]; then
  print -u2 "初版の配布用ビルドにはApple SiliconのMacを使用してください"
  exit 1
fi

ARCHIVE_NAME="PaperPDFPrototype-$VERSION-macos-arm64.zip"
OUTPUT_DIR="$PROJECT_DIR/dist/$RELEASE_TAG"
STAGING_PARENT=${PAPERPDF_STAGING_DIR:-${TMPDIR:-/private/tmp}}
mkdir -p "$STAGING_PARENT"
STAGING_ROOT=$(mktemp -d "$STAGING_PARENT/paperpdf-release.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGED_APP_DIR="$STAGING_ROOT/PaperPDFPrototype.app"

# A release build gets its own bundle; leave the development app in place.
PAPERPDF_APP_DIR="$STAGED_APP_DIR" "$PROJECT_DIR/Scripts/build-app.sh" release

ditto -c -k --sequesterRsrc --keepParent \
  "$STAGED_APP_DIR" "$STAGING_ROOT/$ARCHIVE_NAME"

# Check the actual distributable after extraction, not just the build output.
ditto -x -k "$STAGING_ROOT/$ARCHIVE_NAME" "$STAGING_ROOT/extracted"
EXTRACTED_APP_DIR="$STAGING_ROOT/extracted/PaperPDFPrototype.app"
plutil -lint "$EXTRACTED_APP_DIR/Contents/Info.plist"
codesign --verify --deep --strict "$EXTRACTED_APP_DIR"
EXTRACTED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$EXTRACTED_APP_DIR/Contents/Info.plist")
[[ "$EXTRACTED_VERSION" == "$VERSION" ]]
[[ -x "$EXTRACTED_APP_DIR/Contents/MacOS/PaperPDFPrototype" ]]
[[ "$(lipo -archs "$EXTRACTED_APP_DIR/Contents/MacOS/PaperPDFPrototype")" == arm64 ]]

(
  cd "$STAGING_ROOT"
  shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
  shasum -a 256 -c "$ARCHIVE_NAME.sha256"
)

mkdir -p "$OUTPUT_DIR"
mv -f "$STAGING_ROOT/$ARCHIVE_NAME" "$OUTPUT_DIR/$ARCHIVE_NAME"
mv -f "$STAGING_ROOT/$ARCHIVE_NAME.sha256" "$OUTPUT_DIR/$ARCHIVE_NAME.sha256"
print "配布用ZIP: $OUTPUT_DIR/$ARCHIVE_NAME"
print "SHA-256: $OUTPUT_DIR/$ARCHIVE_NAME.sha256"
print "Appleの公証は受けていません。初回の起動方法をリリースノートに記載しています。"
