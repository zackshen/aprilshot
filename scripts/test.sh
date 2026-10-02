#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Swift/AppKit tests require macOS and Xcode Command Line Tools." >&2
  exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$ROOT/.build/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" "$ROOT/Tests/CoreTests.swift" \
  -o "$ROOT/.build/AprilShotTests"
"$ROOT/.build/AprilShotTests"
