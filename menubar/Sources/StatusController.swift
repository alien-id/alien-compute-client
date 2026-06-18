import AppKit

final class StatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let proxy: ProxyManager
    private let client = FleetClient()
    private var timer: Timer?

    private var lastStatus: FleetStatus?
    private var lastCapacity: Capacity?
    private var healthy = false

    init(proxy: ProxyManager) {
        self.proxy = proxy
        super.init()
        client.port = proxy.listenPort
        configureButton()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        startTimer()
    }

    // MARK: - Status bar button

    private func configureButton() {
        guard let b = statusItem.button else { return }
        b.image = Saucer.menuBarImage()
        b.imagePosition = .imageLeading
        b.title = " …"
    }

    private func updateButton() {
        guard let b = statusItem.button else { return }
        if !proxy.isRunning {
            b.title = " off"
        } else if !healthy {
            b.title = " …"
        } else if let st = lastStatus, let bal = balanceTokens(st) {
            b.title = " " + fmtUSD(tokenToUSDC(bal))
        } else {
            b.title = " …"
        }
    }

    /// Total available balance (internal token) = unescrowed wallet + remaining
    /// escrowed funds. Escrowed funds are still the user's money, so we fold them
    /// in now that the channel line is hidden.
    private func balanceTokens(_ st: FleetStatus) -> Double? {
        guard let wallet = tokenValue(st.wallet_balance) else { return nil }
        let dep = tokenValue(st.channel_deposit) ?? 0
        let spent = tokenValue(st.channel_spent) ?? 0
        return wallet + max(0, dep - spent)
    }

    // MARK: - Polling

    private func startTimer() {
        let t = Timer(timeInterval: 4.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    private func refresh() {
        client.port = proxy.listenPort // the proxy may pick a different free port
        guard proxy.isRunning else {
            healthy = false
            DispatchQueue.main.async { [weak self] in self?.updateButton() }
            return
        }
        client.fetchStatus { [weak self] st in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let st = st { self.lastStatus = st; self.healthy = true }
                else { self.healthy = false }
                self.updateButton()
            }
        }
        client.fetchCapacity { [weak self] cap in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let cap = cap { self.lastCapacity = cap }
            }
        }
    }

    private func refreshSoon() {
        refresh()
        for delay in [1.2, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let running = proxy.isRunning
        let statusText = !running ? "Disconnected" : (healthy ? "Connected" : "Connecting…")
        let statusSymbol = running ? "antenna.radiowaves.left.and.right"
                                   : "antenna.radiowaves.left.and.right.slash"

        // Connect / Disconnect toggle switch — on top.
        let toggleItem = NSMenuItem()
        let tv = ToggleMenuView(title: statusText, isOn: running, symbol: statusSymbol)
        tv.onChange = { [weak self] on in
            guard let self = self else { return }
            if on { self.proxy.start() } else { self.proxy.stop() }
            self.refreshSoon()
        }
        toggleItem.view = tv
        menu.addItem(toggleItem)

        let gw = lastStatus?.gateways?.first ?? proxy.gateway
        addInfo(menu, "Gateway: \(gw)", symbol: "globe")

        menu.addItem(.separator())

        if healthy, let st = lastStatus {
            addInfo(menu, "Balance: \(fmtUSD(balanceTokens(st).map(tokenToUSDC)))",
                    symbol: "dollarsign.circle")
            if let rp = st.requests_paid {
                addInfo(menu, "Paid: \(rp) requests · \(fmtUSD(tokenValue(st.total_paid).map(tokenToUSDC))) total",
                        symbol: "checklist")
            }
        } else {
            addInfo(menu, "Balance: —", symbol: "dollarsign.circle")
        }

        if let net = lastCapacity?.network {
            addInfo(menu, "Network: \(net.models ?? 0) models · \(net.free_slots ?? 0) free slots",
                    symbol: "antenna.radiowaves.left.and.right")
        }

        menu.addItem(.separator())

        // Last-hour usage by model (bounded by uptime — receipts live in memory).
        let now = Int64(Date().timeIntervalSince1970)
        let (byModel, total) = usageLastHour(lastStatus?.receipts ?? [], now: now)

        let lh = NSMenuItem()
        lh.attributedTitle = NSAttributedString(
            string: "Last hour (since connect)",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        lh.image = menuSymbol("clock")
        lh.isEnabled = false
        menu.addItem(lh)

        if byModel.isEmpty {
            addInfo(menu, "    no requests yet")
        } else {
            for entry in byModel {
                let u = entry.usage
                addInfo(menu, "    \(entry.model): \(fmtTok(u.inTok))→\(fmtTok(u.outTok)) tok · "
                    + "\(fmtUSD(tokenToUSDC(nanoToToken(u.nano)))) · \(u.reqs) req")
            }
            addInfo(menu, "    Σ \(fmtTok(total.inTok + total.outTok)) tok · "
                + "\(fmtUSD(tokenToUSDC(nanoToToken(total.nano)))) · \(total.reqs) req")
        }

        menu.addItem(.separator())

        addAction(menu, "Copy proxy URL", #selector(copyProxyURL), symbol: "link", key: "c")
        if let pub = lastStatus?.session_pub {
            addAction(menu, "Copy wallet ID (\(shortHex(pub)))", #selector(copyWallet), symbol: "key")
        }

        menu.addItem(.separator())

        addAction(menu, "Reconnect", #selector(restartProxy), symbol: "arrow.clockwise")
        addAction(menu, "Set gateway…", #selector(setGateway), symbol: "network")
        addAction(menu, "Open proxy log", #selector(openLog), symbol: "doc.text")

        menu.addItem(.separator())
        addAction(menu, "Quit Alien Compute", #selector(quit), symbol: "power", key: "q")

        // Kick a fetch so the next open shows fresher data.
        refresh()
    }

    private func menuSymbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    private func addInfo(_ menu: NSMenu, _ text: String, symbol: String? = nil) {
        let it = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        it.isEnabled = false
        if let symbol = symbol { it.image = menuSymbol(symbol) }
        menu.addItem(it)
    }

    @discardableResult
    private func addAction(_ menu: NSMenu, _ title: String, _ sel: Selector,
                           symbol: String? = nil, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        it.isEnabled = true
        if let symbol = symbol { it.image = menuSymbol(symbol) }
        menu.addItem(it)
        return it
    }

    // MARK: - Actions

    @objc private func copyProxyURL() { setClipboard(proxy.apiBase) }

    @objc private func copyWallet() {
        if let pub = lastStatus?.session_pub { setClipboard(pub) }
    }

    @objc private func restartProxy() {
        proxy.restart()
        refreshSoon()
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(proxy.logURL)
    }

    @objc private func setGateway() {
        let alert = NSAlert()
        alert.messageText = "Gateway URL"
        alert.informativeText = "One entrypoint is enough — the proxy discovers the rest. Comma-separated bootstrap URLs are allowed. The proxy will restart."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.stringValue = proxy.gateway
        alert.accessoryView = field
        alert.addButton(withTitle: "Save & Restart")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let gw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !gw.isEmpty {
                UserDefaults.standard.set(gw, forKey: "gateway")
                proxy.restart(gateway: gw)
                refreshSoon()
            }
        }
    }

    @objc private func quit() {
        proxy.stop()
        NSApp.terminate(nil)
    }

    private func setClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}
