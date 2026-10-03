import AppKit

/// One reusable settings window. Edits are staged until Save; closing or Cancel
/// never changes registration or preferences.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: AppPreferences
    private let currentShortcut: () -> HotKeyShortcut?
    private let apply: (HotKeyShortcut, Int) throws -> Void
    let keyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let retentionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let preview = NSTextField(labelWithString: "")
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let saveButton = NSButton(title: "保存", target: nil, action: nil)
    let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    let resetButton = NSButton(title: "恢复默认", target: nil, action: nil)
    private(set) var modifierButtons: [(HotKeyModifiers, NSButton)] = []
    static let retentionOptions = [(3, "保留最近 3 天（默认）"), (1, "保留最近 1 天"),
                                   (7, "保留最近 7 天"), (30, "保留最近 30 天"), (0, "不自动清理")]

    init(preferences: AppPreferences,
         currentShortcut: @escaping () -> HotKeyShortcut?,
         apply: @escaping (HotKeyShortcut, Int) throws -> Void) {
        self.preferences = preferences
        self.currentShortcut = currentShortcut
        self.apply = apply
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 508),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AprilShot 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        reload()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat = 13, color: NSColor = .labelColor,
                       bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        field.textColor = color
        return field
    }
    private func buildContent() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])
        func fullWidth(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        fullWidth(label("截图快捷键", size: 15, bold: true))
        let modifiers = NSStackView()
        modifiers.orientation = .horizontal
        modifiers.alignment = .centerY
        modifiers.distribution = .equalSpacing
        modifiers.spacing = 16
        for (flag, title) in [(HotKeyModifiers.command, "⌘ Command"), (.shift, "⇧ Shift"),
                              (.option, "⌥ Option"), (.control, "⌃ Control")] {
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(updatePreview(_:)))
            button.identifier = NSUserInterfaceItemIdentifier("settings.modifier.\(flag.rawValue)")
            modifierButtons.append((flag, button))
            modifiers.addArrangedSubview(button)
        }
        fullWidth(modifiers)
        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 12
        shortcutRow.addArrangedSubview(label("按键"))
        for key in HotKeyShortcut.supportedKeys {
            keyPopup.addItem(withTitle: key.displayName)
            keyPopup.lastItem?.tag = Int(key.keyCode)
        }
        keyPopup.target = self
        keyPopup.action = #selector(updatePreview(_:))
        keyPopup.identifier = NSUserInterfaceItemIdentifier("settings.key")
        keyPopup.translatesAutoresizingMaskIntoConstraints = false
        keyPopup.widthAnchor.constraint(equalToConstant: 96).isActive = true
        shortcutRow.addArrangedSubview(keyPopup)
        preview.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        preview.setContentHuggingPriority(.required, for: .horizontal)
        preview.identifier = NSUserInterfaceItemIdentifier("settings.shortcutPreview")
        shortcutRow.addArrangedSubview(preview)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        shortcutRow.addArrangedSubview(spacer)
        resetButton.target = self
        resetButton.action = #selector(resetShortcut(_:))
        resetButton.bezelStyle = .rounded
        shortcutRow.addArrangedSubview(resetButton)
        fullWidth(shortcutRow)
        fullWidth(label("至少选择两个修饰键，含 Command 或 Control。按键按美式键盘位置识别。", size: 12, color: .secondaryLabelColor))
        let separator = NSBox()
        separator.boxType = .separator
        fullWidth(separator)
        stack.setCustomSpacing(18, after: separator)
        fullWidth(label("图片清理", size: 15, bold: true))
        for (days, title) in Self.retentionOptions {
            retentionPopup.addItem(withTitle: title)
            retentionPopup.lastItem?.tag = days
        }
        retentionPopup.identifier = NSUserInterfaceItemIdentifier("settings.retention")
        fullWidth(retentionPopup)
        fullWidth(label("每天按实际时长计算；过期图片会移入废纸篓，原路径将失效。仅清理“复制路径”生成的图片。另存到其他位置、剪贴板正在引用及最近 5 分钟的图片不受影响。", size: 12, color: .secondaryLabelColor))
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.identifier = NSUserInterfaceItemIdentifier("settings.error")
        errorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        fullWidth(errorLabel)
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(footerSpacer)
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.identifier = NSUserInterfaceItemIdentifier("settings.cancel")
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.identifier = NSUserInterfaceItemIdentifier("settings.save")
        for button in [cancelButton, saveButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 80).isActive = true
            footer.addArrangedSubview(button)
        }
        fullWidth(footer)
        stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20).isActive = true
    }

    func present() {
        if window?.isVisible != true { reload() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    func reload() {
        selectShortcut(currentShortcut() ?? preferences.shortcut)
        retentionPopup.selectItem(withTag: preferences.retentionDays)
        errorLabel.stringValue = preferences.loadWarning ?? ""
    }
    private func selectShortcut(_ shortcut: HotKeyShortcut) {
        keyPopup.selectItem(withTag: Int(shortcut.keyCode))
        for (flag, button) in modifierButtons {
            button.state = shortcut.modifiers.contains(flag) ? .on : .off
        }
        updatePreview(nil)
    }
    private func candidateShortcut() throws -> HotKeyShortcut {
        var modifiers: HotKeyModifiers = []
        for (flag, button) in modifierButtons where button.state == .on { modifiers.insert(flag) }
        return try HotKeyShortcut(keyCode: UInt32(keyPopup.selectedTag()), modifiers: modifiers)
    }
    @objc private func updatePreview(_ sender: Any?) {
        do {
            preview.stringValue = try candidateShortcut().displayString
            errorLabel.stringValue = ""
            saveButton.isEnabled = true
        } catch {
            preview.stringValue = "请选择有效快捷键"
            errorLabel.stringValue = error.localizedDescription
            saveButton.isEnabled = false
        }
    }
    @objc private func resetShortcut(_ sender: Any?) { selectShortcut(.default) }
    @objc private func cancel(_ sender: Any?) { close() }
    @objc private func save(_ sender: Any?) {
        do {
            let shortcut = try candidateShortcut()
            let days = retentionPopup.selectedTag()
            try apply(shortcut, days)
            close()
        } catch {
            errorLabel.stringValue = error.localizedDescription
        }
    }
}
