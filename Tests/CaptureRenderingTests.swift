import AppKit
import ImageIO

/// Exercises the capture-file lifetime and the actual AppKit editor, not just
/// AnnotationRenderer with an already-decoded CGContext-generated CGImage.
@main
struct CaptureRenderingTests {
    static var checks = 0
    static var failures = 0
    static let width = 1712
    static let height = 662
    static let artifacts = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APRILSHOT_TEST_ARTIFACTS"] ?? ".build/rendering-artifacts", isDirectory: true)

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func fixturePNG() throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (x, y, color) in [(0, height / 2, NSColor.red), (width / 2, height / 2, NSColor.green),
                              (0, 0, NSColor.blue), (width / 2, 0, NSColor.yellow)] {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x, y: y, width: width / 2, height: height / 2))
        }
        return try AnnotationRenderer.png(image: context.makeImage()!, annotations: [
            .text(TextAnnotation(text: "AprilShot · SYNTHETIC CAPTURE · 测试截图", rect: CGRect(x: 60, y: 295, width: 1550, height: 70), color: .black, fontSize: 48))
        ])
    }

    static func loadThenDelete(_ png: Data) throws -> CGImage? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AprilShot-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("capture.png")
        try png.write(to: file)
        // Match production: load during the callback, remove the capture directory
        // before the event loop can ask CanvasView to draw. Do not inspect pixels here.
        let image = autoreleasepool { ScreenshotCapture.loadImage(at: file) }
        try FileManager.default.removeItem(at: directory)
        check(!FileManager.default.fileExists(atPath: file.path), "temporary capture is removed before first rendering")
        return image
    }

    static func bitmap(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: artifacts.appendingPathComponent(name))
        return bitmap
    }

    static func nearColor(_ actual: NSColor, _ expected: NSColor) -> Bool {
        // These fixtures and rendered bitmaps encode 8-bit RGB primaries. Compare
        // their sample values directly; re-converting an NSBitmapImageRep's
        // calibrated color through the runner's display profile distorts blue.
        return abs(actual.redComponent - expected.redComponent) < 0.15 &&
            abs(actual.greenComponent - expected.greenComponent) < 0.15 &&
            abs(actual.blueComponent - expected.blueComponent) < 0.15 && actual.alphaComponent > 0.95
    }

    static let samples: [(CGFloat, CGFloat, NSColor)] = [
        (0.25, 0.75, .red), (0.75, 0.75, .green),
        (0.25, 0.25, .blue), (0.75, 0.25, .yellow)
    ]

    static func checkCanvas(_ canvas: CanvasView, name: String) throws {
        let rendered = try bitmap(canvas, name: name)
        check(canvas.geometry.scale > 0, "\(name): nonzero canvas geometry")
        for (x, y, color) in samples {
            let point = canvas.geometry.viewPoint(from: CGPoint(x: x * CGFloat(width), y: y * CGFloat(height)))
            let px = Int(point.x / canvas.bounds.width * CGFloat(rendered.pixelsWide))
            let py = Int((canvas.bounds.height - point.y) / canvas.bounds.height * CGFloat(rendered.pixelsHigh))
            let actual = rendered.colorAt(x: px, y: py)!
            check(nearColor(actual, color), "\(name): source quadrant (\(x), \(y)) visible; got \(actual)")
        }
    }

    static func checkExport(_ data: Data, name: String) throws {
        try data.write(to: artifacts.appendingPathComponent(name))
        let rendered = NSBitmapImageRep(data: data)!
        check(rendered.pixelsWide == width && rendered.pixelsHigh == height, "\(name): exact source pixel dimensions")
        for (x, y, color) in samples {
            check(nearColor(rendered.colorAt(x: Int(x * CGFloat(width)), y: Int((1 - y) * CGFloat(height)))!, color), "\(name): source colors and orientation survive cleanup")
        }
    }

    static func mouse(_ canvas: CanvasView, at point: CGPoint, type: NSEvent.EventType) -> NSEvent {
        let location = canvas.convert(canvas.geometry.viewPoint(from: point), to: nil)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                 windowNumber: canvas.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let png = try fixturePNG()
        try png.write(to: artifacts.appendingPathComponent("synthetic-source.png"))
        // Repeat full file lifecycle to catch stale image/cache or window reuse.
        for attempt in 1...2 {
            guard let image = try loadThenDelete(png) else {
                check(false, "capture image loads")
                continue
            }
            check(image.width == width && image.height == height, "loaded screenshot dimensions are valid")
            // Defer first display past the cleanup callback/run-loop boundary.
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let editor = EditorWindowController(image: image)
            let window = editor.window!
            window.contentView!.layoutSubtreeIfNeeded()
            // The first image-dependent operation must be AppKit's real drawing path.
            try checkCanvas(editor.canvas, name: "canvas-\(attempt)-initial.png")
            _ = try bitmap(window.contentView!, name: "editor-\(attempt).png")
            try checkExport(editor.canvas.exportPNG(), name: "export-\(attempt).png")
            window.setContentSize(NSSize(width: 860, height: 520))
            window.contentView!.layoutSubtreeIfNeeded()
            try checkCanvas(editor.canvas, name: "canvas-\(attempt)-resized.png")
            // A real canvas input path draws an annotation over the loaded screenshot.
            editor.canvas.color = .magenta
            editor.canvas.brushWidth = 24
            let dot = CGPoint(x: 100, y: 100)
            editor.canvas.mouseDown(with: mouse(editor.canvas, at: dot, type: .leftMouseDown))
            editor.canvas.mouseUp(with: mouse(editor.canvas, at: dot, type: .leftMouseUp))
            let annotatedData = try editor.canvas.exportPNG()
            try checkExport(annotatedData, name: "annotated-\(attempt).png")
            let annotated = NSBitmapImageRep(data: annotatedData)!
            check(nearColor(annotated.colorAt(x: 100, y: height - 100)!, .magenta), "canvas brush overlays screenshot")
            editor.canvas.undoAnnotation()
            let undoneData = try editor.canvas.exportPNG()
            try checkExport(undoneData, name: "undo-\(attempt).png")
            let undone = NSBitmapImageRep(data: undoneData)!
            check(nearColor(undone.colorAt(x: 100, y: height - 100)!, .blue), "canvas undo removes annotation and restores source pixel")
            editor.canvas.redoAnnotation()
            let redone = NSBitmapImageRep(data: try editor.canvas.exportPNG())!
            check(nearColor(redone.colorAt(x: 100, y: height - 100)!, .magenta), "canvas redo restores annotation")
            window.orderOut(nil)
        }
        // Export-first uses a fresh load, so preview cannot warm its decode cache.
        if let exportFirst = try loadThenDelete(png) {
            try checkExport(AnnotationRenderer.png(image: exportFirst, annotations: []), name: "export-first.png")
        } else { check(false, "export-first source loads") }
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent("AprilShot-invalid-\(UUID().uuidString).png")
        try Data("not a PNG".utf8).write(to: invalid)
        check(ScreenshotCapture.loadImage(at: invalid) == nil, "invalid capture cannot open a blank editor")
        try Data(png.prefix(80)).write(to: invalid)
        check(ScreenshotCapture.loadImage(at: invalid) == nil, "truncated capture is rejected")
        try FileManager.default.removeItem(at: invalid)
        check(ScreenshotCapture.loadImage(at: invalid) == nil, "missing capture cannot open a blank editor")
        print("\(failures == 0 ? "PASS" : "FAIL"): \(checks) capture and AppKit rendering assertions, \(failures) failures")
        if failures != 0 { exit(1) }
    }
}
