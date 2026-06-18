import AppKit

/// A custom-drawn on/off pill. We draw it ourselves (with an explicit blue fill
/// and `allowsVibrancy = false`) because a real NSSwitch renders desaturated/gray
/// inside a menu's vibrant, non-key context.
final class PillSwitch: NSView {
    var isOn: Bool = false { didSet { needsDisplay = true } }

    override var allowsVibrancy: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }

    private let onColor = NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // #007AFF
    private let offColor = NSColor(white: 0.5, alpha: 0.45)

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds.insetBy(dx: 1, dy: 1)
        let r = b.height / 2
        (isOn ? onColor : offColor).setFill()
        NSBezierPath(roundedRect: b, xRadius: r, yRadius: r).fill()

        let knobD = b.height - 4
        let knobX = isOn ? b.maxX - knobD - 2 : b.minX + 2
        let knobRect = NSRect(x: knobX, y: b.minY + 2, width: knobD, height: knobD)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A custom menu-item view: an SF Symbol, a label, and the pill toggle on the
/// right. Clicking anywhere on the row toggles it.
final class ToggleMenuView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let pill = PillSwitch()
    private var isOn: Bool
    var onChange: ((Bool) -> Void)?

    init(title: String, isOn: Bool, symbol: String) {
        self.isOn = isOn
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
        autoresizingMask = [.width] // stretch to the menu width; pill pins right

        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        pill.isOn = isOn
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 40),
            pill.heightAnchor.constraint(equalToConstant: 24),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        pill.isOn = isOn
        label.stringValue = isOn ? "Connected" : "Disconnected"
        onChange?(isOn)
    }
}
