import AppKit

/// Real AppKit canvas + disk + pasteboard regression. All inputs are synthetic.
@main
struct CopyPathTests {
    static var checks = 0
    static var failures = 0
    static let size = CGSize(width: 720, height: 480)
    struct TestFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        checks += 1
        do {
            if try !condition() { failures += 1; print("FAIL: \(message)") }
        } catch { failures += 1; print("FAIL: \(message): \(error)") }
    }
    static func fixture() -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        return context.makeImage()!
    }
    static func mouse(_ canvas: CanvasView, at point: CGPoint, type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.geometry.viewPoint(from: point), to: nil),
                          modifierFlags: [], timestamp: 0, windowNumber: canvas.window!.windowNumber,
                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    static func copyButton(_ editor: EditorWindowController) -> NSButton {
        descendants(editor.window!.contentView!).first { $0.identifier?.rawValue == "editor.export.copy" } as! NSButton
    }
    static func dismissError(_ editor: EditorWindowController) {
        check(editor.window?.attachedSheet != nil, "copy failure presents an error sheet")
        if let sheet = editor.window?.attachedSheet {
            editor.window?.endSheet(sheet)
            sheet.orderOut(nil)
            let deadline = Date().addingTimeInterval(1)
            while editor.window?.attachedSheet != nil && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        check(editor.window?.attachedSheet == nil, "error sheet can be dismissed for retry")
    }
    static func clipboardPNG(_ pasteboard: NSPasteboard, editor: EditorWindowController) throws -> (URL, Data) {
        let details: String
        if let view = editor.window?.attachedSheet?.contentView {
            details = descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " | ")
        } else { details = "no error sheet" }
        guard copyButton(editor).title.contains("路径已复制"),
              let path = pasteboard.string(forType: .string), path.hasPrefix("/"), path.hasSuffix(".png") else {
            throw TestFailure(message: "Copy did not publish a PNG path: button=\(copyButton(editor).title); \(details)")
        }
        check(path.hasPrefix("/") && !path.hasPrefix("file:") && !path.contains("\\ "), "clipboard is an unescaped absolute path")
        check(path.hasSuffix(".png"), "path names a PNG")
        // AppKit may advertise the legacy NSStringPboardType alias as well as
        // public.utf8-plain-text; both represent the same plain text payload.
        let types = pasteboard.types ?? []
        check(types.contains(.string) && types.allSatisfy { $0 == .string || $0.rawValue == "NSStringPboardType" },
              "only plain text (including its system alias) is exposed: \(types.map { $0.rawValue })")
        check(pasteboard.data(forType: .png) == nil && pasteboard.data(forType: .tiff) == nil &&
              pasteboard.string(forType: .fileURL) == nil, "terminal paste offers no image or file-URL alternative")
        let url = URL(fileURLWithPath: path)
        check(FileManager.default.isReadableFile(atPath: path), "copied image exists and is readable")
        return (url, try Data(contentsOf: url))
    }
    static func main() {
        do { try runTests() }
        catch { check(false, "stopped dependent copy checks: \(error.localizedDescription)") }
        print("\(failures == 0 ? "PASS" : "FAIL"): \(checks) persistent path copy assertions, \(failures) failures")
        if failures != 0 { exit(1) }
    }
    static func runTests() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // Keep normal success fixtures under the checkout, avoiding macOS's /var
        // temp alias. Symlink rejection is exercised independently by cleanup tests.
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent("AprilShot copy path 测试 \(UUID().uuidString)", isDirectory: true)
        print("Copy-path fixture: \(root.path)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Remove only this isolated fixture; production cleanup separately protects recent and currently copied exports.
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let destination = root.appendingPathComponent("Persistent Exports", isDirectory: true)
        let store = CopiedImageStore(directory: destination)
        var failClipboard = false
        var writeAttempts = 0
        let copier = ImagePathCopier(store: store, writePath: { path in
            writeAttempts += 1
            check(FileManager.default.isReadableFile(atPath: path), "image is readable before clipboard publication")
            if failClipboard { return false }
            return ImagePathCopier.write(path, to: pasteboard)
        })
        let source = fixture()
        var editor: EditorWindowController? = EditorWindowController(image: source, imagePathCopier: copier)
        let window = editor!.window!
        window.contentView!.layoutSubtreeIfNeeded()
        let canvas = editor!.canvas
        let button = copyButton(editor!)
        canvas.tool = .brush
        canvas.color = .red
        canvas.brushWidth = 24
        let point = CGPoint(x: 160, y: 160)
        canvas.mouseDown(with: mouse(canvas, at: point, type: .leftMouseDown))
        canvas.mouseDragged(with: mouse(canvas, at: CGPoint(x: 300, y: 160), type: .leftMouseDragged))
        check(canvas.hasPendingContent && canvas.history.items.isEmpty, "test begins with an uncommitted stroke")
        button.performClick(nil) // Deliberately no mouseUp and no exportPNG before Copy.
        let (brushURL, brushPNG) = try clipboardPNG(pasteboard, editor: editor!)
        check(!canvas.hasPendingContent && canvas.history.items.count == 1, "Copy finishes the pending stroke exactly once")
        check(!window.isDocumentEdited && button.title.contains("路径已复制"), "successful path copy marks this version exported")
        let bitmap = NSBitmapImageRep(data: brushPNG)!
        check(bitmap.pixelsWide == 720 && bitmap.pixelsHigh == 480, "file preserves original source dimensions")
        let red = bitmap.colorAt(x: 220, y: 320)!
        check(red.redComponent > 0.9 && red.greenComponent < 0.1, "saved PNG includes the unfinished brush stroke")
        let blue = bitmap.colorAt(x: 40, y: 440)!
        check(blue.blueComponent > 0.9 && blue.redComponent < 0.1, "saved PNG preserves the source orientation and pixels")
        check(brushURL.path.contains("copy path 测试") && brushURL.path.contains("Persistent Exports"), "spaces and Unicode remain literal in path text")

        canvas.tool = .text
        canvas.color = .black
        let textPoint = CGPoint(x: 140, y: 360)
        canvas.mouseDown(with: mouse(canvas, at: textPoint, type: .leftMouseDown))
        let field = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        // Our shortcut interceptor yields Command-C to the real text responder.
        // Invoke that responder separately; offscreen tests do not install the
        // app menu or claim complete system keyboard routing.
        field.string = "copy selected text"
        field.didChangeText()
        field.setSelectedRange(NSRange(location: 5, length: 8))
        let nativeCopy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, characters: "c",
                                        charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        let attemptsBeforeTextCopy = writeAttempts
        check((window as! EditorWindow).handleShortcut?(nativeCopy) == false, "Command-C interceptor yields during text input")
        field.copy(nil)
        check(NSPasteboard.general.string(forType: .string) == "selected" && canvas.isEditingText,
              "native text Copy keeps selected text semantics and the editor open")
        check(writeAttempts == attemptsBeforeTextCopy && canvas.history.items.count == 1,
              "text Copy does not export an image or commit the draft")
        field.string = ""
        field.setSelectedRange(NSRange(location: 0, length: 0))
        // Include active marked text, as supplied by a real input method.
        field.setMarkedText("中文标注\nRead this image", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        field.didChangeText()
        check(field.hasMarkedText(), "test exercises active input-method composition")
        check(canvas.isEditingText && canvas.hasPendingContent, "copy begins while marked text is still being edited")
        let shortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: "c",
                                      charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        check(window.performKeyEquivalent(with: shortcut), "Shift-Command-C works during inline text editing")
        let (textURL, textPNG) = try clipboardPNG(pasteboard, editor: editor!)
        check(!canvas.isEditingText && canvas.history.items.count == 2, "copy commits active text once, alongside the brush")
        if case .text(let annotation)? = canvas.history.items.last {
            check(annotation.text == "中文标注\nRead this image", "marked Chinese and multiline text is preserved")
        } else { check(false, "text annotation exists") }
        check(textURL != brushURL, "successive copies always use distinct files")
        check(try Data(contentsOf: brushURL) == brushPNG, "later copy does not alter the previous image")
        check(textPNG == (try canvas.exportPNG()), "saved annotated PNG equals a fresh renderer export")
        let textBitmap = NSBitmapImageRep(data: textPNG)!
        var darkPixels = 0
        for y in 100..<260 {
            for x in 135..<580 {
                if textBitmap.colorAt(x: x, y: y)!.redComponent < 0.3 { darkPixels += 1 }
            }
        }
        check(darkPixels > 100, "saved PNG contains actual text pixels, not only annotation history")
        canvas.copyViaResponder(nil)
        let (repeatURL, repeatPNG) = try clipboardPNG(pasteboard, editor: editor!)
        check(repeatURL != textURL && repeatPNG == textPNG && canvas.history.items.count == 2, "responder Copy repeats without duplicating annotations or overwriting files")

        // A clipboard failure leaves the successfully written file intact, marks
        // no new state exported, and replaces any old success feedback.
        failClipboard = true
        canvas.undoAnnotation()
        let beforeFailure = pasteboard.string(forType: .string)
        button.performClick(nil)
        check(window.isDocumentEdited && !button.title.contains("路径已复制") && button.title.contains("失败"), "failed copy never reports success or marks the new version exported")
        check(pasteboard.string(forType: .string) == beforeFailure, "failing publisher leaves its prior clipboard text intact")
        let files = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "png" }
        check(files.count == 4 && files.allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) }, "clipboard failure still retains every saved PNG")
        dismissError(editor!)
        failClipboard = false
        button.performClick(nil)
        let (recoveredURL, _) = try clipboardPNG(pasteboard, editor: editor!)
        check(!window.isDocumentEdited && button.title.contains("路径已复制"), "copy recovers after a transient clipboard failure")

        // A file occupying the target directory gives a deterministic I/O failure
        // without changing system permissions or relying on the CI user's UID.
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blocker)
        let attemptsBeforeDiskFailure = writeAttempts
        let broken = ImagePathCopier(store: CopiedImageStore(directory: blocker.appendingPathComponent("Exports")), writePath: { path in
            writeAttempts += 1
            return ImagePathCopier.write(path, to: pasteboard)
        })
        let oldClipboard = pasteboard.string(forType: .string)
        do { _ = try broken.copyPNG(textPNG); check(false, "blocked storage throws") }
        catch { check(error.localizedDescription.contains("剪贴板未更改"), "disk error explains that clipboard was untouched") }
        check(writeAttempts == attemptsBeforeDiskFailure && pasteboard.string(forType: .string) == oldClipboard, "storage failure cannot call or clear clipboard publication")
        let failedEditor = EditorWindowController(image: source, imagePathCopier: broken)
        failedEditor.copyImagePath(nil)
        check(failedEditor.window!.isDocumentEdited && copyButton(failedEditor).title.contains("失败"), "disk failure leaves controller dirty with accurate feedback")
        dismissError(failedEditor)
        failedEditor.window?.orderOut(nil)

        // Close and release the editor. Nothing owns temporary lifetime for copies.
        check(editor!.windowShouldClose(window), "successful copied version can close without a discard prompt")
        window.close()
        editor = nil
        check(try Data(contentsOf: textURL) == textPNG && FileManager.default.isReadableFile(atPath: recoveredURL.path), "saved copies outlive the editor and its controller")
        let restartedStore = CopiedImageStore(directory: destination)
        let restartedURL = try restartedStore.savePNG(textPNG)
        check(try restartedURL != textURL && Data(contentsOf: textURL) == textPNG, "fresh store instance retains previous paths")
        // An independent process reads the exact path bytes supplied to the clipboard.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.arguments = [textURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let externalData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        check(process.terminationStatus == 0 && externalData == textPNG, "separate local process can read copied image path with spaces and Unicode")
        let defaultDirectory = try CopiedImageStore.exportsDirectory()
        check(defaultDirectory.path.hasSuffix("/Library/Application Support/AprilShot/Exports"), "production copy directory is persistent user Application Support")
    }
}
