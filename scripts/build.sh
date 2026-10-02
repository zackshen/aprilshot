#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "AprilShot must be built on macOS 13+ with Xcode Command Line Tools." >&2
  exit 1
fi
xcrun --find swiftc >/dev/null
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported ARCH: $ARCH" >&2; exit 1 ;; esac
APP="$ROOT/build/AprilShot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" \
  -module-cache-path "$ROOT/.build/module-cache" \
  -framework AppKit -framework Carbon -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/AprilShot"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
# Local ad-hoc signing only. A developer may opt in to their own identity.
IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --sign - "$APP"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
echo "Built: $APP"
echo "Launch through: open \"$APP\" (not the binary inside Contents/MacOS)"
