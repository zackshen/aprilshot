import AppKit

/// Regression coverage and reviewable screenshots of the real editor window.
/// Every pixel originates in the synthetic fixture below, never a user capture.
@main
struct EditorToolbarTests {
    static var checks = 0
    static var failures = 0
    static let sourceSize = CGSize(width: 1440, height: 900)
    static let artifacts = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APRILSHOT_TEST_ARTIFACTS"] ?? ".build/rendering-artifacts", isDirectory: true)

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    static func find<T: NSView>(_ id: String, in view: NSView, as type: T.Type) -> T? {
        let matches = descendants(view).filter { $0.identifier?.rawValue == id }
        check(matches.count == 1, "\(id): has one stable identifier")
        let result = matches.first as? T
        check(result != nil, "\(id): uses \(type)")
        return result
    }

    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static func near(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 1 }

    static func sameColor(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let a = lhs.usingColorSpace(.sRGB), let b = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.08 &&
            abs(a.greenComponent - b.greenComponent) < 0.08 &&
            abs(a.blueComponent - b.blueComponent) < 0.08 && abs(a.alphaComponent - b.alphaComponent) < 0.08
    }

    static func samePixel(_ actual: NSColor, _ expected: NSColor) -> Bool {
        // Compare the encoded sRGB sample values, as in CaptureRenderingTests.
        // colorAt's NSColor wrapper must not color-convert the PNG bytes again.
        return abs(actual.redComponent - expected.redComponent) < 0.08 &&
            abs(actual.greenComponent - expected.greenComponent) < 0.08 &&
            abs(actual.blueComponent - expected.blueComponent) < 0.08 &&
            abs(actual.alphaComponent - expected.alphaComponent) < 0.08
    }

    static func fixture() -> CGImage {
        let context = CGContext(data: nil, width: Int(sourceSize.width), height: Int(sourceSize.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        func box(_ rect: CGRect, _ color: NSColor, radius: CGFloat = 0) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 20,
                   color: NSColor = rgb(0.19, 0.22, 0.24), weight: NSFont.Weight = .regular) {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
            ])
        }
        let muted = rgb(0.46, 0.50, 0.52)
        let green = rgb(0.20, 0.43, 0.35)
        box(CGRect(origin: .zero, size: sourceSize), rgb(0.96, 0.96, 0.94))
        box(CGRect(x: 0, y: 0, width: 242, height: 900), rgb(0.91, 0.93, 0.90))
        box(CGRect(x: 0, y: 820, width: 1440, height: 80), .white)
        box(CGRect(x: 28, y: 844, width: 28, height: 28), green, radius: 8)
        label("Fieldnotes", x: 68, y: 843, size: 26, weight: .semibold)
        label("A public, synthetic workspace", x: 1002, y: 849, size: 16, color: muted)
        label("WORKSPACE", x: 28, y: 756, size: 13, color: muted, weight: .semibold)
        box(CGRect(x: 16, y: 678, width: 210, height: 50), rgb(0.82, 0.87, 0.81), radius: 12)
        label("Overview", x: 42, y: 692, size: 20, color: green, weight: .semibold)
        label("Projects", x: 42, y: 628, color: muted)
        label("Notes", x: 42, y: 565, color: muted)
        label("Archive", x: 42, y: 502, color: muted)
        label("Made for the small things.", x: 27, y: 43, size: 14, color: muted)
        label("YOUR SPACE", x: 298, y: 751, size: 13, color: green, weight: .semibold)
        label("A little room for ideas.", x: 296, y: 684, size: 42, weight: .semibold)
        label("Keep the useful details. Make the next step clear.", x: 299, y: 644, size: 22, color: muted)
        box(CGRect(x: 298, y: 342, width: 1086, height: 254), .white, radius: 18)
        label("This week", x: 330, y: 536, size: 23, weight: .semibold)
        label("A few good things in progress", x: 330, y: 498, size: 18, color: muted)
        let titles = ["Explore", "Make", "Share"]
        let details = ["Collect the first ideas", "Bring one idea to life", "Give it a little context"]
        for index in 0..<3 {
            let x = CGFloat(330 + index * 348)
            box(CGRect(x: x, y: 410, width: 30, height: 30), rgb(0.88, 0.93, 0.86), radius: 15)
            label("\(index + 1)", x: x + 10, y: 416, size: 14, color: green, weight: .semibold)
            label(titles[index], x: x + 44, y: 418, size: 19, weight: .semibold)
            label(details[index], x: x + 44, y: 386, size: 16, color: muted)
        }
        box(CGRect(x: 298, y: 72, width: 524, height: 234), rgb(0.89, 0.92, 0.85), radius: 18)
        box(CGRect(x: 848, y: 72, width: 536, height: 234), rgb(0.93, 0.89, 0.82), radius: 18)
        label("Less noise, more focus.", x: 330, y: 242, size: 25, weight: .semibold)
        label("One clear next step is a good start.", x: 330, y: 201, size: 18, color: muted)
        label("Capture, annotate, share.", x: 880, y: 242, size: 25, weight: .semibold)
        label("A small note can make the difference.", x: 880, y: 201, size: 18, color: muted)
        label("SYNTHETIC DEMO · NO PERSONAL DATA", x: 300, y: 29, size: 12, color: muted)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    static func layout(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
    }

    @discardableResult
    static func render(_ content: NSView, name: String) throws -> NSBitmapImageRep {
        content.layoutSubtreeIfNeeded()
        content.needsDisplay = true
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: artifacts.appendingPathComponent("\(name).png"))
        check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(name): full editor content renders")
        if let image = bitmap.cgImage {
            let width = 640
            let height = max(1, Int(CGFloat(width) * CGFloat(image.height) / CGFloat(image.width)))
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
                .write(to: artifacts.appendingPathComponent("\(name)-thumbnail.png"))
        }
        return bitmap
    }

    static func checkLayout(_ editor: EditorWindowController, toolbar: NSView, controls: [NSControl], name: String) {
        let content = editor.window!.contentView!
        let canvas = editor.canvas
        check(content.subviews.count == 2 && content.subviews.contains(where: { $0 === toolbar }) &&
              content.subviews.contains(where: { $0 === canvas }), "\(name): only the top toolbar and canvas occupy the content view")
        check(near(canvas.frame.minY, content.bounds.minY), "\(name): canvas reaches the bottom with no footer")
        check(near(canvas.frame.minX, content.bounds.minX) && near(canvas.frame.maxX, content.bounds.maxX), "\(name): canvas spans the full width")
        check(near(toolbar.frame.maxY, content.bounds.maxY), "\(name): toolbar is at the top")
        check(near(toolbar.frame.minX, content.bounds.minX) && near(toolbar.frame.maxX, content.bounds.maxX), "\(name): toolbar spans the full width")
        check(toolbar.frame.height > 0 && toolbar.frame.height <= 72, "\(name): toolbar stays compact (\(toolbar.frame.height) pt)")
        check(near(canvas.frame.maxY, toolbar.frame.minY), "\(name): toolbar and canvas meet without an extra row")
        check(canvas.frame.height > 300, "\(name): canvas retains useful vertical space")
        check(!content.hasAmbiguousLayout && !toolbar.hasAmbiguousLayout && !canvas.hasAmbiguousLayout, "\(name): primary layout is unambiguous")
        let visible = controls.filter { !$0.isHiddenOrHasHiddenAncestor }
        for control in visible {
            let frame = control.convert(control.bounds, to: toolbar)
            check(frame.width > 0 && frame.height > 0 && toolbar.bounds.insetBy(dx: -1, dy: -1).contains(frame), "\(name): \(control.identifier!.rawValue) is fully visible")
            check(!control.hasAmbiguousLayout, "\(name): \(control.identifier!.rawValue) has an unambiguous layout")
        }
        for first in 0..<visible.count {
            for second in (first + 1)..<visible.count {
                let a = visible[first].convert(visible[first].bounds, to: toolbar)
                let b = visible[second].convert(visible[second].bounds, to: toolbar)
                check(!a.insetBy(dx: 0.5, dy: 0.5).intersects(b.insetBy(dx: 0.5, dy: 0.5)), "\(name): \(visible[first].identifier!.rawValue) and \(visible[second].identifier!.rawValue) do not overlap")
            }
        }
    }

    static func key(_ canvas: CanvasView, _ value: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: canvas.window!.windowNumber, context: nil, characters: value,
                        charactersIgnoringModifiers: value, isARepeat: false, keyCode: code)!
    }

    static func mouse(_ canvas: CanvasView, at point: CGPoint, type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.geometry.viewPoint(from: point), to: nil),
                          modifierFlags: [], timestamp: 0, windowNumber: canvas.window!.windowNumber,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    static func action(_ control: NSControl) {
        check(control.action != nil && control.target != nil, "\(control.identifier!.rawValue): has a target/action")
        check(control.sendAction(control.action, to: control.target), "\(control.identifier!.rawValue): dispatches its action")
    }

    static func checkCopy(_ window: NSWindow, button: NSButton, expected: Data, name: String) {
        // Only this generated fixture is copied on the ephemeral macOS runner.
        let path = NSPasteboard.general.string(forType: .string)
        check(path?.hasPrefix("/") == true && path?.contains("file://") == false, "\(name): clipboard contains an absolute plain path")
        if let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            check(data == expected, "\(name): saved PNG bytes match the actual annotation export")
            let bitmap = NSBitmapImageRep(data: data)
            check(bitmap?.pixelsWide == Int(sourceSize.width) && bitmap?.pixelsHigh == Int(sourceSize.height), "\(name): saved copy preserves source pixel dimensions")
        } else { check(false, "\(name): clipboard path is readable") }
        check(NSPasteboard.general.data(forType: .png) == nil && NSPasteboard.general.data(forType: .tiff) == nil &&
              NSPasteboard.general.string(forType: .fileURL) == nil, "\(name): clipboard only offers text, never image or file URL flavors")
        check(button.title.contains("路径已复制"), "\(name): path copy confirmation appears in the action button")
        check(!window.isDocumentEdited, "\(name): copied version is marked exported")
    }

    static func checkTool(_ editor: EditorWindowController, expected: CanvasView.Tool, brush: NSButton, text: NSButton,
                          brushSettings: NSView, textSettings: NSView, name: String) {
        check(editor.canvas.tool == expected, "\(name): canvas tool matches")
        check(brush.state == (expected == .brush ? .on : .off) && text.state == (expected == .text ? .on : .off), "\(name): precisely one tool is selected")
        check((brush.accessibilityValue() as? NSNumber)?.intValue == (expected == .brush ? 1 : 0) &&
              (text.accessibilityValue() as? NSNumber)?.intValue == (expected == .text ? 1 : 0), "\(name): accessibility selection matches the active tool")
        check(brushSettings.isHidden == (expected != .brush) && textSettings.isHidden == (expected != .text), "\(name): only the selected tool's settings are shown")
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let source = fixture()
        let sourcePNG = try AnnotationRenderer.png(image: source, annotations: [])
        try sourcePNG.write(to: artifacts.appendingPathComponent("toolbar-synthetic-source.png"))
        let sourceBitmap = NSBitmapImageRep(data: sourcePNG)!
        let store = CopiedImageStore(directory: artifacts.appendingPathComponent("toolbar-copied-images"))
        let editor = EditorWindowController(image: source, imagePathCopier: ImagePathCopier(store: store))
        let window = editor.window!
        let content = window.contentView!
        guard let toolbar = find("editor.toolbar", in: content, as: NSView.self),
              let brush = find("editor.tools.brush", in: content, as: NSButton.self),
              let text = find("editor.tools.text", in: content, as: NSButton.self),
              let color = find("editor.color", in: content, as: NSColorWell.self),
              let width = find("editor.brush.width", in: content, as: NSSlider.self),
              let widthValue = find("editor.brush.value", in: content, as: NSTextField.self),
              let font = find("editor.text.size", in: content, as: NSPopUpButton.self),
              let undo = find("editor.history.undo", in: content, as: NSButton.self),
              let redo = find("editor.history.redo", in: content, as: NSButton.self),
              let copy = find("editor.export.copy", in: content, as: NSButton.self),
              let save = find("editor.export.save", in: content, as: NSButton.self),
              let brushSettings = find("editor.settings.brush", in: content, as: NSView.self),
              let textSettings = find("editor.settings.text", in: content, as: NSView.self) else {
            print("FAIL: toolbar controls missing; \(checks) assertions, \(failures) failures")
            exit(1)
        }
        let controls: [NSControl] = [brush, text, color, width, font, undo, redo, copy, save]
        for control in controls {
            check(!(control.accessibilityLabel() ?? "").isEmpty, "\(control.identifier!.rawValue): has an accessibility label")
            check(!(control.toolTip ?? "").isEmpty, "\(control.identifier!.rawValue): has a discoverable tooltip")
            check(!control.refusesFirstResponder, "\(control.identifier!.rawValue): permits keyboard focus")
        }
        check(copy.title.contains("复制路径") && copy.accessibilityLabel()?.contains("路径") == true && copy.toolTip?.contains("本机 Codex CLI") == true, "copy label and tooltip describe persistent file paths")
        check(brush.toolTip?.contains("B") == true && text.toolTip?.contains("T") == true, "tool tooltips expose B/T shortcuts")
        check(!undo.isEnabled && !redo.isEnabled, "empty history disables both history actions")
        checkTool(editor, expected: .brush, brush: brush, text: text, brushSettings: brushSettings, textSettings: textSettings, name: "initial")

        // Offscreen rendering does not activate the app or capture any desktop pixels.
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for size in ["minimum", "large"] {
                if size == "minimum" {
                    window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: false)
                } else { window.setContentSize(NSSize(width: 1260, height: 820)) }
                for (toolName, button, expected) in [("brush", brush, CanvasView.Tool.brush), ("text", text, CanvasView.Tool.text)] {
                    button.performClick(nil)
                    layout(window)
                    let name = "toolbar-\(theme)-\(toolName)-\(size)"
                    checkTool(editor, expected: expected, brush: brush, text: text, brushSettings: brushSettings, textSettings: textSettings, name: name)
                    checkLayout(editor, toolbar: toolbar, controls: controls, name: name)
                    _ = try render(content, name: name)
                }
            }
        }

        for iteration in 1...3 {
            for (button, expected) in [(brush, CanvasView.Tool.brush), (brush, .brush), (text, .text), (text, .text)] {
                button.performClick(nil)
                checkTool(editor, expected: expected, brush: brush, text: text, brushSettings: brushSettings, textSettings: textSettings, name: "repeated click \(iteration)")
            }
            for (value, code, expected) in [("b", UInt16(11), CanvasView.Tool.brush), ("t", UInt16(17), .text)] {
                editor.canvas.keyDown(with: key(editor.canvas, value, code: code))
                checkTool(editor, expected: expected, brush: brush, text: text, brushSettings: brushSettings, textSettings: textSettings, name: "shortcut \(value) \(iteration)")
            }
        }
        brush.performClick(nil)
        width.doubleValue = 14
        action(width)
        check(near(editor.canvas.brushWidth, 14), "width slider changes subsequent brush width")
        check(widthValue.stringValue.contains("14"), "width value label updates immediately")
        let annotationColor = rgb(0.91, 0.16, 0.34)
        color.color = annotationColor
        action(color)
        check(sameColor(editor.canvas.color, annotationColor), "color well updates subsequent annotation color")
        layout(window)
        let point = CGPoint(x: 1160, y: 135)
        editor.canvas.mouseDown(with: mouse(editor.canvas, at: point, type: .leftMouseDown))
        editor.canvas.mouseUp(with: mouse(editor.canvas, at: point, type: .leftMouseUp))
        check(editor.canvas.history.items.count == 1 && undo.isEnabled && !redo.isEnabled, "brush commit enables undo only")
        if case .brush(let stroke)? = editor.canvas.history.items.last {
            check(near(stroke.width, 14) && sameColor(stroke.color, annotationColor), "new brush annotation retains toolbar settings")
        } else { check(false, "brush annotation exists") }
        let brushPNG = try editor.canvas.exportPNG()
        try brushPNG.write(to: artifacts.appendingPathComponent("toolbar-brush-export.png"))
        let brushBitmap = NSBitmapImageRep(data: brushPNG)!
        let px = Int(point.x), py = Int(sourceSize.height - point.y)
        check(samePixel(brushBitmap.colorAt(x: px, y: py)!, annotationColor), "actual PNG contains the toolbar-configured brush")
        undo.performClick(nil)
        check(editor.canvas.history.items.isEmpty && !undo.isEnabled && redo.isEnabled, "undo button updates history and enabled states")
        let undonePNG = try editor.canvas.exportPNG()
        try undonePNG.write(to: artifacts.appendingPathComponent("toolbar-undo-export.png"))
        check(samePixel(NSBitmapImageRep(data: undonePNG)!.colorAt(x: px, y: py)!, sourceBitmap.colorAt(x: px, y: py)!), "undo restores the synthetic source pixel")
        redo.performClick(nil)
        check(editor.canvas.history.items.count == 1 && undo.isEnabled && !redo.isEnabled, "redo button restores history and enabled states")
        let redonePNG = try editor.canvas.exportPNG()
        check(samePixel(NSBitmapImageRep(data: redonePNG)!.colorAt(x: px, y: py)!, annotationColor), "redo restores the exported brush pixel")

        text.performClick(nil)
        font.selectItem(withTitle: "48")
        check(font.titleOfSelectedItem == "48", "48-point font size is available")
        action(font)
        check(near(editor.canvas.textSize, 48), "font picker changes subsequent text size")
        layout(window)
        let textPoint = CGPoint(x: 350, y: 160)
        editor.canvas.mouseDown(with: mouse(editor.canvas, at: textPoint, type: .leftMouseDown))
        if let field = editor.canvas.subviews.compactMap({ $0 as? NSTextView }).first {
            field.string = "Discard this draft"
            field.didChangeText()
            check(editor.canvas.hasPendingContent && undo.isEnabled && !redo.isEnabled, "pending text keeps history actions correct")
            editor.canvas.keyDown(with: key(editor.canvas, "\u{1b}", code: 53))
            check(!editor.canvas.isEditingText && editor.canvas.history.items.count == 1, "Escape discards an interrupted text annotation")
        } else { check(false, "text tool creates its real inline editor") }
        editor.canvas.mouseDown(with: mouse(editor.canvas, at: textPoint, type: .leftMouseDown))
        if let field = editor.canvas.subviews.compactMap({ $0 as? NSTextView }).first {
            field.string = "Ready to share"
            field.didChangeText()
            brush.performClick(nil)
            check(!editor.canvas.isEditingText && editor.canvas.history.items.count == 2, "switching tools commits inline text exactly once")
            if case .text(let annotation)? = editor.canvas.history.items.last {
                check(annotation.text == "Ready to share" && near(annotation.fontSize, 48) && sameColor(annotation.color, annotationColor), "committed text retains the selected content, font, and color")
            } else { check(false, "text annotation exists") }
            brush.performClick(nil)
            brush.performClick(nil)
            check(editor.canvas.history.items.count == 2, "repeated selected-tool clicks do not duplicate committed text")
        } else { check(false, "text input can be restarted after cancellation") }
        let annotatedPNG = try editor.canvas.exportPNG()
        try annotatedPNG.write(to: artifacts.appendingPathComponent("toolbar-annotated-export.png"))
        let annotated = NSBitmapImageRep(data: annotatedPNG)!
        check(annotated.pixelsWide == Int(sourceSize.width) && annotated.pixelsHigh == Int(sourceSize.height), "toolbar annotations export at source resolution")
        var changedPixels = 0
        for y in stride(from: 735, to: 820, by: 2) {
            for x in stride(from: 340, to: 850, by: 2) {
                if !samePixel(annotated.colorAt(x: x, y: y)!, brushBitmap.colorAt(x: x, y: y)!) { changedPixels += 1 }
            }
        }
        check(changedPixels > 100, "actual PNG renders the text annotation (\(changedPixels) sampled changed pixels)")
        undo.performClick(nil)
        check(editor.canvas.history.items.count == 1 && redo.isEnabled, "text annotation is one undo step")
        redo.performClick(nil)
        check(editor.canvas.history.items.count == 2 && !redo.isEnabled, "text annotation is one redo step")

        let expectedClipboardPNG = try editor.canvas.exportPNG()
        copy.performClick(nil)
        checkCopy(window, button: copy, expected: expectedClipboardPNG, name: "copy button")
        let firstCopiedPath = NSPasteboard.general.string(forType: .string)
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: false)
            layout(window)
            checkLayout(editor, toolbar: toolbar, controls: controls, name: "copy feedback minimum \(theme)")
            check(copy.title.contains("路径已复制"), "\(theme): minimum-size render includes the actual success caption")
            let captionWidth = copy.attributedTitle.size().width + (copy.image?.size.width ?? 0) + 12
            check(captionWidth <= copy.bounds.width, "\(theme): successful copy caption and icon fit at minimum window size")
            _ = try render(content, name: "toolbar-\(theme)-copy-feedback-minimum")
        }
        window.setContentSize(NSSize(width: 1260, height: 820))
        layout(window)
        checkLayout(editor, toolbar: toolbar, controls: controls, name: "copy feedback")
        _ = try render(content, name: "toolbar-dark-copy-feedback")
        check(window.performKeyEquivalent(with: key(editor.canvas, "z", code: 6, modifiers: .command)), "Command-Z is handled by the real editor window")
        check(editor.canvas.history.items.count == 1 && redo.isEnabled && window.isDocumentEdited, "Command-Z undoes one annotation and marks the copied version changed")
        check(window.performKeyEquivalent(with: key(editor.canvas, "z", code: 6, modifiers: [.command, .shift])), "Shift-Command-Z is handled by the real editor window")
        check(editor.canvas.history.items.count == 2 && !redo.isEnabled && !window.isDocumentEdited, "Shift-Command-Z restores the copied version and its export state")
        check(window.performKeyEquivalent(with: key(editor.canvas, "c", code: 8, modifiers: [.command, .shift])), "Shift-Command-C is handled by the real editor window")
        checkCopy(window, button: copy, expected: expectedClipboardPNG, name: "copy shortcut")
        check(NSPasteboard.general.string(forType: .string) != firstCopiedPath, "repeated copy creates a new path")
        check(firstCopiedPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } == expectedClipboardPNG, "earlier copied path remains readable and unchanged")
        layout(window)
        check(content.subviews.count == 2 && near(editor.canvas.frame.minY, content.bounds.minY), "copy shortcut confirmation does not create a footer")
        for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            text.performClick(nil)
            layout(window)
            _ = try render(content, name: "toolbar-\(theme)-annotated")
        }
        window.orderOut(nil)
        print("\(failures == 0 ? "PASS" : "FAIL"): \(checks) toolbar interaction, layout and rendering assertions, \(failures) failures")
        if failures != 0 { exit(1) }
    }
}
