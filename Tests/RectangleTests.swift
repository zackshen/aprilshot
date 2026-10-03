import AppKit

/// Rectangular outline annotations through actual AppKit mouse/keyboard events.
/// Fixtures are generated here and contain no captured desktop or user content.
@main
struct RectangleTests {
    static var checks = 0
    static var failures = 0
    struct TestFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static let size = CGSize(width: 960, height: 600)
    static let artifacts = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APRILSHOT_TEST_ARTIFACTS"] ?? ".build/rendering-artifacts", isDirectory: true)

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do {
            if try !condition() { failures += 1; print("FAIL: \(message)") }
        } catch { failures += 1; print("FAIL: \(message): \(error)") }
    }
    static func fixture() -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return context.makeImage()!
    }
    static func mouse(_ canvas: CanvasView, _ point: CGPoint, _ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.geometry.viewPoint(from: point), to: nil),
                          modifierFlags: [], timestamp: 0, windowNumber: canvas.window!.windowNumber,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    static func key(_ canvas: CanvasView, _ value: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: canvas.window!.windowNumber, context: nil, characters: value,
                        charactersIgnoringModifiers: value, isARepeat: false, keyCode: code)!
    }
    static func start(_ canvas: CanvasView, _ from: CGPoint, _ to: CGPoint) {
        canvas.mouseDown(with: mouse(canvas, from, .leftMouseDown))
        canvas.mouseDragged(with: mouse(canvas, to, .leftMouseDragged))
    }
    static func draw(_ canvas: CanvasView, _ from: CGPoint, _ to: CGPoint) {
        start(canvas, from, to)
        canvas.mouseUp(with: mouse(canvas, to, .leftMouseUp))
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    static func control<T: NSView>(_ id: String, _ editor: EditorWindowController, as: T.Type) -> T {
        descendants(editor.window!.contentView!).first { $0.identifier?.rawValue == id } as! T
    }
    static func lastRectangle(_ canvas: CanvasView) -> RectangleAnnotation? {
        if case .rectangle(let rectangle)? = canvas.history.items.last { return rectangle }
        return nil
    }
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001 &&
            abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
    }
    static func pixel(_ bitmap: NSBitmapImageRep, _ point: CGPoint) -> NSColor {
        bitmap.colorAt(x: Int(point.x), y: Int(size.height - point.y))!
    }
    static func isRed(_ color: NSColor) -> Bool {
        color.redComponent > 0.9 && color.greenComponent < 0.1 && color.blueComponent < 0.1
    }
    static func isWhite(_ color: NSColor) -> Bool {
        color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9
    }
    static func checkPNG(_ png: Data, name: String) {
        guard let bitmap = NSBitmapImageRep(data: png) else { check(false, "\(name): valid PNG"); return }
        check(bitmap.pixelsWide == Int(size.width) && bitmap.pixelsHigh == Int(size.height), "\(name): image is not cropped or resized")
        for point in [CGPoint(x: 100, y: 220), CGPoint(x: 420, y: 220),
                      CGPoint(x: 240, y: 100), CGPoint(x: 240, y: 360),
                      CGPoint(x: 100, y: 100), CGPoint(x: 420, y: 360)] {
            let sample = pixel(bitmap, point)
            check(isRed(sample), "\(name): outline edge/corner at \(point); got encoded \(sample)")
        }
        check(isWhite(pixel(bitmap, CGPoint(x: 240, y: 220))), "\(name): rectangle interior preserves source content")
        check(isWhite(pixel(bitmap, CGPoint(x: 109, y: 220))), "\(name): line width uses original pixels")
        check(pixel(bitmap, CGPoint(x: 20, y: 20)).blueComponent > 0.9 &&
              pixel(bitmap, CGPoint(x: 20, y: 20)).redComponent < 0.1, "\(name): source orientation is preserved")
    }
    static func checkPreview(_ canvas: CanvasView, name: String) throws {
        canvas.needsDisplay = true
        let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: artifacts.appendingPathComponent(name + ".png"))
        let point = canvas.geometry.viewPoint(from: CGPoint(x: 100, y: 220))
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / canvas.bounds.width)
        let y = Int((canvas.bounds.height - point.y) * CGFloat(bitmap.pixelsHigh) / canvas.bounds.height)
        let sample = bitmap.colorAt(x: x, y: y)!
        check(isRed(sample), "\(name): real CanvasView outline at bitmap (\(x), \(y)); got encoded \(sample)")
    }
    static func copiedPNG(_ pasteboard: NSPasteboard, editor: EditorWindowController) throws -> (String, Data) {
        let button = control("editor.export.copy", editor, as: NSButton.self)
        let details: String
        if let view = editor.window?.attachedSheet?.contentView {
            details = descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " | ")
        } else { details = "no error sheet" }
        guard button.title.contains("路径已复制"),
              let path = pasteboard.string(forType: .string), path.hasPrefix("/"), path.hasSuffix(".png") else {
            throw TestFailure(message: "Rectangle copy did not publish a PNG path: button=\(button.title); \(details)")
        }
        return (path, try Data(contentsOf: URL(fileURLWithPath: path)))
    }
    static func main() {
        do { try runTests() }
        catch { check(false, "stopped dependent rectangle checks: \(error.localizedDescription)") }
        print("\(failures == 0 ? "PASS" : "FAIL"): \(checks) rectangle input, history, export and lifecycle assertions, \(failures) failures")
        if failures != 0 { exit(1) }
    }
    static func runTests() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        // Normal storage fixtures use the checkout; /var temp aliases must not
        // make success-path tests depend on production symlink restrictions.
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent("AprilShot Rectangle \(UUID().uuidString)", isDirectory: true)
        print("Rectangle fixture: \(root.path)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let copier = ImagePathCopier(store: CopiedImageStore(directory: root.appendingPathComponent("Exports", isDirectory: true)), writePath: { ImagePathCopier.write($0, to: pasteboard) })
        let source = fixture()
        let sourcePNG = try AnnotationRenderer.png(image: source, annotations: [])
        let editor = EditorWindowController(image: source, imagePathCopier: copier)
        let window = editor.window!
        let canvas = editor.canvas
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        let rectangle = control("editor.tools.rectangle", editor, as: NSButton.self)
        let brush = control("editor.tools.brush", editor, as: NSButton.self)
        let text = control("editor.tools.text", editor, as: NSButton.self)
        let undo = control("editor.history.undo", editor, as: NSButton.self)
        let redo = control("editor.history.redo", editor, as: NSButton.self)
        let copy = control("editor.export.copy", editor, as: NSButton.self)
        let width = control("editor.brush.width", editor, as: NSSlider.self)
        let color = control("editor.color", editor, as: NSColorWell.self)
        check(canvas.tool == .rectangle && rectangle.state == .on && brush.state == .off && text.state == .off,
              "new editor defaults to rectangle with exactly one selected tool")
        width.doubleValue = 12
        width.sendAction(width.action, to: width.target)
        color.color = .red
        color.sendAction(color.action, to: color.target)
        check(canvas.brushWidth == 12 && canvas.color == .red, "rectangle uses the shared toolbar line style")
        let from = CGPoint(x: 100, y: 100)
        let to = CGPoint(x: 420, y: 360)
        let initial = canvas.history.current.id
        for (index, pair) in [(from, to), (to, from), (CGPoint(x: 100, y: 360), CGPoint(x: 420, y: 100)),
                              (CGPoint(x: 420, y: 100), CGPoint(x: 100, y: 360))].enumerated() {
            start(canvas, pair.0, pair.1)
            check(canvas.hasPendingContent && canvas.history.items.isEmpty && undo.isEnabled && !redo.isEnabled,
                  "direction \(index): live rectangle is pending and enables undo")
            try checkPreview(canvas, name: "rectangle-preview-direction-\(index)")
            canvas.mouseUp(with: mouse(canvas, pair.1, .leftMouseUp))
            check(canvas.history.items.count == 1 && !canvas.hasPendingContent, "direction \(index): one release creates one annotation")
            check(lastRectangle(canvas).map { near($0.rect, CGRect(x: 100, y: 100, width: 320, height: 260)) } == true,
                  "direction \(index): normalized image-pixel rectangle")
            check(lastRectangle(canvas)?.width == 12 && lastRectangle(canvas)?.color == .red,
                  "direction \(index): captured style is retained")
            let png = try canvas.exportPNG()
            if index == 0 { try png.write(to: artifacts.appendingPathComponent("rectangle-export.png")) }
            checkPNG(png, name: "direction \(index)")
            let committed = canvas.history.current.id
            canvas.mouseUp(with: mouse(canvas, pair.1, .leftMouseUp))
            canvas.commitPendingAnnotations()
            check(canvas.history.current.id == committed, "direction \(index): repeated completion does not duplicate history")
            undo.performClick(nil)
            check(canvas.history.current.id == initial && redo.isEnabled, "direction \(index): one undo restores original state identity")
            check(try canvas.exportPNG() == sourcePNG, "direction \(index): undo restores exact source PNG")
            redo.performClick(nil)
            check(canvas.history.current.id == committed && !redo.isEnabled, "direction \(index): one redo restores rectangle identity")
            checkPNG(try canvas.exportPNG(), name: "redone \(index)")
            undo.performClick(nil)
        }

        // Empty gestures must not dirty the image or erase an existing redo branch.
        for end in [from, CGPoint(x: 100, y: 360), CGPoint(x: 420, y: 100)] {
            draw(canvas, from, end)
            check(canvas.history.current.id == initial && !canvas.hasPendingContent && canvas.history.canRedo,
                  "click and single-axis drags create no history and preserve redo")
        }
        draw(canvas, CGPoint(x: -20, y: 100), to)
        check(canvas.history.current.id == initial, "a gesture beginning outside the image is ignored")
        canvas.mouseDown(with: mouse(canvas, from, .leftMouseDown))
        canvas.mouseUp(with: mouse(canvas, to, .leftMouseUp))
        check(lastRectangle(canvas).map { near($0.rect, CGRect(x: 100, y: 100, width: 320, height: 260)) } == true,
              "mouse release captures the final endpoint even without an intervening drag event")
        canvas.undoAnnotation()

        start(canvas, from, to)
        canvas.cancelOperation(nil)
        canvas.mouseUp(with: mouse(canvas, to, .leftMouseUp))
        check(canvas.history.current.id == initial && !canvas.hasPendingContent && canvas.history.canRedo && redo.isEnabled,
              "Escape cancels a pending rectangle without adding history or losing redo")
        start(canvas, from, to)
        let beforeIgnoredRedo = canvas.history.current.id
        canvas.redoAnnotation()
        check(canvas.hasPendingContent && canvas.history.current.id == beforeIgnoredRedo,
              "redo is a no-op while a different rectangle is pending")
        undo.performClick(nil)
        check(canvas.history.current.id == initial && !canvas.hasPendingContent && canvas.history.canRedo,
              "undo during a drag removes only the pending rectangle")
        redo.performClick(nil)
        check(canvas.history.items.count == 1, "redo restores the interrupted rectangle as one step")
        canvas.undoAnnotation()
        draw(canvas, CGPoint(x: 300, y: 250), CGPoint(x: -100, y: -100))
        check(lastRectangle(canvas).map { near($0.rect, CGRect(x: 0, y: 0, width: 300, height: 250)) } == true,
              "reverse dragging beyond image clamps both lower edges")
        canvas.undoAnnotation()
        draw(canvas, CGPoint(x: 300, y: 250), CGPoint(x: 2000, y: 2000))
        check(lastRectangle(canvas).map { near($0.rect, CGRect(x: 300, y: 250, width: 660, height: 350)) } == true,
              "dragging beyond image clamps both upper edges")
        let edgePNG = NSBitmapImageRep(data: try canvas.exportPNG())!
        check(isRed(edgePNG.colorAt(x: 958, y: 120)!) && isRed(edgePNG.colorAt(x: 600, y: 1)!),
              "clipped upper-edge outlines remain visible in exported PNG")
        canvas.undoAnnotation()
        start(canvas, from, to)
        canvas.mouseDragged(with: mouse(canvas, CGPoint(x: 2000, y: 2000), .leftMouseDragged))
        canvas.mouseDragged(with: mouse(canvas, to, .leftMouseDragged))
        canvas.mouseUp(with: mouse(canvas, to, .leftMouseUp))
        checkPNG(try canvas.exportPNG(), name: "leave and return")
        canvas.undoAnnotation()

        // Style is captured at mouse-down and tool switches commit only once.
        start(canvas, from, to)
        canvas.color = .blue
        canvas.brushWidth = 32
        brush.performClick(nil)
        check(canvas.history.items.count == 1 && lastRectangle(canvas)?.color == .red && lastRectangle(canvas)?.width == 12,
              "switching tools commits the rectangle with its original style")
        brush.performClick(nil)
        check(canvas.history.items.count == 1 && !canvas.hasPendingContent, "repeated tool selection is idempotent")
        canvas.mouseDown(with: mouse(canvas, CGPoint(x: 750, y: 250), .leftMouseDown))
        rectangle.performClick(nil)
        check(canvas.history.items.count == 2, "switching to rectangle commits an unfinished brush dot")
        if case .brush(let stroke)? = canvas.history.items.last {
            check(stroke.width == 32 && stroke.color == .blue, "brush keeps its own toolbar style")
        } else { check(false, "brush regression annotation exists") }
        text.performClick(nil)
        canvas.mouseDown(with: mouse(canvas, CGPoint(x: 500, y: 480), .leftMouseDown))
        if let field = canvas.subviews.compactMap({ $0 as? NSTextView }).first {
            field.string = "矩形标注仍保留文字输入"
            field.didChangeText()
            rectangle.performClick(nil)
            check(!canvas.isEditingText && canvas.history.items.count == 3, "switching from text to rectangle commits text exactly once")
        } else { check(false, "text tool still opens inline editor") }
        canvas.keyDown(with: key(canvas, "b", code: 11))
        canvas.keyDown(with: key(canvas, "r", code: 15))
        check(canvas.tool == .rectangle && rectangle.state == .on && brush.state == .off && text.state == .off,
              "R selects rectangle and updates native tool selection")
        while canvas.history.canUndo { canvas.undoAnnotation() }
        canvas.color = .red
        canvas.brushWidth = 12

        // Copy path must export a live rectangle, keep the file and track the exact state.
        let next = EditorWindowController(image: source, imagePathCopier: copier)
        check(next.canvas.tool == .rectangle && next.canvas.history.items.isEmpty, "every fresh screenshot resets to rectangle and empty history")
        next.window?.orderOut(nil)
        copy.performClick(nil)
        _ = try copiedPNG(pasteboard, editor: editor)
        check(!window.isDocumentEdited, "empty capture copy sets the export baseline")
        start(canvas, from, to)
        check(window.isDocumentEdited, "a live rectangle marks the previously exported capture changed")
        canvas.cancelOperation(nil)
        check(!window.isDocumentEdited, "cancelling restores the exported-state indicator")
        start(canvas, from, to)
        copy.performClick(nil)
        let (copiedPath, copiedData) = try copiedPNG(pasteboard, editor: editor)
        checkPNG(copiedData, name: "copy live rectangle")
        check(!canvas.hasPendingContent && canvas.history.items.count == 1 && !window.isDocumentEdited,
              "copy commits the live rectangle once and marks that state exported")
        check(try canvas.exportPNG() == copiedData, "copy-path file and save's exportPNG pipeline use identical rendering")
        canvas.mouseUp(with: mouse(canvas, to, .leftMouseUp))
        check(canvas.history.items.count == 1 && !window.isDocumentEdited, "late mouse-up after copy cannot duplicate or dirty the rectangle")
        canvas.undoAnnotation()
        check(window.isDocumentEdited, "undo after copy changes the exported-state indicator")
        canvas.redoAnnotation()
        check(!window.isDocumentEdited && editor.windowShouldClose(window), "redo restores the copied state and allows safe close")

        // Close commits pending input before prompting, and Continue Editing keeps it.
        start(canvas, CGPoint(x: 550, y: 100), CGPoint(x: 800, y: 350))
        var sawClosePrompt = false
        let closeResponse = Timer(timeInterval: 0.02, repeats: false) { _ in
            sawClosePrompt = NSApp.modalWindow != nil
            NSApp.stopModal(withCode: .alertFirstButtonReturn)
        }
        RunLoop.current.add(closeResponse, forMode: .modalPanel)
        check(!editor.windowShouldClose(window), "Continue Editing cancels closing an unsaved rectangle")
        closeResponse.invalidate()
        check(sawClosePrompt && canvas.history.items.count == 2 && !canvas.hasPendingContent && window.isDocumentEdited,
              "close prompt keeps the committed rectangle and dirty state")
        copy.performClick(nil)
        _ = try copiedPNG(pasteboard, editor: editor)
        check(editor.windowShouldClose(window), "copied version can close after continuing editing")
        window.close()
        check(try Data(contentsOf: URL(fileURLWithPath: copiedPath)) == copiedData, "closing the editor preserves its previously copied rectangle PNG")

    }
}
