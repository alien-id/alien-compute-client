import Foundation

// MARK: - Wire models (field names match the proxy JSON exactly)

struct Receipt: Decodable {
    let model: String?
    let in_tokens: UInt64?
    let out_tokens: UInt64?
    let price_nano: UInt64?
    let at: Int64?          // Unix seconds
    let verified: Bool?
}

struct FleetStatus: Decodable {
    let gateways: [String]?
    let session_pub: String?
    let wallet_balance: String?     // e.g. "50.000000000 FLEET"
    let channel_id: String?
    let channel_deposit: String?
    let channel_spent: String?
    let requests_paid: Int?
    let total_paid: String?
    let receipts: [Receipt]?
}

struct Capacity: Decodable {
    struct Network: Decodable {
        let models: Int?
        let free_slots: Int?
    }
    let network: Network?
}

// MARK: - Local HTTP client (talks to the proxy on 127.0.0.1)

final class FleetClient {
    var port: Int = 8080
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    private func get<T: Decodable>(_ path: String, _ type: T.Type,
                                   completion: @escaping (T?) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            completion(nil); return
        }
        session.dataTask(with: url) { data, resp, err in
            guard err == nil,
                  let data = data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONDecoder().decode(T.self, from: data) else {
                completion(nil); return
            }
            completion(obj)
        }.resume()
    }

    func fetchStatus(_ c: @escaping (FleetStatus?) -> Void) {
        get("/fleet/status", FleetStatus.self, completion: c)
    }

    func fetchCapacity(_ c: @escaping (Capacity?) -> Void) {
        get("/fleet/capacity", Capacity.self, completion: c)
    }
}

// MARK: - Usage aggregation

struct ModelUsage {
    var inTok: UInt64 = 0
    var outTok: UInt64 = 0
    var nano: UInt64 = 0
    var reqs: Int = 0
}

/// Group receipts from the last hour by model, sorted by spend descending.
func usageLastHour(_ receipts: [Receipt], now: Int64)
    -> (byModel: [(model: String, usage: ModelUsage)], total: ModelUsage) {
    let cutoff = now - 3600
    var map: [String: ModelUsage] = [:]
    var total = ModelUsage()

    for r in receipts {
        guard let at = r.at, at >= cutoff else { continue }
        let m = r.model ?? "?"
        let i = r.in_tokens ?? 0
        let o = r.out_tokens ?? 0
        let n = r.price_nano ?? 0

        var u = map[m] ?? ModelUsage()
        u.inTok += i; u.outTok += o; u.nano += n; u.reqs += 1
        map[m] = u

        total.inTok += i; total.outTok += o; total.nano += n; total.reqs += 1
    }

    let sorted = map.sorted { $0.value.nano > $1.value.nano }
        .map { (model: $0.key, usage: $0.value) }
    return (sorted, total)
}

// MARK: - Currency

// Internally the proxy reports amounts with a "FLEET" suffix and prices in
// nano-units. We never surface that token; everything shown to the user is USDC,
// converted with a mock exchange rate. Adjust the rate freely.
let usdcPerToken: Double = 0.90   // mock: 1 internal token = $0.90 USDC (~$45 balance)

/// Numeric value out of a "<number> FLEET" string (the unit suffix is ignored).
func tokenValue(_ s: String?) -> Double? {
    guard let s = s else { return nil }
    let token = s.split(separator: " ").first.map(String.init) ?? s
    return Double(token)
}

func nanoToToken(_ n: UInt64) -> Double { Double(n) / 1_000_000_000.0 }
func tokenToUSDC(_ amount: Double) -> Double { amount * usdcPerToken }

// MARK: - Formatting helpers

private let usdFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "en_US") // USD formatting: "$1,234.45"
    f.currencySymbol = "$"
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

func fmtUSD(_ usd: Double?) -> String {
    guard let v = usd else { return "—" }
    return usdFormatter.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
}

func fmtTok(_ n: UInt64) -> String {
    if n < 1_000 { return "\(n)" }
    if n < 1_000_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return String(format: "%.2fM", Double(n) / 1_000_000)
}

/// Abbreviate a long hex id as prefix…suffix.
func shortHex(_ s: String, prefix: Int = 6, suffix: Int = 4) -> String {
    guard s.count > prefix + suffix + 1 else { return s }
    return "\(s.prefix(prefix))…\(s.suffix(suffix))"
}
