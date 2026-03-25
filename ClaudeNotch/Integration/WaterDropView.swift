import AppKit
import QuartzCore

/// Full-screen overlay that renders one complete water-drop animation cycle.
///
/// **5-phase lifecycle** (driven by `CADisplayLink`):
/// 1. **Flight** – a dot follows a parabolic arc from the notch to the terminal border.
/// 2. **Race / stream** – two liquid streams race clockwise and counter-clockwise around the terminal border until they meet at the bottom-center.
/// 3. **Impact** – the dot squishes and emits a splash ring and burst particles on landing.
/// 4. **Merge** – the two streams collide at the meeting point with a pulsing burst.
/// 5. **Return** – the merged dot arcs back up to the notch and fades out.
///
/// The view is created and owned by `WaterDropAnimator.animate(...)` for the duration of one animation.
/// Reduce-motion is handled at the animator level; this view is never instantiated when reduce-motion is enabled.
final class WaterDropView: NSView {

    override var isFlipped: Bool { true }

    let notchCenter: CGPoint
    let geometry: WaterDropAnimator.AnimationGeometry
    let colorR: CGFloat
    let colorG: CGFloat
    let colorB: CGFloat
    let scale: CGFloat

    private var startTime: Double = 0
    private var elapsed: Double = 0

    // Pre-allocated buffers for stream drawing
    private var outerPoints: [CGPoint] = []
    private var innerPoints: [CGPoint] = []

    // FIFO trails (newest first): head is the current frame, tail fades to transparent
    private var flightTrail: [CGPoint] = []
    private var returnTrail: [CGPoint] = []

    // Burst particles
    private var impactBurst: [Particle] = []
    private var mergeBurst: [Particle] = []
    private var splashDroplets: [Particle] = []

    private struct Particle {
        var x, y, vx, vy, life: CGFloat
    }

    init(frame: NSRect, notchCenter: CGPoint, geometry: WaterDropAnimator.AnimationGeometry, color: NSColor, scale: CGFloat) {
        self.notchCenter = notchCenter
        self.geometry = geometry
        self.scale = scale

        let rgb = color.usingColorSpace(.sRGB) ?? NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        self.colorR = rgb.redComponent
        self.colorG = rgb.greenComponent
        self.colorB = rgb.blueComponent

        outerPoints.reserveCapacity(70)
        innerPoints.reserveCapacity(70)

        super.init(frame: frame)
        wantsLayer = true
        startTime = CACurrentMediaTime()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Display Link Callback

    @objc func handleDisplayLink(_ sender: CADisplayLink) {
        elapsed = CACurrentMediaTime() - startTime
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let flight = NotchTokens.Animation.waterDropFlightDur
        let impact = NotchTokens.Animation.waterDropImpactDur
        let race = NotchTokens.Animation.waterDropRaceDur
        let merge = NotchTokens.Animation.waterDropMergeDur

        let landPt = geometry.pointOnBorder(at: 0) // top-center
        let meetPt = geometry.pointOnBorder(at: 0.5) // bottom-center

        if elapsed < flight {
            drawFlight(ctx, progress: elapsed / flight, landPt: landPt)
        } else if elapsed < flight + impact {
            drawImpact(ctx, progress: (elapsed - flight) / impact, landPt: landPt)
        } else if elapsed < flight + impact + race {
            drawRace(ctx, progress: (elapsed - flight - impact) / race, meetPt: meetPt)
        } else if elapsed < flight + impact + race + merge {
            drawMerge(ctx, progress: (elapsed - flight - impact - race) / merge, meetPt: meetPt)
        } else {
            let returnDur = NotchTokens.Animation.waterDropReturnDur
            drawReturn(ctx, progress: (elapsed - flight - impact - race - merge) / returnDur, meetPt: meetPt)
        }

        // Terminal border glow: flash at impact, fade through race
        let glowStart = flight
        let glowEnd = flight + impact + race * 0.5
        if elapsed >= glowStart && elapsed < glowEnd {
            let glowElapsed = elapsed - glowStart
            let glowDuration = glowEnd - glowStart
            // Quick flash in (first 15%), then fade out
            let fadeIn = min(1, glowElapsed / (glowDuration * 0.15))
            let fadeOut = 1 - max(0, (glowElapsed - glowDuration * 0.15) / (glowDuration * 0.85))
            let glowAlpha = fadeIn * fadeOut * 0.5
            drawTerminalGlow(ctx, alpha: glowAlpha)
        }

        // Draw burst particles across all phases
        updateAndDrawBursts(ctx)
    }

    // MARK: - Phase 1: Flight

    private func drawFlight(_ ctx: CGContext, progress p: Double, landPt: CGPoint) {
        let t = CGFloat(p)
        let pos = WaterDropAnimator.AnimationGeometry.projectilePosition(t: t, from: notchCenter, to: landPt)
        let next = WaterDropAnimator.AnimationGeometry.projectilePosition(
            t: min(1, t + 0.015), from: notchCenter, to: landPt
        )

        let angle = atan2(next.y - pos.y, next.x - pos.x)
        let speed = hypot(next.x - pos.x, next.y - pos.y)
        let stretch = 1 + min(speed * 0.05, 0.6)
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale

        ctx.withGState { ctx in
            ctx.translateBy(x: pos.x, y: pos.y)
            ctx.rotate(by: angle)
            ctx.scaleBy(x: stretch, y: 1 / stretch)
            drawDot(ctx, at: .zero, radius: dotR * 1.1, alpha: 1, glow: true)
        }

        // Trail
        flightTrail.insert(pos, at: 0)
        if flightTrail.count > NotchTokens.Animation.waterDropFlightTrailLength { flightTrail.removeLast() }
        drawTrail(ctx, trail: flightTrail, maxAlpha: 0.45)
    }

    // MARK: - Phase 2: Impact

    private func drawImpact(_ ctx: CGContext, progress p: Double, landPt: CGPoint) {
        let sp = CGFloat(p)

        if impactBurst.isEmpty {
            impactBurst = makeBurst(at: landPt, count: NotchTokens.Animation.waterDropImpactBurstCount, speed: 3.0)
            splashDroplets = makeSplash(at: landPt, count: NotchTokens.Animation.waterDropSplashCount)
        }

        let squishW = 1 + sp * 1.5
        let squishH = max(0.2, 1 - sp * 0.8)
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale

        ctx.withGState { ctx in
            ctx.translateBy(x: landPt.x, y: landPt.y)
            ctx.scaleBy(x: squishW, y: squishH)
            drawDot(ctx, at: .zero, radius: dotR, alpha: 1, glow: true)
        }

        // Splash ring expanding outward
        let ringRadius = dotR * (1 + sp * 4)
        let ringAlpha = (1 - sp) * 0.5
        ctx.withGState { ctx in
            ctx.setStrokeColor(colorWith(alpha: ringAlpha))
            ctx.setLineWidth(2.0 * (1 - sp))
            ctx.strokeEllipse(in: CGRect(
                x: landPt.x - ringRadius, y: landPt.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2
            ))
        }
    }

    // MARK: - Phase 3: Race

    private func drawRace(_ ctx: CGContext, progress p: Double, meetPt: CGPoint) {
        let rp = CGFloat(p)
        let eased = easeInOut(rp)
        let cwFront = eased * 0.5
        let ccwFront = eased * 0.5

        drawStream(ctx, front: cwFront, direction: 1, raceProgress: rp)
        drawStream(ctx, front: ccwFront, direction: -1, raceProgress: rp)

        // Glow at leading edges
        let cwPt = geometry.pointOnBorder(at: cwFront)
        let ccwT = WaterDropAnimator.AnimationGeometry.wrap(-ccwFront)
        let ccwPt = geometry.pointOnBorder(at: ccwT)
        drawGlow(ctx, at: cwPt, radius: 8 * scale)
        drawGlow(ctx, at: ccwPt, radius: 8 * scale)

        // Create merge burst near end
        if rp > 0.95 && mergeBurst.isEmpty {
            mergeBurst = makeBurst(at: meetPt, count: NotchTokens.Animation.waterDropMergeBurstCount, speed: 2.5)
        }
    }

    private func drawStream(_ ctx: CGContext, front: CGFloat, direction: CGFloat, raceProgress rp: CGFloat) {
        buildStreamGeometry(front: front, direction: direction, raceProgress: rp)
        guard outerPoints.count >= 2 else { return }

        drawStreamBody(ctx)
        drawStreamHighlight(ctx)
        drawSatelliteDroplets(ctx, front: front, direction: direction)
    }

    /// Populates `outerPoints` and `innerPoints` with samples along the stream path.
    private func buildStreamGeometry(front: CGFloat, direction: CGFloat, raceProgress rp: CGFloat) {
        let samples = NotchTokens.Animation.waterDropStreamSamples
        let streamLen = NotchTokens.Animation.waterDropStreamLength
        let baseThick = NotchTokens.Animation.waterDropStreamThickness * scale

        outerPoints.removeAll(keepingCapacity: true)
        innerPoints.removeAll(keepingCapacity: true)

        for i in 0...samples {
            let frac = CGFloat(i) / CGFloat(samples) // 0=front, 1=tail
            let bT = front - frac * streamLen
            if bT < -0.01 { continue }
            let clampedT = max(0, bT)

            let actualT: CGFloat = direction > 0
                ? clampedT
                : WaterDropAnimator.AnimationGeometry.wrap(-clampedT)

            let p = geometry.pointOnBorder(at: actualT)
            var n = geometry.normalOnBorder(at: actualT)
            if direction < 0 { n.dx = -n.dx; n.dy = -n.dy }

            // Thickness envelope + wobble
            let env = pow(1 - frac, 0.8)
            let wobble: CGFloat = 1 + sin(frac * 8 + rp * 12) * 0.15
            let thick = baseThick * env * wobble

            // Front taper
            let frontTaper: CGFloat = frac < 0.05 ? frac / 0.05 : 1
            let finalThick = thick * frontTaper

            outerPoints.append(p)
            innerPoints.append(CGPoint(x: p.x + n.dx * finalThick, y: p.y + n.dy * finalThick))
        }
    }

    /// Draws the filled liquid body and both edge strokes of the stream.
    private func drawStreamBody(_ ctx: CGContext) {
        // Fill liquid body
        ctx.withGState { ctx in
            ctx.beginPath()
            ctx.move(to: outerPoints[0])
            for i in 1..<outerPoints.count { ctx.addLine(to: outerPoints[i]) }
            for i in stride(from: innerPoints.count - 1, through: 0, by: -1) { ctx.addLine(to: innerPoints[i]) }
            ctx.closePath()
            ctx.setFillColor(colorWith(alpha: 0.3))
            ctx.fillPath()
        }

        // Meniscus stroke (outer edge)
        ctx.withGState { ctx in
            ctx.beginPath()
            ctx.move(to: outerPoints[0])
            for i in 1..<outerPoints.count { ctx.addLine(to: outerPoints[i]) }
            ctx.setStrokeColor(colorWith(alpha: 0.7))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }

        // Inner edge stroke
        ctx.withGState { ctx in
            ctx.beginPath()
            ctx.move(to: innerPoints[0])
            for i in 1..<innerPoints.count { ctx.addLine(to: innerPoints[i]) }
            ctx.setStrokeColor(colorWith(alpha: 0.25))
            ctx.setLineWidth(1.0)
            ctx.strokePath()
        }
    }

    /// Draws the specular highlight dot near the stream's leading edge.
    private func drawStreamHighlight(_ ctx: CGContext) {
        guard outerPoints.count > 3 else { return }
        let sp = outerPoints[2]
        let spI = innerPoints[2]
        let hx = (sp.x + spI.x) / 2
        let hy = (sp.y + spI.y) / 2
        ctx.withGState { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4))
            ctx.fillEllipse(in: CGRect(x: hx - 2, y: hy - 2, width: 4, height: 4))
        }
    }

    /// Draws the small trailing satellite droplets that follow the stream tail.
    private func drawSatelliteDroplets(_ ctx: CGContext, front: CGFloat, direction: CGFloat) {
        let streamLen = NotchTokens.Animation.waterDropStreamLength
        let baseThick = NotchTokens.Animation.waterDropStreamThickness * scale

        for d in 0..<3 {
            let dropFrac = 0.7 + CGFloat(d) * 0.1
            let dropBorderT = front - dropFrac * streamLen
            if dropBorderT < 0 { continue }

            let dropT: CGFloat = direction > 0
                ? dropBorderT
                : WaterDropAnimator.AnimationGeometry.wrap(-dropBorderT)

            let dp = geometry.pointOnBorder(at: dropT)
            var dn = geometry.normalOnBorder(at: dropT)
            if direction < 0 { dn.dx = -dn.dx; dn.dy = -dn.dy }

            let dropSize = 1.5 * (1 - dropFrac) * scale
            let ox = dp.x + dn.dx * (baseThick * 0.3)
            let oy = dp.y + dn.dy * (baseThick * 0.3)

            ctx.withGState { ctx in
                ctx.setFillColor(colorWith(alpha: 0.4 * (1 - dropFrac)))
                ctx.fillEllipse(in: CGRect(x: ox - dropSize, y: oy - dropSize, width: dropSize * 2, height: dropSize * 2))
            }
        }
    }

    // MARK: - Phase 4: Merge

    private func drawMerge(_ ctx: CGContext, progress p: Double, meetPt: CGPoint) {
        if mergeBurst.isEmpty {
            mergeBurst = makeBurst(at: meetPt, count: NotchTokens.Animation.waterDropMergeBurstCount, speed: 2.5)
        }

        let mp = CGFloat(p)
        let pulse = 1 + sin(mp * .pi * 2) * 0.3
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale
        drawDot(ctx, at: meetPt, radius: dotR * pulse, alpha: 1, glow: true)
    }

    // MARK: - Phase 5: Return

    private func drawReturn(_ ctx: CGContext, progress p: Double, meetPt: CGPoint) {
        let rp = CGFloat(min(p, 1))
        let pos = WaterDropAnimator.AnimationGeometry.returnPosition(t: rp, from: meetPt, to: notchCenter)
        let next = WaterDropAnimator.AnimationGeometry.returnPosition(
            t: min(1, rp + 0.015), from: meetPt, to: notchCenter
        )

        let angle = atan2(next.y - pos.y, next.x - pos.x)
        let speed = hypot(next.x - pos.x, next.y - pos.y)
        let stretch = 1 + min(speed * 0.05, 0.6)
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale
        let size = dotR * (1 - rp * 0.4)
        let alpha = 1 - rp * 0.3

        ctx.withGState { ctx in
            ctx.translateBy(x: pos.x, y: pos.y)
            ctx.rotate(by: angle)
            ctx.scaleBy(x: stretch, y: 1 / stretch)
            drawDot(ctx, at: .zero, radius: size, alpha: alpha, glow: true)
        }

        returnTrail.insert(pos, at: 0)
        if returnTrail.count > NotchTokens.Animation.waterDropReturnTrailLength { returnTrail.removeLast() }
        drawTrail(ctx, trail: returnTrail, maxAlpha: 0.35 * (1 - rp * 0.5))
    }

    // MARK: - Terminal Glow

    private func drawTerminalGlow(_ ctx: CGContext, alpha: CGFloat) {
        let rect = geometry.rect
        let cr = geometry.cornerRadius
        let spread: CGFloat = 12 * scale

        let glowRect = rect.insetBy(dx: -spread, dy: -spread)
        let path = CGPath(roundedRect: glowRect, cornerWidth: cr + spread, cornerHeight: cr + spread, transform: nil)
        let innerPath = CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil)

        // Outer glow (shadow-like)
        ctx.withGState { ctx in
            ctx.addPath(path)
            ctx.addPath(innerPath)
            ctx.clip(using: .evenOdd)
            ctx.setShadow(offset: .zero, blur: spread, color: colorWith(alpha: alpha))
            ctx.setFillColor(colorWith(alpha: alpha))
            ctx.addPath(innerPath)
            ctx.fillPath()
        }

        // Border stroke
        ctx.withGState { ctx in
            ctx.addPath(innerPath)
            ctx.setStrokeColor(colorWith(alpha: alpha * 0.8))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }

    // MARK: - Drawing Helpers

    private static let sRGBColorSpace = CGColorSpaceCreateDeviceRGB()

    private func drawDot(_ ctx: CGContext, at pt: CGPoint, radius: CGFloat, alpha: CGFloat, glow: Bool) {
        if glow {
            let glowR = radius * NotchTokens.Animation.waterDropGlowRadiusMultiplier
            let colors = [colorWith(alpha: alpha * 0.5), colorWith(alpha: 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: WaterDropView.sRGBColorSpace, colors: colors, locations: [0, 1]) {
                ctx.withGState { ctx in
                    ctx.drawRadialGradient(gradient, startCenter: pt, startRadius: 0, endCenter: pt, endRadius: glowR, options: [])
                }
            }
        }
        ctx.withGState { ctx in
            ctx.setFillColor(colorWith(alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func drawGlow(_ ctx: CGContext, at pt: CGPoint, radius: CGFloat) {
        let colors = [colorWith(alpha: 0.5), colorWith(alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: WaterDropView.sRGBColorSpace, colors: colors, locations: [0, 1]) else { return }
        ctx.withGState { ctx in
            ctx.drawRadialGradient(gradient, startCenter: pt, startRadius: 0, endCenter: pt, endRadius: radius, options: [])
        }
    }

    private func drawTrail(_ ctx: CGContext, trail: [CGPoint], maxAlpha: CGFloat) {
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale
        for (i, pt) in trail.enumerated() {
            let age = 1 - CGFloat(i) / CGFloat(trail.count)
            let r = dotR * 0.4 * age
            ctx.withGState { ctx in
                ctx.setFillColor(colorWith(alpha: age * maxAlpha))
                ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    // MARK: - Burst Particles

    private func makeBurst(at center: CGPoint, count: Int, speed: CGFloat) -> [Particle] {
        (0..<count).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let s = 0.5 + CGFloat.random(in: 0...1) * speed
            return Particle(
                x: center.x, y: center.y,
                vx: cos(angle) * s, vy: sin(angle) * s,
                life: 1
            )
        }
    }

    private func makeSplash(at center: CGPoint, count: Int) -> [Particle] {
        (0..<count).map { i in
            // Fan outward in a semicircle (upward-biased for a splash feel)
            let spread = CGFloat.pi * 0.8
            let baseAngle = -CGFloat.pi / 2 // upward
            let angle = count > 1
                ? baseAngle - spread / 2 + (spread * CGFloat(i) / CGFloat(count - 1))
                : baseAngle
            let s: CGFloat = 2.5 + CGFloat.random(in: 0...2)
            return Particle(
                x: center.x, y: center.y,
                vx: cos(angle) * s, vy: sin(angle) * s,
                life: 1
            )
        }
    }

    private func updateAndDrawBursts(_ ctx: CGContext) {
        updateAndDrawBurst(ctx, particles: &impactBurst, decay: NotchTokens.Animation.waterDropImpactBurstDecay)
        updateAndDrawBurst(ctx, particles: &mergeBurst, decay: NotchTokens.Animation.waterDropMergeBurstDecay)
        updateAndDrawSplash(ctx)
    }

    private func updateAndDrawSplash(_ ctx: CGContext) {
        splashDroplets = splashDroplets.compactMap { p in
            var p = p
            p.x += p.vx
            p.y += p.vy
            p.vy += 0.08 // heavier gravity for arc
            p.vx *= 0.98 // slight drag
            p.life -= 0.025
            guard p.life > 0 else { return nil }

            let r = (3.5 + p.life * 2) * scale
            // Draw droplet with a slight glow
            let alpha = p.life * 0.8
            ctx.withGState { ctx in
                ctx.setFillColor(colorWith(alpha: alpha))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                // Tiny white specular
                let specR = r * 0.35
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha * 0.5))
                ctx.fillEllipse(in: CGRect(x: p.x - specR * 0.5, y: p.y - r * 0.5, width: specR, height: specR))
            }

            return p
        }
    }

    private func updateAndDrawBurst(_ ctx: CGContext, particles: inout [Particle], decay: CGFloat) {
        particles = particles.compactMap { p in
            var p = p
            p.x += p.vx
            p.y += p.vy
            p.vy += 0.015
            p.life -= decay
            guard p.life > 0 else { return nil }

            let r = 2.5 * p.life * scale
            ctx.withGState { ctx in
                ctx.setFillColor(colorWith(alpha: p.life))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }

            return p
        }
    }

    // MARK: - Color Utility

    private func colorWith(alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: colorR, green: colorG, blue: colorB, alpha: alpha)
    }

    private func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

// MARK: - CGContext Graphics State Helper

private extension CGContext {
    /// Saves the current graphics state, executes `body`, then restores it.
    /// Replaces paired `saveGState()` / `restoreGState()` calls for clarity.
    func withGState(_ body: (CGContext) -> Void) {
        saveGState()
        body(self)
        restoreGState()
    }
}
