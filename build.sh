#!/bin/zsh
# Builds Topside.app next to this script. Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"

swift build -c release 2>&1 | grep -vE "^\[|^Building|^Compiling|^Build complete" || true
BIN="$(swift build -c release --show-bin-path)/Topside"
[ -x "$BIN" ] || { echo "Build failed"; exit 1; }

APP="Topside.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Topside"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign with a real identity when there is one so macOS remembers granted permissions between builds.
ID="$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')"
codesign --force --sign "${ID:--}" "$APP" 2>/dev/null || codesign --force --sign - "$APP"
echo "Built $PWD/$APP"

if [ "$1" = "--run" ]; then
  pkill -x Topside 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
