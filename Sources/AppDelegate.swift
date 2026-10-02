import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKeyManager()
    private let capture = ScreenshotCapture()
    private var editors: [UUID: EditorWindowController] = [:]
    private var capturePending = false
    private var captureItem: NSMenuItem!
    private var didRequestPermission = false
    private var showingAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        buildStatusMenu()
        hotKey.onPress = { [weak self] in self?.captureRegion(nil) }
        do { try hotKey.register() }
        catch { DispatchQueue.main.async { self.showMessage(error.localizedDescription) } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Ask about every unexported image before terminating a menu-bar-only app.
        for editor in editors.values {
            if let window = editor.window, !editor.windowShouldClose(window) { return .terminateCancel }
        }
        capture.cancel()
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let editor = editors.values.first { editor.present() }
        return false
    }
    private func buildMainMenu() {
        // Standard responder-chain edit actions are important for Chinese IME and inline text.
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 AprilShot", action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 AprilShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "AprilShot 截图") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else { statusItem.button?.title = "截" }
        statusItem.button?.toolTip = "AprilShot · ⌘⇧2 截取区域"
        let menu = NSMenu()
        captureItem = menu.addItem(withTitle: "截取区域    ⌘⇧2", action: #selector(captureRegion(_:)), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(withTitle: "打开已复制图片文件夹…", action: #selector(openCopiedImages(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "使用说明…", action: #selector(showHelp(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "屏幕录制设置…", action: #selector(openScreenSettings(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "关于 AprilShot", action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "退出 AprilShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    @objc private func captureRegion(_ sender: Any?) {
        guard !capturePending, !capture.isRunning, !showingAlert else { return }
        // Avoid hiding an active Save/error sheet; the user can finish or cancel it first.
        if let editor = editors.values.first(where: { $0.window?.attachedSheet != nil }) {
            editor.present()
            NSSound.beep()
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            if !didRequestPermission {
                didRequestPermission = true
                showingAlert = true
                let granted = CGRequestScreenCaptureAccess()
                showingAlert = false
                if granted { beginCapture(); return }
            }
            showPermissionHelp()
            return
        }
        beginCapture()
    }
    private func beginCapture() {
        capturePending = true
        captureItem.isEnabled = false
        for editor in editors.values { editor.canvas.commitText(); editor.canvas.finishStroke() }
        NSColorPanel.shared.orderOut(nil)
        NSApp.hide(nil)
        // Let the status menu and editor disappear before the system picker snapshots the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.capture.start { [weak self] result in
                guard let self = self else { return }
                self.capturePending = false
                self.captureItem.isEnabled = true
                NSApp.unhideWithoutActivation()
                switch result {
                case .captured(let image): self.openEditor(image: image)
                case .cancelled: break
                case .failed(let message): self.showMessage(message)
                }
            }
        }
    }
    private func openEditor(image: CGImage) {
        let id = UUID()
        let editor = EditorWindowController(image: image)
        editor.onClose = { [weak self] in self?.editors.removeValue(forKey: id) }
        editors[id] = editor
        editor.present()
    }
    private func showPermissionHelp() {
        guard !showingAlert else { return }
        showingAlert = true
        defer { showingAlert = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕录制”（新版本可能显示为“屏幕与系统音频录制”）中允许 AprilShot，然后完全退出并重新打开 App。无需辅助功能或输入监控权限。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn { openScreenSettings(nil) }
    }
    @objc private func openScreenSettings(_ sender: Any?) {
        // Best-effort deep link; help text also gives the path if Apple changes it.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func openCopiedImages(_ sender: Any?) {
        do {
            let directory = try CopiedImageStore.exportsDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(directory) { showMessage("无法打开已复制图片文件夹：\(directory.path)") }
        } catch { showMessage("无法打开已复制图片文件夹：\(error.localizedDescription)") }
    }
    @objc private func showHelp(_ sender: Any?) {
        showMessage("1. 按 ⌘⇧2 或点击“截取区域”，拖出区域，Esc 取消。\n2. 用画笔拖动标注；切到文字后点击图片输入，⌘Return 完成，Esc 放弃当前文字。\n3. ⌘Z 撤销，⇧⌘Z 重做。输入文字时沿用系统文本编辑快捷键。\n4. ⇧⌘C 保存标注 PNG 并复制绝对路径，粘贴到本机 Codex CLI 的提示中即可让它读取；⌘S 另存为 PNG。\n复制的图片会一直保留，可从菜单“打开已复制图片文件夹…”查看或手动清理。远程环境无法直接读取本机路径。\n5. 关闭标注窗口后仍驻留菜单栏。需要开机启动时，可在系统设置的登录项中手动添加 AprilShot。")
    }
    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3"
        showMessage("AprilShot \(version)\n原生 macOS 菜单栏截图与轻量标注。\n截图与标注仅在本机处理，无网络请求、遥测或第三方依赖。")
    }
    private func showMessage(_ text: String) {
        guard !showingAlert else { return }
        showingAlert = true
        defer { showingAlert = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AprilShot"
        alert.informativeText = text
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
