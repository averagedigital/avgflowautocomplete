#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_ROOT="$ROOT_DIR/Shared/LlamaCpp"
VENDOR_ROOT="$LLAMA_ROOT/vendor/llama.cpp"
INCLUDE_DIR="$LLAMA_ROOT/include"
BUILD_ROOT="$LLAMA_ROOT/build"
ARCH_NAME="$(uname -m)"
BUILD_DIR="$BUILD_ROOT/$ARCH_NAME"
BIN_DIR="$BUILD_DIR/bin"
STAMP_FILE="$BUILD_DIR/.runtime-stamp"
LOCK_DIR="$BUILD_ROOT/.bootstrap-lock"
PINNED_COMMIT="43e1cbd6c1b407fcb1fb0196276265e774986035"
REMOTE_URL="https://github.com/ggml-org/llama.cpp.git"

mkdir -p "$BUILD_ROOT"
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  sleep 1
done
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

if [ ! -d "$VENDOR_ROOT/.git" ]; then
  mkdir -p "$(dirname "$VENDOR_ROOT")"
  git clone --depth 1 "$REMOTE_URL" "$VENDOR_ROOT" >/dev/null 2>&1
fi

CURRENT_COMMIT="$(git -C "$VENDOR_ROOT" rev-parse HEAD 2>/dev/null || echo '')"
if [ "$CURRENT_COMMIT" != "$PINNED_COMMIT" ]; then
  git -C "$VENDOR_ROOT" fetch --depth 1 origin "$PINNED_COMMIT" >/dev/null 2>&1
  git -C "$VENDOR_ROOT" checkout --detach "$PINNED_COMMIT" >/dev/null 2>&1
fi

mkdir -p "$INCLUDE_DIR"
rsync -a "$VENDOR_ROOT/include/llama.h" "$INCLUDE_DIR/"
rsync -a "$VENDOR_ROOT/ggml/include/"*.h "$INCLUDE_DIR/"

EXPECTED_STAMP="$PINNED_COMMIT|$ARCH_NAME"
if [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$EXPECTED_STAMP" ] && [ -f "$BIN_DIR/libllama.0.dylib" ]; then
  exit 0
fi

cmake -S "$VENDOR_ROOT" -B "$BUILD_DIR" -G Ninja \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_METAL=OFF \
  -DGGML_ACCELERATE=ON \
  -DLLAMA_BUILD_COMMON=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH_NAME" >/dev/null

cmake --build "$BUILD_DIR" --target llama -j 8 >/dev/null

echo "$EXPECTED_STAMP" > "$STAMP_FILE"
