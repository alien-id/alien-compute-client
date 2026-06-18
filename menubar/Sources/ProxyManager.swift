import Foundation
import Darwin

/// Manages the bundled `fleet-proxy` subprocess.
final class ProxyManager {
    private(set) var process: Process?
    private let proxyURL: URL
    let logURL: URL

    var gateway: String
    let listenHost = "127.0.0.1"
    private let preferredPort = 4113
    private(set) var listenPort = 4113
    var listen: String { "\(listenHost):\(listenPort)" }
    var apiBase: String { "http://\(listenHost):\(listenPort)/v1" }

    init?(gateway: String) {
        guard let res = Bundle.main.resourceURL?.appendingPathComponent("fleet-proxy"),
              FileManager.default.fileExists(atPath: res.path) else {
            return nil
        }
        self.proxyURL = res
        self.gateway = gateway

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logURL = logsDir.appendingPathComponent("AlienCompute-proxy.log")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    func start() {
        guard !isRunning else { return }
        listenPort = resolvePort()

        let p = Process()
        p.executableURL = proxyURL
        p.arguments = ["-gateway", gateway, "-listen", listen]

        // Fresh log file per launch; reuse one handle for stdout+stderr so the
        // file offset stays shared and lines interleave correctly.
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let fh = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = fh
            p.standardError = fh
        }

        do {
            try p.run()
            process = p
        } catch {
            NSLog("AlienCompute: failed to launch fleet-proxy: \(error)")
            process = nil
        }
    }

    func stop() {
        guard let p = process, p.isRunning else { process = nil; return }
        p.terminate() // SIGTERM
        process = nil
    }

    /// Stop, then start again (optionally with a new gateway) after the port frees.
    func restart(gateway: String? = nil) {
        if let gw = gateway { self.gateway = gw }
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Port selection

    /// Prefer 4113. If a leftover fleet-proxy holds it, reclaim it. If another
    /// service holds it, fall back to the next free port.
    private func resolvePort() -> Int {
        guard let occ = occupant(of: preferredPort) else { return preferredPort }
        if occ.command.contains("fleet-proxy") {
            kill(occ.pid, SIGTERM) // our own orphan — take the port back
            usleep(500_000)
            if occupant(of: preferredPort) == nil { return preferredPort }
        }
        for port in (preferredPort + 1)...(preferredPort + 30) where occupant(of: port) == nil {
            return port
        }
        return preferredPort
    }

    /// The process listening on a TCP port, via `lsof`, or nil if the port is free.
    private func occupant(of port: Int) -> (pid: pid_t, command: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["+c", "0", "-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }

        var pid: pid_t = 0
        var cmd = ""
        for line in s.split(separator: "\n") {
            switch line.first {
            case "p": pid = pid_t(line.dropFirst()) ?? 0
            case "c": cmd = String(line.dropFirst())
            default: break
            }
        }
        return pid > 0 ? (pid, cmd) : nil
    }
}
