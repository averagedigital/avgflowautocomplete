#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ARCH_NAME="$(uname -m)"
BIN_DIR="$ROOT_DIR/Shared/LlamaCpp/build/$ARCH_NAME/bin"

if [ ! -d "$BIN_DIR" ]; then
  exit 0
fi

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
  exit 0
fi

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$FRAMEWORKS_DIR"
rsync -a "$BIN_DIR/" "$FRAMEWORKS_DIR/"

if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  while IFS= read -r -d '' dylib; do
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$dylib"
  done < <(find "$FRAMEWORKS_DIR" -maxdepth 1 -type f -name '*.dylib' -print0)
fi
