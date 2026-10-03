import AppKit

private final class MenuProbe: NSObject {
    var calls: [String] = []
    @objc func capture(_ sender: Any?) { calls.append("capture") }
    @objc func images(_ sender: Any?) { calls.append("images") }
    @objc func cleanup(_ sender: Any?) { calls.append("cleanup") }
    @objc func settings(_ sender: Any?) { calls.append("settings") }
    @objc func permissions(_ sender: Any?) { calls.append("permissions") }
    @objc func help(_ sender: Any?) { calls.append("help") }
    @objc func about(_ sender: Any?) { calls.append("about") }
}

private final class IconPreviewView: NSView {
    var fillColor = NSColor.white
    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        bounds.fill()
    }
}

/// These tests never register hotkeys, capture a screen, open Finder/settings,
/// or terminate the application. The previews contain only our own icon.
@main
struct StatusMenuTests {
    static var checks = 0
    static var failures = 0
    static let artifacts = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APRILSHOT_TEST_ARTIFACTS"] ?? ".build/rendering-artifacts", isDirectory: true)

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    static func write(_ bitmap: NSBitmapImageRep, _ name: String) throws {
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: artifacts.appendingPathComponent("\(name).png"))
    }

    static func mask(_ image: NSImage, scale: Int) -> NSBitmapImageRep {
        let pixels = 18 * scale
        let context = CGContext(data: nil, width: pixels, height: pixels,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: StatusIcon.size), from: .zero,
                   operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return NSBitmapImageRep(cgImage: context.makeImage()!)
    }

    static func alpha(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)!.alphaComponent
    }

    static func checkMask(_ image: NSImage, scale: Int) throws {
        let bitmap = mask(image, scale: scale)
        let pixels = 18 * scale
        check(bitmap.pixelsWide == pixels && bitmap.pixelsHigh == pixels, "\(scale)×: preserves requested resolution")
        var edgeIsClear = true
        var occupied = 0
        for y in 0..<pixels {
            for x in 0..<pixels {
                let value = alpha(bitmap, x, y)
                if value > 0.1 { occupied += 1 }
                if x == 0 || y == 0 || x == pixels - 1 || y == pixels - 1 {
                    edgeIsClear = edgeIsClear && value < 0.01
                }
            }
        }
        check(edgeIsClear, "\(scale)×: artwork has clear padding and no clipped edges")
        let coverage = Double(occupied) / Double(pixels * pixels)
        check(coverage > 0.14 && coverage < 0.4, "\(scale)×: visible strokes without a heavy filled silhouette")
        check(alpha(bitmap, 9 * scale, 9 * scale) > 0.7, "\(scale)×: centre shutter dot remains visible")
        check(alpha(bitmap, 9 * scale, 3 * scale) < 0.01 && alpha(bitmap, 3 * scale, 9 * scale) < 0.01,
              "\(scale)×: open frame gaps remain transparent")
        for (name, x, y) in [("top left", 3, 4), ("top right", 14, 4),
                             ("bottom left", 3, 13), ("bottom right", 14, 13)] {
            var count = 0
            for row in (y - 1) * scale..<(y + 2) * scale {
                for column in (x - 1) * scale..<(x + 2) * scale {
                    if alpha(bitmap, column, row) > 0.1 { count += 1 }
                }
            }
            check(count > 2 * scale * scale, "\(scale)×: \(name) capture corner is present")
        }
        try write(bitmap, "status-icon-mask-\(scale)x")
    }

    static func checkMenu() {
        let probe = MenuProbe()
        let status = StatusMenu(target: probe, capture: #selector(MenuProbe.capture(_:)),
                                images: #selector(MenuProbe.images(_:)),
                                cleanup: #selector(MenuProbe.cleanup(_:)), settings: #selector(MenuProbe.settings(_:)),
                                permissions: #selector(MenuProbe.permissions(_:)),
                                help: #selector(MenuProbe.help(_:)), about: #selector(MenuProbe.about(_:)))
        let menu = status.menu
        let items = menu.items.filter { !$0.isSeparatorItem }
        check(items.map { $0.title } == ["截图", "图片文件夹", "清理…", "设置…", "截图权限…", "帮助", "关于", "退出"],
              "short labels retain every existing capability")
        check(menu.items.count == 10 && menu.items[3].isSeparatorItem && menu.items[8].isSeparatorItem,
              "capture/files, support, and quit are separated")
        check(items.map { $0.identifier?.rawValue } == ["status.capture", "status.images", "status.cleanup", "status.settings", "status.permissions", "status.help", "status.about", "status.quit"],
              "menu items have unique stable identifiers")
        check(items.allSatisfy { !$0.title.contains("⌘") && !$0.title.contains("\n") && !$0.title.contains("  ") },
              "titles contain no fake shortcut spacing or instructional paragraphs")
        check(items.allSatisfy { $0.title.count <= 5 }, "all visible labels fit in five characters")
        check(items.allSatisfy { $0.submenu == nil && $0.isEnabled }, "actions remain one click away")
        check(status.captureItem === items[0], "busy state references the actual capture item")
        check(items[0].keyEquivalent == "2" && items[0].keyEquivalentModifierMask == [.command, .shift],
              "capture uses the native ⌘⇧2 shortcut column")
        check(items[7].keyEquivalent == "q" && items[7].keyEquivalentModifierMask == [.command],
              "quit retains ⌘Q")
        check(items[7].action == #selector(NSApplication.terminate(_:)) && items[7].target === NSApp,
              "quit uses application termination and its unsaved-image protection")
        check([items[1], items[2], items[4], items[5], items[6]].allSatisfy { $0.keyEquivalent.isEmpty }, "support actions do not add shortcut conflicts")
        check(items[3].keyEquivalent == "," && items[3].keyEquivalentModifierMask == [.command], "settings uses the standard Command-comma shortcut")
        for item in items.prefix(7) {
            check(item.target === probe && item.action != nil, "\(item.title): retains an explicit target/action")
            menu.performActionForItem(at: menu.index(of: item))
        }
        check(probe.calls == ["capture", "images", "cleanup", "settings", "permissions", "help", "about"], "all seven actions dispatch to their original destinations")
        check(!menu.autoenablesItems, "menu honours the explicit capture busy state")
        for _ in 0..<3 {
            status.captureItem.isEnabled = false
            menu.update()
            check(!status.captureItem.isEnabled, "opening/updating the menu does not re-enable a busy capture")
            status.captureItem.isEnabled = true
            menu.update()
            check(status.captureItem.isEnabled, "capture becomes available again after completion/cancel")
        }
        // Construct a physical ANSI 2 event using the runner's keyboard layout.
        // In particular, charactersIgnoringModifiers must retain Shift; making
        // up a "2" string with a Shift flag would not model a real key press.
        if let key = CGEvent(keyboardEventSource: nil, virtualKey: 19, keyDown: true) {
            key.flags = [.maskCommand, .maskShift]
            if let event = NSEvent(cgEvent: key) {
                for enabled in [true, false, true] {
                    status.captureItem.isEnabled = enabled
                    menu.update()
                    let before = probe.calls.count
                    let handled = menu.performKeyEquivalent(with: event)
                    if enabled { check(handled, "native capture shortcut is handled when available") }
                    check(probe.calls.count == before + (enabled ? 1 : 0), "native shortcut sends exactly one enabled capture action")
                }
            } else { check(false, "physical capture key converts to an AppKit event") }
        } else { check(false, "physical capture key event can be constructed") }
        let help = StatusMenu.helpText(shortcut: .default)
        check(help.contains("⇧⌘C") && help.contains("复制路径") &&
              help.contains("远程环境") && help.contains("废纸篓"),
              "concise help retains persistent local path and remote-environment guidance")
        check(help.count < 260, "help stays concise")
        check(help.contains("框选") && help.contains("3 天"), "help explains rectangle and new retention default")
        let custom = try! HotKeyShortcut(keyCode: 35, modifiers: [.control, .option])
        let customMenu = StatusMenu(target: probe, capture: #selector(MenuProbe.capture(_:)),
                                    images: #selector(MenuProbe.images(_:)), cleanup: #selector(MenuProbe.cleanup(_:)),
                                    settings: #selector(MenuProbe.settings(_:)), permissions: #selector(MenuProbe.permissions(_:)),
                                    help: #selector(MenuProbe.help(_:)), about: #selector(MenuProbe.about(_:)), shortcut: custom)
        check(customMenu.captureItem.keyEquivalent == custom.keyEquivalent && customMenu.captureItem.keyEquivalentModifierMask == custom.keyEquivalentModifierMask,
              "menu uses configured shortcut instead of stale default")
        check(StatusMenu.helpText(shortcut: custom).contains(custom.displayString), "help displays configured shortcut")
        check(!StatusMenu.helpText(shortcut: nil).contains("⌘⇧2"), "failed hotkey registration does not advertise default as active")
    }

    /// Real AppKit template rendering in a synthetic button fixture. These are
    /// not screenshots of a user's desktop or claims about menu-bar wallpaper.
    static func checkAppearance(_ image: NSImage, name: String, appearance: NSAppearance.Name,
                                background: NSColor, foreground: NSColor) throws {
        let view = IconPreviewView(frame: NSRect(x: 0, y: 0, width: 72, height: 36))
        view.appearance = NSAppearance(named: appearance)
        view.fillColor = background
        let button = NSButton(frame: NSRect(x: 18, y: 0, width: 36, height: 36))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.image = image
        button.contentTintColor = foreground
        button.setAccessibilityLabel("AprilShot")
        view.addSubview(button)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = view.appearance
        window.isReleasedWhenClosed = false
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try write(bitmap, "status-icon-\(name)-appkit")
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let expectedBackground = background.usingColorSpace(.sRGB)!
        let corner = bitmap.colorAt(x: 0, y: 0)!
        check(corner.alphaComponent > 0.99 &&
              abs(corner.redComponent - expectedBackground.redComponent) < 0.05 &&
              abs(corner.greenComponent - expectedBackground.greenComponent) < 0.05 &&
              abs(corner.blueComponent - expectedBackground.blueComponent) < 0.05,
              "\(name): preview has the expected opaque background")
        var visiblePixels = 0
        var strayPixels = 0
        let iconRegion = NSRect(x: 24, y: 6, width: 24, height: 24)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let pixel = bitmap.colorAt(x: x, y: y)!
                if pixel.alphaComponent > 0.9 && abs(pixel.redComponent - expectedBackground.redComponent) > 0.5 {
                    if iconRegion.contains(NSPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale)) {
                        visiblePixels += 1
                    } else { strayPixels += 1 }
                }
            }
        }
        check(CGFloat(visiblePixels) > 20 * scale * scale && CGFloat(visiblePixels) < 180 * scale * scale,
              "\(name): native template button has contrasting artwork, not a blank or filled fixture")
        check(strayPixels == 0, "\(name): artwork stays inside the centred icon region")
        check(button.image?.isTemplate == true && button.image?.size == StatusIcon.size,
              "\(name): template stays at native 18-point size")
        check(button.accessibilityLabel() == "AprilShot", "\(name): icon-only button keeps an accessible name")
        window.close()
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let image = StatusIcon.makeImage()
        check(image.isTemplate, "the system controls light/dark/highlight tint")
        check(image.size == NSSize(width: 18, height: 18), "icon has menu-bar-sized intrinsic dimensions")
        for scale in [1, 2, 3] { try checkMask(image, scale: scale) }
        checkMenu()
        try checkAppearance(image, name: "light", appearance: .aqua, background: .white, foreground: .black)
        try checkAppearance(image, name: "dark", appearance: .darkAqua, background: .black, foreground: .white)
        try checkAppearance(image, name: "selected", appearance: .darkAqua,
                            background: NSColor(srgbRed: 0.05, green: 0.35, blue: 0.82, alpha: 1), foreground: .white)
        print("Status menu tests: \(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
