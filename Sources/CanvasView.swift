import AppKit

final class CanvasView: NSView, NSTextViewDelegate, NSUserInterfaceValidations {
    enum Tool: Int { case brush = 0, text = 1 }
    let image: CGImage
    private(set) var history = History<Annotation>()
    var tool: Tool = .brush { didSet { commitText(); window?.invalidateCursorRects(for: self) } }
    var color: NSColor = .systemRed
    var brushWidth: CGFloat = 6
    var textSize: CGFloat = 36
    var onChange: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCopy: (() -> Void)?
    private var stroke: BrushStroke?
    private var textEditor: NSTextView?
    private let textSessionUndoManager = UndoManager()
    private var editingRect = CGRect.zero
    private var editingTop: CGFloat = 0
    private var editingColor: NSColor = .systemRed
    private var editingFontSize: CGFloat = 36
    var isEditingText: Bool { textEditor != nil }
    var hasPendingContent: Bool { stroke != nil || !(textEditor?.string.isEmpty ?? true) }
    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var geometry: CanvasGeometry { CanvasGeometry(imageSize: imageSize, bounds: bounds, inset: 18) }
    override var acceptsFirstResponder: Bool { true }

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityLabel("截图标注画布")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() {
        addCursorRect(geometry.imageRect, cursor: tool == .brush ? .crosshair : .iBeam)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext, geometry.scale > 0 else { return }
        context.saveGState()
        context.translateBy(x: geometry.imageRect.minX, y: geometry.imageRect.minY)
        context.scaleBy(x: geometry.scale, y: geometry.scale)
        var annotations = history.items
        if let stroke = stroke { annotations.append(.brush(stroke)) }
        AnnotationRenderer.draw(image: image, annotations: annotations, in: context)
        context.restoreGState()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: geometry.imageRect).stroke()
    }
    override func layout() {
        super.layout()
        updateTextEditorFrame()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let imagePoint = geometry.imagePoint(from: point) else { return }
        switch tool {
        case .brush:
            stroke = BrushStroke(points: [imagePoint], color: color, width: brushWidth)
            needsDisplay = true
        case .text:
            beginText(at: imagePoint)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard stroke != nil,
              let point = geometry.imagePoint(from: convert(event.locationInWindow, from: nil), clamp: true) else { return }
        if let last = stroke?.points.last, hypot(point.x - last.x, point.y - last.y) < 0.5 { return }
        stroke?.points.append(point)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { finishStroke() }
    func finishStroke() {
        guard let stroke = stroke else { return }
        self.stroke = nil
        history.append(.brush(stroke))
        didChange()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil); return }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": tool = .brush; onChange?(); return
            case "t": tool = .text; onChange?(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if textEditor != nil {
            discardText()
        } else if stroke != nil {
            stroke = nil
            needsDisplay = true
        } else {
            onCancel?()
        }
    }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case Selector(("undo:")): return history.canUndo || hasPendingContent
        case Selector(("redo:")): return history.canRedo && !hasPendingContent
        case Selector(("copy:")): return true
        default: return false
        }
    }
    func undoManager(for view: NSTextView) -> UndoManager? { textSessionUndoManager }
    @objc(undo:) func undoViaResponder(_ sender: Any?) { undoAnnotation() }
    @objc(redo:) func redoViaResponder(_ sender: Any?) { redoAnnotation() }
    @objc(copy:) func copyViaResponder(_ sender: Any?) { onCopy?() }
    func undoAnnotation() { commitText(); finishStroke(); history.undo(); didChange() }
    func redoAnnotation() { commitText(); finishStroke(); history.redo(); didChange() }
    func exportPNG() throws -> Data {
        commitText()
        finishStroke()
        return try AnnotationRenderer.png(image: image, annotations: history.items)
    }
    private func didChange() { needsDisplay = true; onChange?() }

    private func beginText(at point: CGPoint) {
        textSessionUndoManager.removeAllActions()
        editingColor = color
        editingFontSize = textSize
        let width = min(imageSize.width, max(textSize * 4, min(520, imageSize.width - point.x)))
        let x = min(point.x, max(0, imageSize.width - width))
        let top = min(imageSize.height, max(point.y, min(imageSize.height, textSize * 1.6)))
        editingTop = top
        let height = min(top, textSize * 1.6)
        editingRect = CGRect(x: x, y: top - height, width: width, height: height)
        let editor = NSTextView(frame: .zero)
        editor.delegate = self
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = true
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.drawsBackground = true
        editor.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.94)
        editor.textColor = editingColor
        editor.insertionPointColor = .labelColor
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.borderWidth = 1
        editor.setAccessibilityLabel("输入标注文字，Command 加 Return 完成，Escape 放弃")
        textEditor = editor
        addSubview(editor)
        updateTextEditorFrame()
        window?.makeFirstResponder(editor)
        onChange?()
    }
    private func updateTextEditorFrame() {
        guard let editor = textEditor, geometry.scale > 0 else { return }
        let origin = geometry.viewPoint(from: editingRect.origin)
        editor.frame = CGRect(origin: origin,
                              size: CGSize(width: editingRect.width * geometry.scale,
                                           height: editingRect.height * geometry.scale))
        editor.font = .systemFont(ofSize: editingFontSize * geometry.scale, weight: .semibold)
    }
    func textDidChange(_ notification: Notification) {
        guard let editor = textEditor else { return }
        let value = NSAttributedString(string: editor.string + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: editingFontSize, weight: .semibold)
        ])
        let measured = value.boundingRect(with: CGSize(width: editingRect.width, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let height = min(editingTop, max(editingFontSize * 1.6, ceil(measured) + 4))
        editingRect.origin.y = editingTop - height
        editingRect.size.height = height
        updateTextEditorFrame()
        onChange?()
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) {
            discardText()
            return true
        }
        return false
    }
    func commitText() {
        guard let editor = textEditor else { return }
        // Unmark pending IME composition before exporting Chinese/Japanese input.
        editor.unmarkText()
        let value = editor.string
        textEditor = nil
        editor.delegate = nil
        editor.removeFromSuperview()
        textSessionUndoManager.removeAllActions()
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            history.append(.text(TextAnnotation(text: value, rect: editingRect,
                                                color: editingColor, fontSize: editingFontSize)))
        }
        window?.makeFirstResponder(self)
        didChange()
    }
    private func discardText() {
        let editor = textEditor
        textEditor = nil
        editor?.delegate = nil
        editor?.removeFromSuperview()
        textSessionUndoManager.removeAllActions()
        window?.makeFirstResponder(self)
        didChange()
    }
}
