import AppKit

/// An 18-point capture frame with a shutter dot. Drawing on demand keeps the
/// template crisp at any backing scale; AppKit supplies the menu-bar tint.
enum StatusIcon {
    static let size = NSSize(width: 18, height: 18)

    static func makeImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let frame = NSBezierPath()
            frame.lineWidth = 1.5
            frame.lineCapStyle = .round
            frame.lineJoinStyle = .round

            // Four rounded corners leave the centre open and legible at 1×.
            for (x, y) in [(CGFloat(1), CGFloat(1)), (-1, 1), (1, -1), (-1, -1)] {
                func point(_ px: CGFloat, _ py: CGFloat) -> NSPoint {
                    NSPoint(x: 9 + px * x, y: 9 + py * y)
                }
                frame.move(to: point(-3, -6))
                frame.line(to: point(-5, -6))
                frame.curve(to: point(-6.5, -4.5),
                            controlPoint1: point(-5.83, -6), controlPoint2: point(-6.5, -5.33))
                frame.line(to: point(-6.5, -2.5))
            }
            frame.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.5, y: 7.5, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Keep the real menu independently testable without starting a capture,
/// registering a global shortcut, or showing a permission prompt.
struct StatusMenu {
    let menu: NSMenu
    let captureItem: NSMenuItem

    init(target: AnyObject, capture: Selector, images: Selector,
         permissions: Selector, help: Selector, about: Selector) {
        let menu = NSMenu()
        // AppDelegate owns the capture item's busy state. Automatic validation
        // would otherwise re-enable it while the system selector is running.
        menu.autoenablesItems = false

        @discardableResult
        func item(_ title: String, _ action: Selector, _ id: String,
                  key: String = "") -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = target
            item.identifier = NSUserInterfaceItemIdentifier("status.\(id)")
            return item
        }

        captureItem = item("截图", capture, "capture", key: "2")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        item("图片文件夹", images, "images")
        menu.addItem(.separator())
        item("截图权限…", permissions, "permissions")
        item("帮助", help, "help")
        item("关于", about, "about")
        menu.addItem(.separator())
        let quit = item("退出", #selector(NSApplication.terminate(_:)), "quit", key: "q")
        quit.target = NSApp
        quit.keyEquivalentModifierMask = [.command]
        self.menu = menu
    }

    static let helpText = """
    ⌘⇧2  截图 · Esc 取消
    画笔 / 文字  标注 · ⌘Return 完成文字
    ⌘Z / ⇧⌘Z  撤销 / 重做
    ⇧⌘C  复制路径 · ⌘S 保存 PNG

    图片保存在本机，可从“图片文件夹”查看或清理。
    本机应用可读取复制的路径；远程环境需另行传输。
    关闭窗口后，仍可从菜单栏截图。
    """
}
