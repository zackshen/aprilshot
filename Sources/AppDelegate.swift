import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKey = HotKeyManager()
    private let preferences = AppPreferences()
    private var settingsController: SettingsWindowController?
    private var cleanupTimer: Timer?
    private var didReportCleanupError = false
    private let exportCleanup = ExportCleanup(currentProtectedPath: {
        NSPasteboard.general.string(forType: .string)
    })
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
        let warning = hotKey.registerSavedShortcut(from: preferences)
        updateShortcutPresentation()
        DispatchQueue.main.async { [weak self] in
            if let warning = warning { self?.showMessage(warning) }
            self?.cleanExpiredImages()
        }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanExpiredImages()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Ask about every unexported image before terminating a menu-bar-only app.
        for editor in editors.values {
            if let window = editor.window, !editor.windowShouldClose(window) { return .terminateCancel }
        }
        capture.cancel()
        cleanupTimer?.invalidate()
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
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
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
        statusItem.button?.image = StatusIcon.makeImage()
        statusItem.button?.toolTip = "AprilShot · ⌘⇧2"
        statusItem.button?.setAccessibilityLabel("AprilShot")
        statusItem.button?.setAccessibilityHelp("截图，⌘⇧2")
        let statusMenu = StatusMenu(target: self, capture: #selector(captureRegion(_:)),
                                    images: #selector(openCopiedImages(_:)),
                                    cleanup: #selector(cleanCopiedImages(_:)),
                                    settings: #selector(openSettings(_:)),
                                    permissions: #selector(openScreenSettings(_:)),
                                    help: #selector(showHelp(_:)), about: #selector(showAbout(_:)),
                                    shortcut: preferences.shortcut)
        captureItem = statusMenu.captureItem
        statusItem.menu = statusMenu.menu
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
        for editor in editors.values { editor.canvas.commitPendingAnnotations() }
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
        alert.informativeText = "在系统设置的“隐私与安全性 → 屏幕录制”中允许 AprilShot，然后退出并重新打开。\n新版 macOS 可能显示为“屏幕与系统音频录制”。"
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
            try OwnedExportRegistry.validateDirectory(directory, create: true)
            if !NSWorkspace.shared.open(directory) { showMessage("无法打开已复制图片文件夹：\(directory.path)") }
        } catch { showMessage("无法打开已复制图片文件夹：\(error.localizedDescription)") }
    }
    private func cleanExpiredImages() {
        guard !capturePending, !capture.isRunning, !showingAlert, preferences.loadWarning == nil else { return }
        let policy = ExportRetentionPolicy(rawValue: preferences.retentionDays) ?? .default
        guard policy != .never else { return }
        do {
            let plan = try exportCleanup.plan(mode: .expired(policy))
            let result = try exportCleanup.run(plan)
            if !result.failures.isEmpty && !didReportCleanupError {
                didReportCleanupError = true
                showMessage("部分过期图片未能移入废纸篓，原文件已保留。\n可稍后从菜单选择“清理…”重试。\n" + result.failures[0].message)
            }
        } catch {
            if !didReportCleanupError {
                didReportCleanupError = true
                showMessage("自动清理未完成，图片已保留。\n" + error.localizedDescription)
            }
        }
    }
    @objc private func cleanCopiedImages(_ sender: Any?) {
        guard !capturePending, !capture.isRunning, !showingAlert else { NSSound.beep(); return }
        do {
            let plan = try exportCleanup.plan(mode: .allOwned)
            guard plan.count > 0 else {
                showMessage("没有可清理的图片。\n剪贴板正在引用、最近 5 分钟生成、手动保存及无法确认来源的文件都会保留。")
                return
            }
            let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: plan.byteCount), countStyle: .file)
            let alert = NSAlert()
            alert.messageText = "将 \(plan.count) 张图片移入废纸篓？"
            alert.informativeText = "共 \(size)，来自 AprilShot 的“复制路径”文件夹。清理后，之前复制的这些路径将失效；可从废纸篓恢复。\n剪贴板正在引用及最近 5 分钟生成的图片会保留。另存到其他位置的文件不受影响。"
            if plan.legacyCount > 0 {
                alert.informativeText += "\n其中 \(plan.legacyCount) 张按旧版专用命名识别。"
            }
            alert.addButton(withTitle: "移入废纸篓")
            alert.addButton(withTitle: "取消")
            alert.buttons.first?.keyEquivalent = ""
            alert.buttons.last?.keyEquivalent = "\r"
            showingAlert = true
            NSApp.activate(ignoringOtherApps: true)
            let answer = alert.runModal()
            showingAlert = false
            guard answer == .alertFirstButtonReturn else { return }
            let result = try exportCleanup.run(plan)
            var message = "已将 \(result.movedCount) 张图片移入废纸篓。"
            if result.skippedCount > 0 { message += "\n\(result.skippedCount) 张图片因状态变化已保留。" }
            if !result.failures.isEmpty {
                message += "\n部分文件未能清理，请检查权限后重试。\n" + result.failures[0].message
            } else { didReportCleanupError = false }
            showMessage(message)
        } catch {
            showingAlert = false
            showMessage("清理未完成：" + error.localizedDescription)
        }
    }
    private func updateShortcutPresentation() {
        let shortcut = hotKey.activeShortcut
        captureItem.keyEquivalent = shortcut?.keyEquivalent ?? ""
        captureItem.keyEquivalentModifierMask = shortcut?.keyEquivalentModifierMask ?? []
        let hint = shortcut.map { " · " + $0.displayString } ?? " · 从菜单截图"
        statusItem.button?.toolTip = "AprilShot" + hint
        statusItem.button?.setAccessibilityHelp("截图" + hint)
    }
    @objc private func openSettings(_ sender: Any?) {
        guard !capturePending, !capture.isRunning, !showingAlert else { NSSound.beep(); return }
        if settingsController == nil {
            settingsController = SettingsWindowController(preferences: preferences,
                currentShortcut: { [weak self] in self?.hotKey.activeShortcut },
                apply: { [weak self] shortcut, days in
                    guard let self = self else { return }
                    guard AppPreferences.supportedRetentionDays.contains(days) else {
                        throw AppPreferences.PreferenceError.invalidRetention
                    }
                    try self.hotKey.register(shortcut)
                    try self.preferences.save(shortcut: shortcut, retentionDays: days)
                    self.updateShortcutPresentation()
                    // Wait until the settings window has dismissed before cleanup alerts.
                    DispatchQueue.main.async { [weak self] in self?.cleanExpiredImages() }
                })
        }
        settingsController?.present()
    }
    @objc private func showHelp(_ sender: Any?) {
        showMessage(StatusMenu.helpText(shortcut: hotKey.activeShortcut))
    }
    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.5"
        showMessage("AprilShot \(version)\n截图与标注，全在本机。")
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
