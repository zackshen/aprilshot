import AppKit

@main
struct SettingsWindowTests {
    static var checks = 0
    static var failures = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    static func render(_ controller: SettingsWindowController, name: String,
                       appearance: NSAppearance.Name) throws {
        let window = controller.window!
        window.appearance = NSAppearance(named: appearance)
        let content = window.contentView!
        content.appearance = window.appearance
        func invalidate(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(invalidate)
        }
        invalidate(content)
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.cacheDisplay(in: content.bounds, to: bitmap)
        }
        let background = bitmap.colorAt(x: 0, y: 0)!
        check(background.alphaComponent > 0.99, "\(name): settings screenshot includes opaque native background")
        check(appearance == .darkAqua ? background.redComponent < 0.3 : background.redComponent > 0.8,
              "\(name): native background follows requested light/dark appearance")
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APRILSHOT_TEST_ARTIFACTS"] ?? ".build/rendering-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("settings-\(name).png"))
        check(bitmap.pixelsWide >= 548 && bitmap.pixelsHigh >= 376, "\(name): native settings screenshot has full dimensions")
        for control in [controller.keyPopup, controller.retentionPopup, controller.preview,
                        controller.errorLabel, controller.saveButton, controller.cancelButton, controller.resetButton] as [NSView] {
            let rect = control.convert(control.bounds, to: content)
            check(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= content.bounds.width + 1 && rect.maxY <= content.bounds.height + 1,
                  "\(name): \(control.identifier?.rawValue ?? "control") fits inside window")
            check(rect.width > 10 && rect.height > 10, "\(name): control is visible with usable dimensions")
        }
        let saveFrame = controller.saveButton.convert(controller.saveButton.bounds, to: content)
        let errorFrame = controller.errorLabel.convert(controller.errorLabel.bounds, to: content)
        check(!saveFrame.intersects(errorFrame), "\(name): error and save controls do not overlap")
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "AprilShot.SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPreferences(defaults: defaults)
        var active = HotKeyShortcut.default
        var saves = 0
        var failure = false
        let controller = SettingsWindowController(preferences: prefs, currentShortcut: { active }) { shortcut, days in
            saves += 1
            if failure { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "快捷键与其他应用冲突。原快捷键保持不变，请选择其他组合。"] ) }
            active = shortcut
            try prefs.save(shortcut: shortcut, retentionDays: days)
        }
        check(controller.retentionPopup.selectedTag() == 3, "retention defaults to three days")
        check(controller.preview.stringValue == HotKeyShortcut.default.displayString, "default active shortcut shown")
        check(controller.keyPopup.itemArray.count == HotKeyShortcut.supportedKeys.count, "every supported key has a choice")
        check(Set(controller.retentionPopup.itemArray.map { $0.tag }) == Set([0, 1, 3, 7, 30]), "clear finite retention policies plus never")
        for (_, button) in controller.modifierButtons { button.state = .off }
        _ = NSApp.sendAction(controller.keyPopup.action!, to: controller.keyPopup.target, from: controller.keyPopup)
        check(!controller.saveButton.isEnabled && !controller.errorLabel.stringValue.isEmpty, "unmodified shortcut cannot be saved")
        controller.resetButton.performClick(nil)
        check(controller.saveButton.isEnabled && controller.preview.stringValue == HotKeyShortcut.default.displayString, "restore default repairs invalid form")
        check(saves == 0, "editing and resetting never applies settings")
        controller.retentionPopup.selectItem(withTag: 7)
        controller.cancelButton.performClick(nil)
        controller.reload()
        check(controller.retentionPopup.selectedTag() == 3 && prefs.retentionDays == 3 && saves == 0, "cancel discards all staged preference changes")
        controller.retentionPopup.selectItem(withTag: 30)
        failure = true
        controller.saveButton.performClick(nil)
        check(saves == 1 && prefs.retentionDays == 3 && active == .default, "registration failure retains old shortcut and retention")
        check(controller.errorLabel.stringValue.contains("冲突"), "conflict is shown without closing the settings window")
        try render(controller, name: "conflict-light", appearance: .aqua)
        failure = false
        controller.saveButton.performClick(nil)
        check(saves == 2 && prefs.retentionDays == 30, "retry saves after conflict resolves")
        controller.reload()
        check(controller.retentionPopup.selectedTag() == 30 && controller.errorLabel.stringValue.isEmpty, "reopen shows saved settings without stale errors")
        for _ in 0..<3 {
            controller.present()
            controller.retentionPopup.selectItem(withTag: 7)
            controller.present()
            check(controller.retentionPopup.selectedTag() == 7, "repeated Settings action preserves visible staged edits")
            controller.close()
            controller.present()
            check(controller.retentionPopup.selectedTag() == 30, "reopening closed window reloads saved settings")
            controller.close()
        }
        controller.reload()
        try render(controller, name: "light", appearance: .aqua)
        try render(controller, name: "dark", appearance: .darkAqua)
        controller.close()
        print("Settings window tests: \(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
