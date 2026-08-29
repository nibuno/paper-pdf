#!/bin/zsh

set -euo pipefail

PROJECT_DIR=${0:A:h:h}

if (( $# > 1 )); then
  print -u2 "使い方: $0 [最初に開くPDF]"
  exit 64
fi

"$PROJECT_DIR/Scripts/build-app.sh"
open -n "$PROJECT_DIR/PaperPDFPrototype.app" --args "$@"
