import AppKit
import UniformTypeIdentifiers

final class EditorWindow: NSWindow {
    var handleShortcut: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleShortcut?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let canvas: CanvasView
    var onClose: (() -> Void)?
    private let toolControl = NSSegmentedControl(labels: ["画笔 B", "文字 T"], trackingMode: .selectOne, target: nil, action: nil)
    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider(value: 6, minValue: 1, maxValue: 32, target: nil, action: nil)
    private let fontPicker = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var exportedState: UUID?
    private var isPresentingSave = false
    private var statusReset: DispatchWorkItem?

    init(image: CGImage) {
        canvas = CanvasView(image: image)
        let window = EditorWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.title = "AprilShot · 标注截图"
        window.minSize = NSSize(width: 860, height: 520)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.handleShortcut = { [weak self] event in self?.handleShortcut(event) ?? false }
        buildInterface()
        canvas.onChange = { [weak self] in self?.updateControls() }
        canvas.onCopy = { [weak self] in self?.copyImage(nil) }
        canvas.onCancel = { [weak self] in self?.window?.performClose(nil) }
        updateControls()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }
    private func button(_ title: String, _ selector: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.bezelStyle = .rounded
        return button
    }
    private func buildInterface() {
        guard let content = window?.contentView else { return }
        toolControl.target = self
        toolControl.action = #selector(changeTool(_:))
        toolControl.selectedSegment = 0
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(changeColor(_:))
        colorWell.toolTip = "标注颜色"
        colorWell.widthAnchor.constraint(equalToConstant: 42).isActive = true
        widthSlider.target = self
        widthSlider.action = #selector(changeWidth(_:))
        widthSlider.toolTip = "画笔粗细：1–32 像素"
        widthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        fontPicker.addItems(withTitles: ["18", "24", "36", "48", "64", "96"])
        fontPicker.selectItem(withTitle: "36")
        fontPicker.target = self
        fontPicker.action = #selector(changeFont(_:))
        undoButton = button("撤销", #selector(undoAction(_:)))
        redoButton = button("重做", #selector(redoAction(_:)))
        undoButton.toolTip = "⌘Z"
        redoButton.toolTip = "⇧⌘Z"
        let copy = button("复制图片", #selector(copyImage(_:)))
        copy.toolTip = "⇧⌘C（文字输入时也可用）"
        let save = button("保存 PNG…", #selector(saveImage(_:)))
        save.toolTip = "⌘S"
        let toolbar = NSStackView(views: [toolControl, colorWell,
            NSTextField(labelWithString: "粗细"), widthSlider,
            NSTextField(labelWithString: "字号"), fontPicker,
            undoButton, redoButton, copy, save])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        let help = NSTextField(labelWithString: "拖动绘画 · 点击输入文字 · ⌘Return 完成文字 · Esc 取消 · 关闭窗口仍驻留菜单栏")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        for view in [toolbar, canvas, help, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: help.topAnchor, constant: -4),
            help.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            help.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),
            statusLabel.leadingAnchor.constraint(equalTo: help.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
    }
    private func updateControls() {
        undoButton.isEnabled = canvas.history.canUndo || canvas.hasPendingContent
        redoButton.isEnabled = canvas.history.canRedo && !canvas.hasPendingContent
        toolControl.selectedSegment = canvas.tool.rawValue
        window?.isDocumentEdited = exportedState != canvas.history.current.id || canvas.hasPendingContent
        if statusReset == nil {
            statusLabel.stringValue = "\(canvas.image.width) × \(canvas.image.height) px · 原始分辨率导出 · 颜色、粗细和字号仅影响新标注"
        }
    }
    private func feedback(_ text: String) {
        statusReset?.cancel()
        statusLabel.stringValue = text
        let work = DispatchWorkItem { [weak self] in
            self?.statusReset = nil
            self?.updateControls()
        }
        statusReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    @objc private func changeTool(_ sender: NSSegmentedControl) {
        canvas.tool = CanvasView.Tool(rawValue: sender.selectedSegment) ?? .brush
        updateControls()
    }
    @objc private func changeColor(_ sender: NSColorWell) { canvas.commitText(); canvas.color = sender.color }
    @objc private func changeWidth(_ sender: NSSlider) { canvas.brushWidth = CGFloat(sender.doubleValue) }
    @objc private func changeFont(_ sender: NSPopUpButton) {
        canvas.commitText()
        canvas.textSize = CGFloat(Double(sender.titleOfSelectedItem ?? "36") ?? 36)
    }
    @objc func undoAction(_ sender: Any?) { canvas.undoAnnotation() }
    @objc func redoAction(_ sender: Any?) { canvas.redoAnnotation() }

    @objc func copyImage(_ sender: Any?) {
        do {
            let png = try canvas.exportPNG()
            let pasteboard = NSPasteboard.general
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            if let bitmap = NSBitmapImageRep(data: png), let tiff = bitmap.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                showError("无法写入剪贴板，请重试。")
                return
            }
            exportedState = canvas.history.current.id
            updateControls()
            feedback("已复制图片，可直接粘贴到聊天或文档")
        } catch { showError(error.localizedDescription) }
    }
    @objc func saveImage(_ sender: Any?) {
        guard !isPresentingSave, let window = window else { return }
        do {
            let png = try canvas.exportPNG()
            let state = canvas.history.current.id
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            panel.nameFieldStringValue = "AprilShot_\(formatter.string(from: Date())).png"
            panel.title = "保存标注截图"
            isPresentingSave = true
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self else { return }
                self.isPresentingSave = false
                guard response == .OK, let url = panel.url else { return }
                do {
                    try png.write(to: url, options: .atomic)
                    self.exportedState = state
                    self.updateControls()
                    self.feedback("已保存：\(url.lastPathComponent)")
                } catch { self.showError("保存失败：\(error.localizedDescription)") }
            }
        } catch { showError(error.localizedDescription) }
    }
    private func handleShortcut(_ event: NSEvent) -> Bool {
        // Do not steal Command+C/Z/A from the inline text editor or any modal sheet.
        guard window?.attachedSheet == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command && event.keyCode == 36 {
            canvas.commitText(); return true
        }
        if modifiers == [.command, .shift] && key == "c" { copyImage(nil); return true }
        if modifiers == .command && key == "w" { window?.performClose(nil); return true }
        if modifiers == .command && key == "s" { saveImage(nil); return true }
        if !canvas.isEditingText {
            if modifiers == .command && key == "c" { copyImage(nil); return true }
            if modifiers == .command && key == "z" { undoAction(nil); return true }
            if modifiers == [.command, .shift] && key == "z" { redoAction(nil); return true }
        }
        return false
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.commitText()
        canvas.finishStroke()
        guard exportedState != canvas.history.current.id else { return true }
        let alert = NSAlert()
        alert.messageText = "关闭这张截图？"
        alert.informativeText = "当前版本尚未复制或保存。关闭后无法恢复。"
        alert.addButton(withTitle: "继续编辑")
        alert.addButton(withTitle: "放弃截图")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        statusReset?.cancel()
        onClose?()
    }
    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "AprilShot"
        alert.informativeText = text
        alert.alertStyle = .warning
        if let window = window { alert.beginSheetModal(for: window) }
    }
}
