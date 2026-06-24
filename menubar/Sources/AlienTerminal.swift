import AppKit
import QuartzCore

// MARK: - Alien (Marain nonary) terminal
//
// A self-contained, animated "Culture terminal" rendered entirely in vector.
// It runs a looping REPL session between this client and a Culture Mind. Each
// word is written in *Marain nonary* (M1): every glyph is a 3×3 lattice of
// on/off dots — a nine-bit number — exactly as Banks describes the script that
// "appeals to poets, pedants, engineers and programmers". Commands decrypt
// from scrambled glyphs (a nod to the M8–M32 Contact ciphers), then the
// terminal prints the plain-language gloss beneath.
//
// No external assets / no font dependency: glyphs, scanlines, sensor sweep and
// glow are all drawn in draw(_:). One 30 fps timer drives a monotonic clock;
// the whole scene is a pure function of `phase`, so it survives any redraw.

final class AlienTerminalView: NSView {

    // MARK: Palette
    private let cyan   = NSColor(srgbRed: 0.30, green: 0.85, blue: 1.00, alpha: 1)
    private let amber  = NSColor(srgbRed: 1.00, green: 0.66, blue: 0.20, alpha: 1) // "encrypted"
    private let mind   = NSColor(srgbRed: 0.45, green: 1.00, blue: 0.78, alpha: 1) // Mind replies
    private let dim    = NSColor(srgbRed: 0.58, green: 0.68, blue: 0.80, alpha: 1) // system lines

    // MARK: Glyph metrics (a glyph = 3×3 dot lattice)
    private let pitch: CGFloat = 3.5     // dot-to-dot spacing
    private let dot:   CGFloat = 2.0     // lit-dot diameter
    private let glyphGap: CGFloat = 3.0  // space between glyphs
    private var glyphW: CGFloat { 3 * pitch }
    private var advance: CGFloat { glyphW + glyphGap }

    // MARK: Layout
    private let headerH: CGFloat = 24
    private let pad: CGFloat = 12
    private let blockH: CGFloat = 15     // one REPL line (a row of Marain glyphs)
    private let visibleLines = 8

    override var isFlipped: Bool { true } // top-left origin → natural terminal flow

    // MARK: REPL script (a Culture Mind handshake mirroring the real flow)
    private enum Kind { case system, command, reply }
    private struct Line { let marain: String; let gloss: String; let kind: Kind }
    private let script: [Line] = [
        Line(marain: "selkar ventha",       gloss: "M1 nonary link · established",       kind: .system),
        Line(marain: "kanto sael dirun",    gloss: "claim free balance",                 kind: .command),
        Line(marain: "vaeldon marik thal",  gloss: "wallet manifested · +100 tokens",    kind: .reply),
        Line(marain: "queris venn sira",    gloss: "identify serving Mind",              kind: .command),
        Line(marain: "amari sleeptha vorr", gloss: "GSV Sleeper Service · Mind online",  kind: .reply),
        Line(marain: "sirintha kael bond",  gloss: "open inference channel",             kind: .command),
        Line(marain: "kaellaz tovan secur", gloss: "channel armed · payments e2e",       kind: .reply),
        Line(marain: "rundja meta querin",  gloss: "dispatch inference",                 kind: .command),
        Line(marain: "metaron setha luun",  gloss: "request metered · settling",         kind: .reply),
        Line(marain: "sethlan confa donar", gloss: "micro-payment confirmed",            kind: .reply),
        Line(marain: "skarn substal veri",  gloss: "query substrate status",             kind: .command),
        Line(marain: "thalor nomin twelv",  gloss: "substrate nominal · 12 ms",          kind: .reply),
        Line(marain: "veyl standa korin",   gloss: "standing by",                        kind: .system),
    ]

    // MARK: Timing (seconds)
    private let boot: CFTimeInterval = 1.0
    private let glyphStagger: CFTimeInterval = 0.07
    private let scramble: CFTimeInterval = 0.35
    private let holdAfter: CFTimeInterval = 0.6
    private let gap: CFTimeInterval = 0.15
    private let idle: CFTimeInterval = 2.4

    private lazy var lineDur: [CFTimeInterval] = script.map { l in
        let glyphsDone = Double(l.marain.count) * glyphStagger + scramble
        return glyphsDone + holdAfter + gap
    }
    private lazy var lineStart: [CFTimeInterval] = {
        var t = boot, out: [CFTimeInterval] = []
        for d in lineDur { out.append(t); t += d }
        return out
    }()
    private var sessionDur: CFTimeInterval { (lineStart.last ?? 0) + (lineDur.last ?? 0) }
    private var cycle: CFTimeInterval { sessionDur + idle }

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var timer: Timer?

    // MARK: Lifecycle
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var allowsVibrancy: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 320, height: headerH + pad + CGFloat(visibleLines) * blockH + pad)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startAnimating() } else { stopAnimating() }
    }

    func startAnimating() {
        guard timer == nil else { return }
        startTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAnimating() { timer?.invalidate(); timer = nil }

    // MARK: Drawing
    override func draw(_ dirtyRect: NSRect) {
        let phase = (CACurrentMediaTime() - startTime).truncatingRemainder(dividingBy: cycle)

        let panel = bounds.insetBy(dx: 1.0, dy: 1.0)
        let body = NSBezierPath(rect: panel)

        // Panel body: dark glassy gradient + glowing rim.
        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.05, green: 0.09, blue: 0.13, alpha: 0.96),
            NSColor(srgbRed: 0.01, green: 0.02, blue: 0.04, alpha: 0.98),
        ])!.draw(in: panel, angle: -90)
        drawScanlines(in: panel, phase: phase)
        drawSensorSweep(in: panel, phase: phase)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let rim = NSShadow()
        rim.shadowColor = cyan.withAlphaComponent(0.35)
        rim.shadowBlurRadius = 2.5
        rim.shadowOffset = .zero
        rim.set()
        cyan.withAlphaComponent(0.95).setStroke()
        body.lineWidth = 1.0
        body.stroke()
        NSGraphicsContext.restoreGraphicsState()

        drawHeader(in: panel, phase: phase)

        // Content area (clipped) — the scrolling REPL.
        let content = NSRect(x: panel.minX + pad,
                             y: panel.minY + headerH,
                             width: panel.width - 2 * pad,
                             height: panel.maxY - (panel.minY + headerH) - pad)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: content).addClip()
        drawREPL(in: content, phase: phase)
        NSGraphicsContext.restoreGraphicsState()

        // Soft fade at the top edge so scrolled lines dissolve rather than clip.
        NSGraphicsContext.saveGraphicsState()
        let fade = NSRect(x: content.minX, y: content.minY, width: content.width, height: 14)
        NSGradient(colors: [
            NSColor(srgbRed: 0.02, green: 0.04, blue: 0.06, alpha: 0.95),
            NSColor(srgbRed: 0.02, green: 0.04, blue: 0.06, alpha: 0.0),
        ])!.draw(in: fade, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Header — port lights + Marain label
    private func drawHeader(in panel: NSRect, phase: CFTimeInterval) {
        let cy = panel.minY + headerH / 2
        let lights: [NSColor] = [amber, cyan, mind]
        for (i, col) in lights.enumerated() {
            let x = panel.minX + 14 + CGFloat(i) * 13
            let pulse = 0.55 + 0.45 * abs(sin(phase * 1.7 + Double(i)))
            col.withAlphaComponent(pulse).setFill()
            let r: CGFloat = 3
            NSGraphicsContext.saveGraphicsState()
            let g = NSShadow(); g.shadowColor = col.withAlphaComponent(0.6); g.shadowBlurRadius = 2; g.shadowOffset = .zero; g.set()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let label = NSAttributedString(string: "M1 · NONARY LINK", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: dim.withAlphaComponent(0.8),
            .kern: 1.5,
        ])
        let sz = label.size()
        label.draw(at: NSPoint(x: panel.maxX - 14 - sz.width, y: cy - sz.height / 2))

        // Hairline under the header.
        dim.withAlphaComponent(0.18).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: panel.minX + 10, y: panel.minY + headerH))
        sep.line(to: NSPoint(x: panel.maxX - 10, y: panel.minY + headerH))
        sep.lineWidth = 1
        sep.stroke()
    }

    // MARK: REPL body
    private func drawREPL(in rect: NSRect, phase: CFTimeInterval) {
        // How many lines have begun, plus the active line.
        var active = -1
        for i in 0..<script.count where phase >= lineStart[i] { active = i }

        let idling = phase >= sessionDur
        if active < 0 && !idling {
            // Boot: a lone breathing cursor while the link initialises.
            if Int(phase * 2) % 2 == 0 {
                cyan.withAlphaComponent(0.9).setFill()
                NSBezierPath(rect: NSRect(x: rect.minX + 2, y: rect.minY + 8, width: 8, height: 13)).fill()
            }
            return
        }
        let lastStarted = idling ? script.count - 1 : active

        // Smoothly scroll so the newest line sits on the bottom visible row.
        let scroll = scrollOffset(phase: phase, active: active, idling: idling)

        for i in 0...lastStarted {
            let row = CGFloat(i) - scroll
            let blockTop = rect.minY + row * blockH
            guard blockTop + blockH > rect.minY - 2, blockTop < rect.maxY + 2 else { continue }
            let localT = idling ? 9_999 : (phase - lineStart[i])
            let isActive = (i == lastStarted)
            drawLine(script[i], at: blockTop, in: rect, localT: localT,
                     phase: phase, isActive: isActive, idling: idling)
        }
    }

    private func scrollOffset(phase: CFTimeInterval, active: Int, idling: Bool) -> CGFloat {
        func target(_ i: Int) -> CGFloat { max(0, CGFloat(i) - CGFloat(visibleLines - 1)) }
        if idling { return target(script.count - 1) }
        guard active >= 0 else { return 0 }
        let prev = active > 0 ? target(active - 1) : 0
        let ease = smoothstep(0, 0.35, phase - lineStart[active])
        return prev + (target(active) - prev) * CGFloat(ease)
    }

    private func drawLine(_ line: Line, at blockTop: CGFloat, in rect: NSRect,
                          localT: CFTimeInterval, phase: CFTimeInterval,
                          isActive: Bool, idling: Bool) {
        let color: NSColor = (line.kind == .reply) ? mind : (line.kind == .command ? cyan : dim)
        let indent: CGFloat = (line.kind == .reply) ? 12 : 0
        var x = rect.minX + indent
        let glyphTop = blockTop + 3

        // Prompt sigil.
        let sigil = (line.kind == .command) ? "›" : (line.kind == .reply ? "◂" : "∴")
        let ps = NSAttributedString(string: sigil, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
            .foregroundColor: color.withAlphaComponent(0.95),
        ])
        ps.draw(at: NSPoint(x: x, y: glyphTop - 1))
        x += 10

        // Marain glyphs — scramble (amber) then lock to colour.
        let chars = Array(line.marain)
        for (j, ch) in chars.enumerated() {
            let jStart = Double(j) * glyphStagger
            if localT < jStart { break }
            let into = localT - jStart
            let pat: [String]
            let cellColor: NSColor
            if into < scramble && !idling {
                pat = Self.glyph(forScrambleFrame: Int(into * 22) &+ j &* 7)
                cellColor = amber
            } else {
                pat = Self.glyph(for: ch)
                cellColor = color
            }
            drawGlyph(pat, atX: x, top: glyphTop, color: cellColor)
            x += advance
        }

        // Blinking caret trails the freshly-typed glyphs on the live line.
        if isActive && Int(phase * 2) % 2 == 0 {
            color.withAlphaComponent(0.9).setFill()
            NSBezierPath(rect: NSRect(x: x + 1,
                                      y: glyphTop + pitch * 0.5 - dot / 2,
                                      width: 4,
                                      height: 2 * pitch + dot)).fill()
        }
    }

    /// Draw one Marain glyph: a 3×3 lattice. Lit dots glow; unlit dots stay as a
    /// faint lattice so the nine-cell structure is always legible.
    private func drawGlyph(_ pat: [String], atX gx: CGFloat, top gyTop: CGFloat, color: NSColor) {
        for r in 0..<3 {
            let rowChars = Array(pat[r])
            for c in 0..<3 {
                let cxp = gx + (CGFloat(c) + 0.5) * pitch
                let cyp = gyTop + (CGFloat(r) + 0.5) * pitch
                let lit = rowChars[c] == "#"
                let d = lit ? dot : dot * 0.6
                let cell = NSRect(x: cxp - d / 2, y: cyp - d / 2, width: d, height: d)
                // Crisp dots: bright solid for lit, faint for the dark lattice —
                // contrast (not a diffuse glow) carries the "lit" read.
                color.withAlphaComponent(lit ? 1.0 : 0.10).setFill()
                NSBezierPath(ovalIn: cell).fill()
            }
        }
    }

    // MARK: Ambient effects
    private func drawScanlines(in rect: NSRect, phase: CFTimeInterval) {
        NSColor(white: 1, alpha: 0.035).setStroke()
        let scroll = (phase * 12).truncatingRemainder(dividingBy: 3)
        var y = rect.minY + scroll
        let p = NSBezierPath(); p.lineWidth = 1
        while y < rect.maxY {
            p.move(to: NSPoint(x: rect.minX, y: y))
            p.line(to: NSPoint(x: rect.maxX, y: y))
            y += 3
        }
        p.stroke()
    }

    private func drawSensorSweep(in rect: NSRect, phase: CFTimeInterval) {
        let band: CGFloat = 46
        let travel = rect.height + band
        let y = rect.minY - band + CGFloat((phase * 38).truncatingRemainder(dividingBy: Double(travel)))
        let r = NSRect(x: rect.minX, y: y, width: rect.width, height: band)
        NSGradient(colors: [
            cyan.withAlphaComponent(0.0),
            cyan.withAlphaComponent(0.07),
            cyan.withAlphaComponent(0.0),
        ])!.draw(in: r, angle: -90)
    }

    // MARK: Glyph table — 30 distinct, hand-tuned 3×3 nonary patterns.
    // Each letter maps to a stable pattern (repeats look identical, like a real
    // script); the scramble cycles through the same table so commands appear to
    // decrypt through valid-looking glyphs.
    private static let patterns: [[String]] = [
        ["·#·","###","·#·"], ["#·#","·#·","#·#"], ["###","#·#","###"], ["###","··#","###"],
        ["#··","###","··#"], ["··#","###","#··"], ["##·","·#·","·##"], ["·##","·#·","##·"],
        ["#·#","###","#·#"], ["·#·","#·#","·#·"], ["###","#··","#··"], ["###","··#","··#"],
        ["#··","#··","###"], ["··#","··#","###"], ["###","·#·","·#·"], ["·#·","·#·","###"],
        ["#·#","·#·","###"], ["###","·#·","#·#"], ["##·","##·","··#"], ["·##","·##","#··"],
        ["#·#","#·#","·#·"], ["·#·","#·#","#·#"], ["##·","#·#","·##"], ["·##","#·#","##·"],
        ["#··","·#·","··#"], ["··#","·#·","#··"], ["###","#·#","··#"], ["###","#·#","#··"],
        ["·#·","###","#·#"], ["#·#","###","·#·"],
    ]

    /// Stable glyph for a romanized character (letters → distinct patterns).
    private static func glyph(for ch: Character) -> [String] {
        let s = ch.lowercased().unicodeScalars.first!.value
        if ch == " " { return ["···","···","···"] }
        let idx: Int
        if s >= 97 && s <= 122 { idx = Int(s - 97) % patterns.count }          // a–z
        else if s >= 48 && s <= 57 { idx = (Int(s - 48) + 20) % patterns.count } // 0–9
        else { idx = Int(s) % patterns.count }
        return patterns[idx]
    }

    private static func glyph(forScrambleFrame f: Int) -> [String] {
        var h = UInt32(truncatingIfNeeded: f) &* 2_654_435_761
        h ^= h >> 15; h = h &* 2_246_822_519; h ^= h >> 13
        return patterns[Int(h % UInt32(patterns.count))]
    }
}

// MARK: - small easing helper
private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}
