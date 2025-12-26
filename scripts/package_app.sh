#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build/debug"
OUT_APP="$ROOT/build/Vaaka.app"
rm -rf "$OUT_APP"
mkdir -p "$OUT_APP/Contents/MacOS"
mkdir -p "$OUT_APP/Contents/Resources"
# Copy binary
cp "$BUILD_DIR/Vaaka" "$OUT_APP/Contents/MacOS/Vaaka"
chmod +x "$OUT_APP/Contents/MacOS/Vaaka"
# Copy Info.plist
cp "$ROOT/Resources/Info.plist" "$OUT_APP/Contents/Info.plist"
# Copy resources
cp -R "$ROOT/Resources/" "$OUT_APP/Contents/Resources/"
# Print result
echo "Packaged app at: $OUT_APP"