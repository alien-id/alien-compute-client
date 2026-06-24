import AppKit

private let accentColor = NSColor(srgbRed: 0.30, green: 0.85, blue: 1.0, alpha: 1.0) // neon cyan
private let columnWidth: CGFloat = 320  // text column
private let windowWidth: CGFloat = 420  // → 50pt side margins
private let vPad: CGFloat = 30           // top/bottom padding

// MARK: - Black gradient + starfield background

final class GradientBackgroundView: NSView {
    override var allowsVibrancy: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [
            NSColor(srgbRed: 0.10, green: 0.07, blue: 0.21, alpha: 1), // deep indigo
            NSColor(srgbRed: 0.02, green: 0.02, blue: 0.05, alpha: 1), // near black
        ])!.draw(in: bounds, angle: -90)

        NSColor(white: 1, alpha: 0.85).setFill()
        let stars: [(CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.88, 1.2), (0.20, 0.74, 0.8), (0.82, 0.92, 1.4), (0.90, 0.66, 1.0),
            (0.70, 0.82, 0.8), (0.13, 0.40, 0.8), (0.88, 0.30, 1.0), (0.52, 0.96, 0.9),
            (0.33, 0.90, 0.7), (0.63, 0.93, 0.8), (0.95, 0.80, 0.9), (0.06, 0.58, 0.7),
        ]
        for (fx, fy, r) in stars {
            let c = NSPoint(x: bounds.minX + fx * bounds.width, y: bounds.minY + fy * bounds.height)
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
}

// MARK: - Glowing accent button

final class NeonButton: NSView {
    var onClick: (() -> Void)?
    var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var isEnabledState = true { didSet { needsDisplay = true } }
    private let font = NSFont.systemFont(ofSize: 15, weight: .semibold)

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var allowsVibrancy: Bool { false }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(w) + 48, height: 40)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(rect: r)

        NSGraphicsContext.saveGraphicsState()
        if isEnabledState {
            let glow = NSShadow()
            glow.shadowColor = accentColor.withAlphaComponent(0.85)
            glow.shadowBlurRadius = 6
            glow.shadowOffset = .zero
            glow.set()
        }
        (isEnabledState ? accentColor : NSColor(white: 0.28, alpha: 1)).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isEnabledState ? NSColor.black : NSColor(white: 0.6, alpha: 1),
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                                 withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { if isEnabledState { onClick?() } }
}

// MARK: - Onboarding window

final class OnboardingController: NSObject, NSWindowDelegate {
    private let proxy: ProxyManager
    private let onFinish: () -> Void

    private var window: NSWindow!
    private var stack: NSStackView!
    private var terminal: AlienTerminalView!
    private var connectButton: NeonButton!
    private var spinner: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var urlStack: NSStackView!
    private var urlField: NSTextField!
    private var doneButton: NeonButton!

    private var pollTimer: Timer?
    private var deadline = Date.distantPast
    private var finished = false

    init(proxy: ProxyManager, onFinish: @escaping () -> Void) {
        self.proxy = proxy
        self.onFinish = onFinish
        super.init()
        buildWindow()
    }

    func show() {
        NSApp.setActivationPolicy(.regular) // real, focusable window during onboarding
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = .black
        w.delegate = self
        w.contentView = GradientBackgroundView()
        window = w

        // Small glowing logo above the live alien terminal.
        let logo = NSImageView(image: Saucer.iconImage(64))
        logo.wantsLayer = true
        logo.shadow = {
            let s = NSShadow()
            s.shadowColor = accentColor.withAlphaComponent(0.4)
            s.shadowBlurRadius = 4
            s.shadowOffset = .zero
            return s
        }()
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 64).isActive = true

        // Animated Marain-nonary "Culture terminal".
        terminal = AlienTerminalView()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
        terminal.heightAnchor.constraint(equalToConstant: terminal.intrinsicContentSize.height).isActive = true

        let title = NSTextField(labelWithAttributedString: NSAttributedString(
            string: "ALIEN COMPUTE",
            attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .heavy),
                         .foregroundColor: NSColor.white, .kern: 4.0]))

        let tagline = NSTextField(labelWithAttributedString: NSAttributedString(
            string: "CONFIDENTIAL DISTRIBUTED INFERENCE",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: accentColor, .kern: 2.5]))

        let desc = NSTextField(wrappingLabelWithString:
            "A private AI endpoint on your Mac, powered by a decentralized GPU network.")
        desc.alignment = .center
        desc.font = .systemFont(ofSize: 13)
        desc.textColor = NSColor(white: 0.72, alpha: 1)
        desc.preferredMaxLayoutWidth = columnWidth

        connectButton = NeonButton(title: "Connect to network")
        connectButton.onClick = { [weak self] in self?.connectTapped() }

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 16).isActive = true

        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = NSColor(white: 0.72, alpha: 1)
        statusLabel.preferredMaxLayoutWidth = columnWidth
        let statusRow = NSStackView(views: [spinner, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8

        let urlTitle = NSTextField(labelWithString: "OPENAI-COMPATIBLE ENDPOINT")
        urlTitle.font = .systemFont(ofSize: 10, weight: .semibold)
        urlTitle.textColor = NSColor(white: 0.55, alpha: 1)

        urlField = NSTextField(string: proxy.apiBase)
        urlField.isEditable = false
        urlField.isSelectable = true
        urlField.isBezeled = false
        urlField.drawsBackground = true
        urlField.backgroundColor = NSColor(white: 1, alpha: 0.07)
        urlField.textColor = accentColor
        urlField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        urlField.alignment = .center
        urlField.wantsLayer = true
        urlField.layer?.cornerRadius = 0
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let copyButton = NeonButton(title: "Copy URL")
        copyButton.onClick = { [weak self] in self?.copyTapped() }

        urlStack = NSStackView(views: [urlTitle, urlField, copyButton])
        urlStack.orientation = .vertical
        urlStack.alignment = .centerX
        urlStack.spacing = 8
        urlStack.isHidden = true

        doneButton = NeonButton(title: "Done")
        doneButton.onClick = { [weak self] in self?.doneTapped() }
        doneButton.isHidden = true

        stack = NSStackView(views: [logo, terminal, title, tagline, desc, connectButton, statusRow, urlStack, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(14, after: logo)
        stack.setCustomSpacing(18, after: terminal)
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(22, after: desc)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Fixed-width text column centered in a fixed-width window → guaranteed
        // side margins (windowWidth - columnWidth)/2 regardless of text.
        let content = w.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: columnWidth),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: vPad),
        ])

        resizeWindowToFit(animated: false)
    }

    /// Keep a fixed width; size the height to the content column (grow downward).
    private func resizeWindowToFit(animated: Bool) {
        window.layoutIfNeeded()
        let height = vPad + stack.fittingSize.height + vPad
        let newFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: windowWidth, height: height))
        var f = window.frame
        f.origin.y += f.height - newFrame.height
        f.size = newFrame.size
        window.setFrame(f, display: true, animate: animated)
    }

    // MARK: Connect flow

    private func connectTapped() {
        connectButton.isEnabledState = false
        statusLabel.stringValue = "Connecting to the network…"
        statusLabel.textColor = NSColor(white: 0.72, alpha: 1)
        spinner.startAnimation(nil)
        urlStack.isHidden = true

        proxy.start()
        deadline = Date().addingTimeInterval(20)
        pollTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        guard !finished else { return }
        // The proxy only serves /healthz after reaching a gateway and opening a
        // channel, so a 200 here means we're connected.
        guard let url = URL(string: "http://127.0.0.1:\(proxy.listenPort)/healthz") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            DispatchQueue.main.async {
                guard let self = self, !self.finished else { return }
                if (resp as? HTTPURLResponse)?.statusCode == 200 {
                    self.connected()
                } else if !self.proxy.isRunning || Date() > self.deadline {
                    self.failed()
                }
            }
        }.resume()
    }

    private func connected() {
        pollTimer?.invalidate(); pollTimer = nil
        spinner.stopAnimation(nil)
        statusLabel.stringValue = "Connected ✓  ·  wallet created"
        statusLabel.textColor = .systemGreen
        connectButton.isHidden = true
        urlField.stringValue = proxy.apiBase
        urlStack.isHidden = false
        doneButton.isHidden = false
        resizeWindowToFit(animated: true)
        showFundedBalance()
    }

    /// Fetch the freshly-funded balance and show it (proof the faucet granted).
    private func showFundedBalance() {
        guard let url = URL(string: "http://127.0.0.1:\(proxy.listenPort)/fleet/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let st = try? JSONDecoder().decode(FleetStatus.self, from: data) else { return }
            let wallet = tokenValue(st.wallet_balance) ?? 0
            let dep = tokenValue(st.channel_deposit) ?? 0
            let spent = tokenValue(st.channel_spent) ?? 0
            let usd = tokenToUSDC(wallet + max(0, dep - spent))
            DispatchQueue.main.async {
                guard let self = self, !self.finished else { return }
                self.statusLabel.stringValue = "Connected ✓  ·  wallet funded with \(fmtUSD(usd))"
            }
        }.resume()
    }

    private func failed() {
        pollTimer?.invalidate(); pollTimer = nil
        spinner.stopAnimation(nil)
        statusLabel.stringValue = "Network unavailable — couldn't reach the gateway. "
            + "Try again now, or later from the menu bar."
        statusLabel.textColor = .systemRed
        connectButton.title = "Try again"
        connectButton.isEnabledState = true
        doneButton.isHidden = false
        proxy.stop()
        resizeWindowToFit(animated: true)
    }

    @objc private func copyTapped() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(proxy.apiBase, forType: .string)
    }

    @objc private func doneTapped() { window.close() }

    func windowWillClose(_ notification: Notification) { finish() }

    private func finish() {
        guard !finished else { return }
        finished = true
        pollTimer?.invalidate()
        terminal?.stopAnimating()
        UserDefaults.standard.set(true, forKey: "didOnboard")
        NSApp.setActivationPolicy(.accessory) // back to menu-bar-only
        onFinish()
    }
}
