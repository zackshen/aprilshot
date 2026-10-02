import AppKit

/// Native controls remain responsible for focus, keyboard activation and
/// accessibility. Only their compact toolbar backgrounds are customized.
final class EditorToolbarButton: NSButton {
    enum Emphasis { case plain, tool, primary }
    var emphasis: Emphasis = .plain { didSet { refreshAppearance() } }
    private var hovered = false
    private var hoverTracking: NSTrackingArea?

    init(title: String, symbol: String, label: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title.isEmpty ? "" : "\u{2009}" + title
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        bezelStyle = .regularSquare
        isBordered = false
        focusRingType = .exterior
        font = .systemFont(ofSize: 12, weight: .medium)
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        imageHugsTitle = true
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        if let hoverTracking = hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
                                     options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                     owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override var state: NSControl.StateValue { didSet { refreshAppearance() } }
    override var isEnabled: Bool { didSet { refreshAppearance() } }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
    func setCaption(_ text: String) {
        title = text.isEmpty ? "" : "\u{2009}" + text
        refreshAppearance()
    }
    private func refreshAppearance() {
        let selected = emphasis == .tool && state == .on
        let primary = emphasis == .primary
        let tint: NSColor = primary ? .white : (selected ? .controlAccentColor : .labelColor)
        contentTintColor = isEnabled ? tint : .disabledControlTextColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected || primary ? .semibold : .medium),
            .foregroundColor: isEnabled ? tint : .disabledControlTextColor
        ])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let selected = emphasis == .tool && state == .on
        let primary = emphasis == .primary
        let fill: NSColor
        if primary {
            fill = isHighlighted
                ? (NSColor.controlAccentColor.blended(withFraction: 0.16, of: .black) ?? .controlAccentColor)
                : .controlAccentColor
        } else if selected {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.16)
        } else if hovered && isEnabled {
            fill = NSColor.labelColor.withAlphaComponent(0.07)
        } else {
            fill = .clear
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).fill()
        super.draw(dirtyRect)
    }
}

final class EditorToolbarSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

/// The tool switch is a quiet, rounded group rather than a row of unrelated
/// default push buttons. Dynamic system colors follow light/dark appearance.
final class EditorToolGroup: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }
}
