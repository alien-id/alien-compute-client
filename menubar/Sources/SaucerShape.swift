import AppKit

/// Shared flying-saucer artwork, used for both the menu-bar template image and
/// the colored app icon. No external assets — everything is drawn vector.
enum Saucer {

    // MARK: Menu-bar image (traced flying-saucer silhouette)

    static func menuBarImage(height: CGFloat = 0) -> NSImage {
        let h = height > 0 ? height : max(16, NSStatusBar.system.thickness - 3)
        let w = h * 1.5 // saucer is wider than tall
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            NSColor.black.setFill()
            drawSaucerSilhouette(in: rect)
            return true
        }
        img.isTemplate = true // tints to the menu bar (black/white)
        return img
    }

    /// Vector trace of the provided saucer: hollow dome (arch) + wide disc with
    /// three port-light holes + a detached bottom crescent. Even-odd fill so the
    /// holes and dome interior read as transparent. Requires box width ≈ 1.5×height
    /// (lets the dome use circular arcs).
    static func drawSaucerSilhouette(in b: CGRect) {
        let w = b.width, h = b.height
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: b.minX + fx * w, y: b.minY + fy * h)
        }

        let path = NSBezierPath()
        path.windingRule = .evenOdd

        // Disc (flattened lens), full width.
        path.append(NSBezierPath(ovalIn: CGRect(x: b.minX + 0.01 * w, y: b.minY + 0.31 * h,
                                                width: 0.98 * w, height: 0.30 * h)))

        // Three port lights (subtracted via even-odd).
        let holeR = 0.055 * w
        for fx: CGFloat in [0.30, 0.50, 0.70] {
            let c = p(fx, 0.42)
            path.append(NSBezierPath(ovalIn: CGRect(x: c.x - holeR, y: c.y - holeR,
                                                    width: 2 * holeR, height: 2 * holeR)))
        }

        // Dome: a thick arch (half-annulus). Circular arcs work because w = 1.5 h.
        let cx = b.midX
        let baseY = b.minY + 0.62 * h
        let ro = 0.30 * h, ri = 0.225 * h
        path.move(to: CGPoint(x: cx + ro, y: baseY))
        path.appendArc(withCenter: CGPoint(x: cx, y: baseY), radius: ro,
                       startAngle: 0, endAngle: 180, clockwise: false)
        path.line(to: CGPoint(x: cx - ri, y: baseY))
        path.appendArc(withCenter: CGPoint(x: cx, y: baseY), radius: ri,
                       startAngle: 180, endAngle: 0, clockwise: true)
        path.close()

        // Detached bottom crescent.
        let crescent = NSBezierPath()
        crescent.move(to: p(0.30, 0.205))
        crescent.curve(to: p(0.70, 0.205), controlPoint1: p(0.42, 0.165), controlPoint2: p(0.58, 0.165))
        crescent.curve(to: p(0.30, 0.205), controlPoint1: p(0.60, 0.02), controlPoint2: p(0.40, 0.02))
        crescent.close()
        path.append(crescent)

        path.fill()
    }

    // MARK: Colored app icon

    /// The colored saucer rendered as an NSImage (used for the onboarding logo).
    static func iconImage(_ side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawColored(in: rect)
            return true
        }
    }

    static func drawColored(in canvas: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Rounded-square ("squircle") background, macOS-icon proportions.
        let m = canvas.width * 0.085
        let bg = canvas.insetBy(dx: m, dy: m)
        let r = bg.width * 0.2237
        NSBezierPath(roundedRect: bg, xRadius: r, yRadius: r).addClip()

        NSGradient(colors: [
            NSColor(srgbRed: 0.17, green: 0.12, blue: 0.38, alpha: 1),  // indigo
            NSColor(srgbRed: 0.03, green: 0.03, blue: 0.10, alpha: 1),  // deep space
        ])!.draw(in: bg, angle: -90)

        // Stars.
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9).setFill()
        let stars: [(CGFloat, CGFloat, CGFloat)] = [
            (0.18, 0.80, 0.006), (0.80, 0.84, 0.007), (0.86, 0.60, 0.005),
            (0.13, 0.58, 0.004), (0.72, 0.92, 0.005), (0.30, 0.90, 0.0045),
            (0.90, 0.74, 0.004), (0.25, 0.70, 0.0035), (0.62, 0.82, 0.004),
        ]
        for (fx, fy, fr) in stars {
            let rad = canvas.width * fr
            let cx = bg.minX + fx * bg.width
            let cy = bg.minY + fy * bg.height
            NSBezierPath(ovalIn: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)).fill()
        }

        // Saucer.
        let sw = bg.width * 0.74
        let sh = sw * 0.60
        let sbox = CGRect(x: bg.midX - sw / 2, y: bg.midY - sh * 0.32, width: sw, height: sh)
        drawSaucerColored(in: sbox, canvasW: canvas.width)
    }

    private static func drawSaucerColored(in sbox: CGRect, canvasW W: CGFloat) {
        let bw = sbox.width
        let bh = sbox.height

        let discW = bw
        let discH = bh * 0.42
        let discCY = sbox.minY + bh * 0.40
        let disc = CGRect(x: sbox.midX - discW / 2, y: discCY - discH / 2, width: discW, height: discH)

        // Tractor beam.
        let beam = NSBezierPath()
        let topHalf = discW * 0.16
        let botHalf = discW * 0.40
        let beamBotY = sbox.minY - bh * 0.30
        beam.move(to: CGPoint(x: sbox.midX - topHalf, y: disc.midY))
        beam.line(to: CGPoint(x: sbox.midX + topHalf, y: disc.midY))
        beam.line(to: CGPoint(x: sbox.midX + botHalf, y: beamBotY))
        beam.line(to: CGPoint(x: sbox.midX - botHalf, y: beamBotY))
        beam.close()
        clipFill(beam, gradient: NSGradient(colors: [
            NSColor(srgbRed: 0.55, green: 0.95, blue: 1.0, alpha: 0.45),
            NSColor(srgbRed: 0.55, green: 0.95, blue: 1.0, alpha: 0.0),
        ])!, angle: -90)

        // Disc (metallic).
        let discPath = NSBezierPath(ovalIn: disc)
        clipFill(discPath, gradient: NSGradient(colors: [
            NSColor(srgbRed: 0.93, green: 0.95, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.50, green: 0.54, blue: 0.64, alpha: 1),
        ])!, angle: -90)

        NSColor(srgbRed: 0.30, green: 0.33, blue: 0.42, alpha: 0.9).setStroke()
        let rim = NSBezierPath(ovalIn: disc.insetBy(dx: disc.width * 0.01, dy: disc.height * 0.04))
        rim.lineWidth = max(1, W * 0.012)
        rim.stroke()

        // Dome (glass).
        let domeW = bw * 0.46
        let domeH = bh * 0.52
        let dome = CGRect(x: sbox.midX - domeW / 2, y: disc.maxY - domeH * 0.30, width: domeW, height: domeH)
        clipFill(NSBezierPath(ovalIn: dome), gradient: NSGradient(colors: [
            NSColor(srgbRed: 0.80, green: 0.98, blue: 1.0, alpha: 0.98),
            NSColor(srgbRed: 0.25, green: 0.62, blue: 0.85, alpha: 0.98),
        ])!, angle: -90)

        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55).setFill()
        let hl = CGRect(x: dome.minX + domeW * 0.18, y: dome.minY + domeH * 0.45,
                        width: domeW * 0.28, height: domeH * 0.30)
        NSBezierPath(ovalIn: hl).fill()

        // Port lights.
        let n = 4
        let lightY = discCY - discH * 0.02
        let spread = discW * 0.62
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let x = sbox.midX - spread / 2 + t * spread
            let lr = bw * 0.035
            NSColor(srgbRed: 1.0, green: 0.86, blue: 0.4, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - lr * 2, y: lightY - lr * 2, width: lr * 4, height: lr * 4)).fill()
            NSColor(srgbRed: 1.0, green: 0.9, blue: 0.5, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: x - lr, y: lightY - lr, width: lr * 2, height: lr * 2)).fill()
        }
    }

    // MARK: Line-art hero (blueprint saucer)

    /// Line-drawn flying saucer — crisp neon strokes on a clear background.
    /// Used as the onboarding hero above the terminal.
    static func lineArtImage(_ side: CGFloat,
                             color: NSColor = NSColor(srgbRed: 0.30, green: 0.85, blue: 1.0, alpha: 1)) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawLineArt(in: rect, color: color)
            return true
        }
    }

    static func drawLineArt(in b: CGRect, color: NSColor) {
        let w = b.width, h = b.height
        let lw = max(1, w * 0.018)
        let cx = b.midX
        let midY = b.minY + 0.52 * h          // disc centre-line
        let halfW = 0.46 * w
        let topRise = 0.11 * h                 // upper hull bulge
        let botDrop = 0.15 * h                 // underside dip

        color.setStroke()

        // Hull (lens): top arc + underside arc meeting at the side tips.
        let leftTip = CGPoint(x: cx - halfW, y: midY)
        let rightTip = CGPoint(x: cx + halfW, y: midY)
        let hull = NSBezierPath()
        hull.move(to: leftTip)
        hull.curve(to: rightTip,
                   controlPoint1: CGPoint(x: cx - halfW * 0.5, y: midY + topRise),
                   controlPoint2: CGPoint(x: cx + halfW * 0.5, y: midY + topRise))
        hull.curve(to: leftTip,
                   controlPoint1: CGPoint(x: cx + halfW * 0.45, y: midY - botDrop),
                   controlPoint2: CGPoint(x: cx - halfW * 0.45, y: midY - botDrop))
        hull.lineWidth = lw
        hull.lineJoinStyle = .round
        hull.stroke()

        // Dome: its feet sit exactly on the hull's top arc (sampled at symmetric
        // t on the same Bézier), so the cupola rises from the body instead of
        // crossing into it.
        func hullTop(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(
                x: u*u*u * leftTip.x + 3*u*u*t * (cx - halfW * 0.5)
                 + 3*u*t*t * (cx + halfW * 0.5) + t*t*t * rightTip.x,
                y: u*u*u * midY + 3*u*u*t * (midY + topRise)
                 + 3*u*t*t * (midY + topRise) + t*t*t * midY)
        }
        let footL = hullTop(0.30)
        let footR = hullTop(0.70)
        let domeH = 0.22 * h
        let dome = NSBezierPath()
        dome.move(to: footL)
        dome.curve(to: footR,
                   controlPoint1: CGPoint(x: footL.x, y: footL.y + domeH),
                   controlPoint2: CGPoint(x: footR.x, y: footR.y + domeH))
        dome.lineWidth = lw
        dome.stroke()

        // Port windows along the front face.
        let winR = 0.034 * w
        let winY = midY - 0.015 * h
        let wins = NSBezierPath()
        for i in -1...1 {
            let x = cx + CGFloat(i) * 0.18 * w
            wins.appendOval(in: CGRect(x: x - winR, y: winY - winR, width: winR * 2, height: winR * 2))
        }
        wins.lineWidth = max(1, lw * 0.8)
        wins.stroke()

        // Tractor beam: dashed guide lines fanning down.
        let beam = NSBezierPath()
        beam.lineWidth = max(1, lw * 0.7)
        beam.setLineDash([w * 0.03, w * 0.03], count: 2, phase: 0)
        let beamTopY = midY - botDrop
        let beamBotY = b.minY + 0.10 * h
        for fx in [-0.12, 0.0, 0.12] as [CGFloat] {
            beam.move(to: CGPoint(x: cx + fx * w * 0.6, y: beamTopY))
            beam.line(to: CGPoint(x: cx + fx * w * 1.4, y: beamBotY))
        }
        color.withAlphaComponent(0.4).setStroke()
        beam.stroke()
    }

    private static func clipFill(_ path: NSBezierPath, gradient: NSGradient, angle: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        gradient.draw(in: path.bounds, angle: angle)
        NSGraphicsContext.restoreGraphicsState()
    }
}
