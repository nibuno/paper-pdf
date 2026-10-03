#!/bin/zsh

set -euo pipefail

PROJECT_DIR=${0:A:h:h}
BUILD_DIR=${PAPERPDF_BUILD_DIR:-"$PROJECT_DIR/.build"}
mkdir -p "$BUILD_DIR"

# Keep SwiftPM and Clang caches inside the project, including in restricted
# local environments. Use the same paths as build-app.sh.
CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache" swift test \
  --disable-sandbox \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$BUILD_DIR" \
  --cache-path "$BUILD_DIR/swiftpm-cache" \
  --config-path "$BUILD_DIR/swiftpm-config" \
  --security-path "$BUILD_DIR/swiftpm-security"
