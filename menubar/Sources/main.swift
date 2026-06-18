import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusController?
    var proxy: ProxyManager?
    var onboarding: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let gw = UserDefaults.standard.string(forKey: "gateway") ?? defaultGateway

        guard let proxy = ProxyManager(gateway: gw) else {
            let a = NSAlert()
            a.alertStyle = .critical
            a.messageText = "fleet-proxy binary missing"
            a.informativeText = "The bundled fleet-proxy was not found in the app's Resources. Rebuild the app with build.sh."
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            NSApp.terminate(nil)
            return
        }

        self.proxy = proxy
        controller = StatusController(proxy: proxy)

        if UserDefaults.standard.bool(forKey: "didOnboard") {
            proxy.start()
        } else {
            let ob = OnboardingController(proxy: proxy) { [weak self] in
                self?.onboarding = nil
            }
            onboarding = ob
            ob.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        proxy?.stop()
    }
}

// Default gateway: the live Fleet testnet control plane (see CLIENT.md).
let defaultGateway = "http://15.237.243.199:9000"

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
app.run()
