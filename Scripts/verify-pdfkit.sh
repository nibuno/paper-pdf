#!/bin/zsh

set -euo pipefail

PROJECT_DIR=${0:A:h:h}
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/paperpdf-verify.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

clang \
  -fobjc-arc \
  -isysroot "$SDK_PATH" \
  -mmacosx-version-min=14.0 \
  -framework Foundation \
  -framework AppKit \
  -framework PDFKit \
  "$PROJECT_DIR/Tools/pdfkit_smoke.m" \
  -o "$TEMP_DIR/pdfkit_smoke"

if (( $# == 0 )); then
  clang \
    -fobjc-arc \
    -isysroot "$SDK_PATH" \
    -mmacosx-version-min=14.0 \
    -framework Foundation \
    -framework CoreGraphics \
    -framework CoreText \
    "$PROJECT_DIR/Tools/generate_test_pdf.m" \
    -o "$TEMP_DIR/generate_test_pdf"
  "$TEMP_DIR/generate_test_pdf" "$TEMP_DIR/test-book.pdf"
  PDF_PATH="$TEMP_DIR/test-book.pdf"
elif (( $# == 1 )); then
  PDF_PATH=${1:A}
  if [[ ! -f "$PDF_PATH" || "${PDF_PATH:e:l}" != "pdf" ]]; then
    print -u2 "PDFファイルを指定してください: $PDF_PATH"
    exit 64
  fi
else
  print -u2 "使い方: $0 [検証するPDF]"
  exit 64
fi

print "検証対象: $PDF_PATH"
"$TEMP_DIR/pdfkit_smoke" "$PDF_PATH" "$TEMP_DIR/sidecar.json"
