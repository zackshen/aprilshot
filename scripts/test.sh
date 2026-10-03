#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Swift/AppKit tests require macOS and Xcode Command Line Tools." >&2
  exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$ROOT/.build/module-cache"
failures=()
# Keep independent suites running after a failure so CI still produces their
# synthetic rendering evidence. Never execute a stale binary after compile fails.
run_suite() {
  local name="$1" output="$2"
  shift 2
  echo "=== $name ==="
  if ! xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" \
      -module-cache-path "$ROOT/.build/module-cache" "$@" -o "$output"; then
    failures+=("$name (compile)")
    return
  fi
  if ! APRILSHOT_TEST_ARTIFACTS="$ROOT/.build/rendering-artifacts" "$output"; then
    failures+=("$name (run)")
  fi
}
run_suite Core "$ROOT/.build/AprilShotTests" \
  -framework AppKit "$ROOT"/Sources/Core/*.swift \
  "$ROOT/Sources/Annotation.swift" "$ROOT/Tests/CoreTests.swift"
run_suite Capture "$ROOT/.build/AprilShotCaptureTests" \
  -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" \
  "$ROOT/Sources/ScreenshotCapture.swift" "$ROOT/Sources/CanvasView.swift" \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" \
  "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/CaptureRenderingTests.swift"
run_suite Toolbar "$ROOT/.build/AprilShotToolbarTests" \
  -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" \
  "$ROOT/Sources/ScreenshotCapture.swift" "$ROOT/Sources/CanvasView.swift" \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" \
  "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/EditorToolbarTests.swift"
run_suite CopyPath "$ROOT/.build/AprilShotCopyPathTests" \
  -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" \
  "$ROOT/Sources/CanvasView.swift" "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" \
  "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/CopyPathTests.swift"
run_suite StatusMenu "$ROOT/.build/AprilShotStatusMenuTests" \
  -framework AppKit -framework Carbon \
  "$ROOT/Sources/AppPreferences.swift" "$ROOT/Sources/StatusMenu.swift" "$ROOT/Tests/StatusMenuTests.swift"
run_suite HotKeys "$ROOT/.build/AprilShotHotKeyTests" \
  -framework AppKit -framework Carbon \
  "$ROOT/Sources/AppPreferences.swift" "$ROOT/Sources/HotKeyManager.swift" "$ROOT/Tests/HotKeyPreferencesTests.swift"
run_suite Settings "$ROOT/.build/AprilShotSettingsTests" \
  -framework AppKit -framework Carbon \
  "$ROOT/Sources/AppPreferences.swift" "$ROOT/Sources/SettingsWindowController.swift" "$ROOT/Tests/SettingsWindowTests.swift"
run_suite Cleanup "$ROOT/.build/AprilShotCleanupTests" \
  -framework AppKit -framework ImageIO \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" "$ROOT/Tests/ExportCleanupTests.swift"
run_suite Rectangle "$ROOT/.build/AprilShotRectangleTests" \
  -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/Core/*.swift "$ROOT/Sources/Annotation.swift" "$ROOT/Sources/CanvasView.swift" \
  "$ROOT/Sources/ExportCleanup.swift" "$ROOT/Sources/ImagePathCopier.swift" \
  "$ROOT/Sources/EditorToolbar.swift" "$ROOT/Sources/EditorWindowController.swift" "$ROOT/Tests/RectangleTests.swift"
if [[ ${#failures[@]} -gt 0 ]]; then
  printf 'FAILED SUITE: %s\n' "${failures[@]}" >&2
  exit 1
fi
echo "All 9 test suites passed."
