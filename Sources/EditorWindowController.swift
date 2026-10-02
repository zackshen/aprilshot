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
    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider(value: 6, minValue: 1, maxValue: 32, target: nil, action: nil)
    private let fontPicker = NSPopUpButton()
    private let widthValue = NSTextField(labelWithString: "6 px")
    private let brushSettings = NSView()
    private let textSettings = NSView()
    private var brushButton: EditorToolbarButton!
    private var textButton: EditorToolbarButton!
    private var undoButton: EditorToolbarButton!
    private var redoButton: EditorToolbarButton!
    private var copyButton: EditorToolbarButton!
    private var saveButton: EditorToolbarButton!
    private var exportedState: UUID?
    private var isPresentingSave = false
    private var feedbackReset: DispatchWorkItem?

    init(image: CGImage) {
        canvas = CanvasView(image: image)
        let window = EditorWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        window.title = "AprilShot · 标注截图"
        window.minSize = NSSize(width: 860, height: 520)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
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
    private func button(_ title: String, symbol: String, label: String, identifier: String,
                        width: CGFloat, selector: Selector) -> EditorToolbarButton {
        let button = EditorToolbarButton(title: title, symbol: symbol, label: label, target: self, action: selector)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        return button
    }
    private func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }
    private func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }
    private func buildInterface() {
        guard let content = window?.contentView else { return }
        brushButton = button("画笔", symbol: "paintbrush.pointed", label: "画笔", identifier: "editor.tools.brush",
                             width: 68, selector: #selector(changeTool(_:)))
        textButton = button("文字", symbol: "textformat", label: "文字", identifier: "editor.tools.text",
                            width: 68, selector: #selector(changeTool(_:)))
        brushButton.tag = CanvasView.Tool.brush.rawValue
        textButton.tag = CanvasView.Tool.text.rawValue
        for tool in [brushButton!, textButton!] {
            tool.setButtonType(.pushOnPushOff)
            tool.setAccessibilityRole(.radioButton)
            tool.emphasis = .tool
        }
        brushButton.toolTip = "画笔（B）· 在截图上拖动绘画"
        textButton.toolTip = "文字（T）· 点击截图输入，⌘Return 完成，Esc 取消"
        let tools = EditorToolGroup()
        tools.translatesAutoresizingMaskIntoConstraints = false
        let toolRow = row([brushButton, textButton], spacing: 2)
        tools.addSubview(toolRow)
        NSLayoutConstraint.activate([
            toolRow.leadingAnchor.constraint(equalTo: tools.leadingAnchor, constant: 3),
            toolRow.trailingAnchor.constraint(equalTo: tools.trailingAnchor, constant: -3),
            toolRow.topAnchor.constraint(equalTo: tools.topAnchor, constant: 3),
            toolRow.bottomAnchor.constraint(equalTo: tools.bottomAnchor, constant: -3)
        ])

        colorWell.color = .systemRed
        colorWell.colorWellStyle = .minimal
        colorWell.target = self
        colorWell.action = #selector(changeColor(_:))
        colorWell.identifier = NSUserInterfaceItemIdentifier("editor.color")
        colorWell.toolTip = "标注颜色 · 仅影响新标注"
        colorWell.setAccessibilityLabel("标注颜色")
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 28),
            colorWell.heightAnchor.constraint(equalToConstant: 28)
        ])
        widthSlider.target = self
        widthSlider.action = #selector(changeWidth(_:))
        widthSlider.identifier = NSUserInterfaceItemIdentifier("editor.brush.width")
        widthSlider.toolTip = "画笔粗细：1–32 像素 · 仅影响新笔画"
        widthSlider.setAccessibilityLabel("画笔粗细（像素）")
        widthSlider.controlSize = .small
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.widthAnchor.constraint(equalToConstant: 84).isActive = true
        widthValue.identifier = NSUserInterfaceItemIdentifier("editor.brush.value")
        widthValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        widthValue.textColor = .secondaryLabelColor
        widthValue.alignment = .right
        widthValue.translatesAutoresizingMaskIntoConstraints = false
        widthValue.widthAnchor.constraint(equalToConstant: 34).isActive = true
        fontPicker.addItems(withTitles: ["18", "24", "36", "48", "64", "96"])
        fontPicker.selectItem(withTitle: "36")
        fontPicker.target = self
        fontPicker.action = #selector(changeFont(_:))
        fontPicker.identifier = NSUserInterfaceItemIdentifier("editor.text.size")
        fontPicker.toolTip = "文字大小 · 按原图像素，仅影响新文字"
        fontPicker.setAccessibilityLabel("文字大小（像素）")
        fontPicker.controlSize = .small
        fontPicker.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        fontPicker.translatesAutoresizingMaskIntoConstraints = false
        fontPicker.widthAnchor.constraint(equalToConstant: 72).isActive = true
        brushSettings.identifier = NSUserInterfaceItemIdentifier("editor.settings.brush")
        textSettings.identifier = NSUserInterfaceItemIdentifier("editor.settings.text")
        let settings = NSView()
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.widthAnchor.constraint(equalToConstant: 168).isActive = true
        settings.heightAnchor.constraint(equalToConstant: 32).isActive = true
        for (container, controls) in [(brushSettings, row([label("粗细"), widthSlider, widthValue], spacing: 7)),
                                      (textSettings, row([label("字号"), fontPicker, label("px")], spacing: 8))] {
            container.translatesAutoresizingMaskIntoConstraints = false
            settings.addSubview(container)
            container.addSubview(controls)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: settings.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: settings.trailingAnchor),
                container.topAnchor.constraint(equalTo: settings.topAnchor),
                container.bottomAnchor.constraint(equalTo: settings.bottomAnchor),
                controls.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                controls.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }
        undoButton = button("", symbol: "arrow.uturn.backward", label: "撤销", identifier: "editor.history.undo",
                            width: 32, selector: #selector(undoAction(_:)))
        redoButton = button("", symbol: "arrow.uturn.forward", label: "重做", identifier: "editor.history.redo",
                            width: 32, selector: #selector(redoAction(_:)))
        undoButton.toolTip = "撤销（⌘Z）"
        redoButton.toolTip = "重做（⇧⌘Z）"
        copyButton = button("复制", symbol: "doc.on.doc", label: "复制图片", identifier: "editor.export.copy",
                            width: 78, selector: #selector(copyImage(_:)))
        copyButton.emphasis = .primary
        copyButton.toolTip = "复制图片（⇧⌘C）· 文字输入时也可用"
        saveButton = button("保存", symbol: "square.and.arrow.down", label: "保存 PNG", identifier: "editor.export.save",
                            width: 78, selector: #selector(saveImage(_:)))
        saveButton.toolTip = "保存 PNG…（⌘S）"
        let editing = row([tools, separator(), colorWell, settings], spacing: 14)
        let actions = row([row([undoButton, redoButton], spacing: 2), separator(), saveButton, copyButton], spacing: 10)
        let toolbar = EditorToolbarSurface()
        toolbar.identifier = NSUserInterfaceItemIdentifier("editor.toolbar")
        toolbar.setAccessibilityLabel("截图标注工具栏")
        for view in [toolbar, canvas] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        toolbar.addSubview(editing)
        toolbar.addSubview(actions)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 62),
            editing.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            editing.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            actions.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: editing.trailingAnchor, constant: 20),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }
    private func updateControls() {
        undoButton.isEnabled = canvas.history.canUndo || canvas.hasPendingContent
        redoButton.isEnabled = canvas.history.canRedo && !canvas.hasPendingContent
        let isBrush = canvas.tool == .brush
        brushButton.state = isBrush ? .on : .off
        textButton.state = isBrush ? .off : .on
        brushButton.setAccessibilityValue(isBrush ? 1 : 0)
        textButton.setAccessibilityValue(isBrush ? 0 : 1)
        brushSettings.isHidden = !isBrush
        textSettings.isHidden = isBrush
        widthValue.stringValue = "\(Int(canvas.brushWidth.rounded())) px"
        window?.isDocumentEdited = exportedState != canvas.history.current.id || canvas.hasPendingContent
    }
    private func feedback(on button: EditorToolbarButton, title: String) {
        feedbackReset?.cancel()
        copyButton.setCaption("复制")
        saveButton.setCaption("保存")
        button.setCaption(title)
        NSAccessibility.post(element: button, notification: .announcementRequested,
                             userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        let work = DispatchWorkItem { [weak self] in
            self?.copyButton.setCaption("复制")
            self?.saveButton.setCaption("保存")
            self?.feedbackReset = nil
        }
        feedbackReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
    @objc private func changeTool(_ sender: NSButton) {
        canvas.tool = CanvasView.Tool(rawValue: sender.tag) ?? .brush
        updateControls()
        window?.makeFirstResponder(canvas)
    }
    @objc private func changeColor(_ sender: NSColorWell) { canvas.commitText(); canvas.color = sender.color }
    @objc private func changeWidth(_ sender: NSSlider) {
        canvas.brushWidth = CGFloat(sender.doubleValue.rounded())
        updateControls()
    }
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
            feedback(on: copyButton, title: "已复制")
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
                    self.feedback(on: self.saveButton, title: "已保存")
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
        feedbackReset?.cancel()
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
