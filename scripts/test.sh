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
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" \
  "$ROOT/Sources/ScreenshotCapture.swift" "$ROOT/Sources/CanvasView.swift" \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/CaptureRenderingTests.swift" \
  -o "$ROOT/.build/AprilShotCaptureTests"
APRILSHOT_TEST_ARTIFACTS="$ROOT/.build/rendering-artifacts" "$ROOT/.build/AprilShotCaptureTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" \
  "$ROOT/Sources/ScreenshotCapture.swift" "$ROOT/Sources/CanvasView.swift" \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/EditorToolbarTests.swift" \
  -o "$ROOT/.build/AprilShotToolbarTests"
APRILSHOT_TEST_ARTIFACTS="$ROOT/.build/rendering-artifacts" "$ROOT/.build/AprilShotToolbarTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" \
  "$ROOT/Sources/CanvasView.swift" "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" \
  "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/CopyPathTests.swift" \
  -o "$ROOT/.build/AprilShotCopyPathTests"
"$ROOT/.build/AprilShotCopyPathTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework Carbon \
  "$ROOT/Sources/AppPreferences.swift" "$ROOT/Sources/StatusMenu.swift" "$ROOT/Tests/StatusMenuTests.swift" \
  -o "$ROOT/.build/AprilShotStatusMenuTests"
APRILSHOT_TEST_ARTIFACTS="$ROOT/.build/rendering-artifacts" "$ROOT/.build/AprilShotStatusMenuTests"

xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework Carbon \
  "$ROOT/Sources/AppPreferences.swift" "$ROOT/Sources/HotKeyManager.swift" "$ROOT/Tests/HotKeyPreferencesTests.swift" \
  -o "$ROOT/.build/AprilShotHotKeyTests"
"$ROOT/.build/AprilShotHotKeyTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework Carbon \
  "$ROOT/Sources/AppPreferences.swift" "$ROOT/Sources/SettingsWindowController.swift" "$ROOT/Tests/SettingsWindowTests.swift" \
  -o "$ROOT/.build/AprilShotSettingsTests"
APRILSHOT_TEST_ARTIFACTS="$ROOT/.build/rendering-artifacts" "$ROOT/.build/AprilShotSettingsTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework ImageIO \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" "$ROOT/Tests/ExportCleanupTests.swift" \
  -o "$ROOT/.build/AprilShotCleanupTests"
"$ROOT/.build/AprilShotCleanupTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
  -module-cache-path "$ROOT/.build/module-cache" -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" "$ROOT/Sources/CanvasView.swift" \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" \
  "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/RectangleTests.swift" \
  -o "$ROOT/.build/AprilShotRectangleTests"
APRILSHOT_TEST_ARTIFACTS="$ROOT/.build/rendering-artifacts" "$ROOT/.build/AprilShotRectangleTests"
