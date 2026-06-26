#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-AICompleteMac.xcodeproj}"
SCHEME="${SCHEME:-AICompleteMacPerf}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-.derived/perf}"
OUTPUT_DIR="${OUTPUT_DIR:-artifacts/perf}"
APP_NAME="${APP_NAME:-AICompleteMac.app}"

mkdir -p "$OUTPUT_DIR"

echo "== Environment =="
xcodebuild -version
sw_vers
uname -m
pmset -g batt | head -n 2 || true

echo "== Build (${SCHEME}/${CONFIGURATION}) =="
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$(find "$DERIVED_DATA" -type d -name "$APP_NAME" | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "Unable to locate built app at $DERIVED_DATA"
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
LAUNCH_TRACE="$OUTPUT_DIR/launch_${STAMP}.trace"
CPU_TRACE="$OUTPUT_DIR/cpu_${STAMP}.trace"
SWIFT_CONC_TRACE="$OUTPUT_DIR/swift_concurrency_${STAMP}.trace"

echo "== Record App Launch trace =="
xcrun xctrace record \
  --template "App Launch" \
  --output "$LAUNCH_TRACE" \
  --time-limit 20s \
  --launch -- "$APP_PATH"

echo "== Record Time Profiler trace =="
xcrun xctrace record \
  --template "Time Profiler" \
  --output "$CPU_TRACE" \
  --time-limit 30s \
  --launch -- "$APP_PATH"

echo "== Record Swift Concurrency trace =="
xcrun xctrace record \
  --template "Swift Concurrency" \
  --output "$SWIFT_CONC_TRACE" \
  --time-limit 30s \
  --launch -- "$APP_PATH"

echo "== Export trace TOCs =="
xcrun xctrace export --input "$LAUNCH_TRACE" --toc --output "$OUTPUT_DIR/launch_${STAMP}_toc.xml"
xcrun xctrace export --input "$CPU_TRACE" --toc --output "$OUTPUT_DIR/cpu_${STAMP}_toc.xml"
xcrun xctrace export --input "$SWIFT_CONC_TRACE" --toc --output "$OUTPUT_DIR/swift_concurrency_${STAMP}_toc.xml"

echo "Traces written to $OUTPUT_DIR"
