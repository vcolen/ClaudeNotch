import AppKit
import QuartzCore

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

    // Trail ring buffers
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

        let rgb = color.usingColorSpace(.sRGB) ?? color
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

        ctx.saveGState()
        ctx.translateBy(x: pos.x, y: pos.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: stretch, y: 1 / stretch)
        drawDot(ctx, at: .zero, radius: dotR * 1.1, alpha: 1, glow: true)
        ctx.restoreGState()

        // Trail
        flightTrail.insert(pos, at: 0)
        if flightTrail.count > 18 { flightTrail.removeLast() }
        drawTrail(ctx, trail: flightTrail, maxAlpha: 0.45)
    }

    // MARK: - Phase 2: Impact

    private func drawImpact(_ ctx: CGContext, progress p: Double, landPt: CGPoint) {
        let sp = CGFloat(p)

        if impactBurst.isEmpty {
            impactBurst = makeBurst(at: landPt, count: 14, speed: 3.0)
            splashDroplets = makeSplash(at: landPt, count: 6)
        }

        let squishW = 1 + sp * 1.5
        let squishH = max(0.2, 1 - sp * 0.8)
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale

        ctx.saveGState()
        ctx.translateBy(x: landPt.x, y: landPt.y)
        ctx.scaleBy(x: squishW, y: squishH)
        drawDot(ctx, at: .zero, radius: dotR, alpha: 1, glow: true)
        ctx.restoreGState()

        // Splash ring expanding outward
        let ringRadius = dotR * (1 + sp * 4)
        let ringAlpha = (1 - sp) * 0.5
        ctx.saveGState()
        ctx.setStrokeColor(colorWith(alpha: ringAlpha))
        ctx.setLineWidth(2.0 * (1 - sp))
        ctx.strokeEllipse(in: CGRect(
            x: landPt.x - ringRadius, y: landPt.y - ringRadius,
            width: ringRadius * 2, height: ringRadius * 2
        ))
        ctx.restoreGState()
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
            mergeBurst = makeBurst(at: meetPt, count: 14, speed: 2.5)
        }
    }

    private func drawStream(_ ctx: CGContext, front: CGFloat, direction: CGFloat, raceProgress rp: CGFloat) {
        let samples = 60
        let streamLen = NotchTokens.Animation.waterDropStreamLength
        let baseThick = NotchTokens.Animation.waterDropStreamThickness * scale

        outerPoints.removeAll(keepingCapacity: true)
        innerPoints.removeAll(keepingCapacity: true)

        for i in 0...samples {
            let frac = CGFloat(i) / CGFloat(samples) // 0=front, 1=tail
            let bT = front - frac * streamLen
            if bT < -0.01 { continue }
            let clampedT = max(0, bT)

            let actualT: CGFloat
            if direction > 0 {
                actualT = clampedT
            } else {
                actualT = WaterDropAnimator.AnimationGeometry.wrap(-clampedT)
            }

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

        guard outerPoints.count >= 2 else { return }

        // Fill liquid body
        ctx.saveGState()
        ctx.beginPath()
        ctx.move(to: outerPoints[0])
        for i in 1..<outerPoints.count { ctx.addLine(to: outerPoints[i]) }
        for i in stride(from: innerPoints.count - 1, through: 0, by: -1) { ctx.addLine(to: innerPoints[i]) }
        ctx.closePath()
        ctx.setFillColor(colorWith(alpha: 0.3))
        ctx.fillPath()
        ctx.restoreGState()

        // Meniscus stroke (outer edge)
        ctx.saveGState()
        ctx.beginPath()
        ctx.move(to: outerPoints[0])
        for i in 1..<outerPoints.count { ctx.addLine(to: outerPoints[i]) }
        ctx.setStrokeColor(colorWith(alpha: 0.7))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.restoreGState()

        // Inner edge stroke
        ctx.saveGState()
        ctx.beginPath()
        ctx.move(to: innerPoints[0])
        for i in 1..<innerPoints.count { ctx.addLine(to: innerPoints[i]) }
        ctx.setStrokeColor(colorWith(alpha: 0.25))
        ctx.setLineWidth(1.0)
        ctx.strokePath()
        ctx.restoreGState()

        // Specular highlight near front
        if outerPoints.count > 3 {
            let sp = outerPoints[2]
            let spI = innerPoints[2]
            let hx = (sp.x + spI.x) / 2
            let hy = (sp.y + spI.y) / 2
            ctx.saveGState()
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4))
            ctx.fillEllipse(in: CGRect(x: hx - 2, y: hy - 2, width: 4, height: 4))
            ctx.restoreGState()
        }

        // Trailing satellite droplets
        for d in 0..<3 {
            let dropFrac = 0.7 + CGFloat(d) * 0.1
            let dropBorderT = front - dropFrac * streamLen
            if dropBorderT < 0 { continue }

            let dropT: CGFloat
            if direction > 0 {
                dropT = dropBorderT
            } else {
                dropT = WaterDropAnimator.AnimationGeometry.wrap(-dropBorderT)
            }

            let dp = geometry.pointOnBorder(at: dropT)
            var dn = geometry.normalOnBorder(at: dropT)
            if direction < 0 { dn.dx = -dn.dx; dn.dy = -dn.dy }

            let dropSize = 1.5 * (1 - dropFrac) * scale
            let ox = dp.x + dn.dx * (baseThick * 0.3)
            let oy = dp.y + dn.dy * (baseThick * 0.3)

            ctx.saveGState()
            ctx.setFillColor(colorWith(alpha: 0.4 * (1 - dropFrac)))
            ctx.fillEllipse(in: CGRect(x: ox - dropSize, y: oy - dropSize, width: dropSize * 2, height: dropSize * 2))
            ctx.restoreGState()
        }
    }

    // MARK: - Phase 4: Merge

    private func drawMerge(_ ctx: CGContext, progress p: Double, meetPt: CGPoint) {
        if mergeBurst.isEmpty {
            mergeBurst = makeBurst(at: meetPt, count: 14, speed: 2.5)
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

        ctx.saveGState()
        ctx.translateBy(x: pos.x, y: pos.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: stretch, y: 1 / stretch)
        drawDot(ctx, at: .zero, radius: size, alpha: alpha, glow: true)
        ctx.restoreGState()

        returnTrail.insert(pos, at: 0)
        if returnTrail.count > 12 { returnTrail.removeLast() }
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
        ctx.saveGState()
        ctx.addPath(path)
        ctx.addPath(innerPath)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: .zero, blur: spread, color: colorWith(alpha: alpha))
        ctx.setFillColor(colorWith(alpha: alpha))
        ctx.addPath(innerPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Border stroke
        ctx.saveGState()
        ctx.addPath(innerPath)
        ctx.setStrokeColor(colorWith(alpha: alpha * 0.8))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Drawing Helpers

    private func drawDot(_ ctx: CGContext, at pt: CGPoint, radius: CGFloat, alpha: CGFloat, glow: Bool) {
        if glow {
            let glowR = radius * 5
            let colors = [colorWith(alpha: alpha * 0.5), colorWith(alpha: 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.saveGState()
                ctx.drawRadialGradient(gradient, startCenter: pt, startRadius: 0, endCenter: pt, endRadius: glowR, options: [])
                ctx.restoreGState()
            }
        }
        ctx.saveGState()
        ctx.setFillColor(colorWith(alpha: alpha))
        ctx.fillEllipse(in: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    private func drawGlow(_ ctx: CGContext, at pt: CGPoint, radius: CGFloat) {
        let colors = [colorWith(alpha: 0.5), colorWith(alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.drawRadialGradient(gradient, startCenter: pt, startRadius: 0, endCenter: pt, endRadius: radius, options: [])
        ctx.restoreGState()
    }

    private func drawTrail(_ ctx: CGContext, trail: [CGPoint], maxAlpha: CGFloat) {
        let dotR = NotchTokens.Animation.waterDropDotRadius * scale
        for (i, pt) in trail.enumerated() {
            let age = 1 - CGFloat(i) / CGFloat(trail.count)
            let r = dotR * 0.4 * age
            ctx.saveGState()
            ctx.setFillColor(colorWith(alpha: age * maxAlpha))
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
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
            let angle = baseAngle - spread / 2 + (spread * CGFloat(i) / CGFloat(count - 1))
            let s: CGFloat = 2.5 + CGFloat.random(in: 0...2)
            return Particle(
                x: center.x, y: center.y,
                vx: cos(angle) * s, vy: sin(angle) * s,
                life: 1
            )
        }
    }

    private func updateAndDrawBursts(_ ctx: CGContext) {
        updateAndDrawBurst(ctx, particles: &impactBurst, decay: 0.04)
        updateAndDrawBurst(ctx, particles: &mergeBurst, decay: 0.03)
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
            ctx.saveGState()
            ctx.setFillColor(colorWith(alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            // Tiny white specular
            let specR = r * 0.35
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha * 0.5))
            ctx.fillEllipse(in: CGRect(x: p.x - specR * 0.5, y: p.y - r * 0.5, width: specR, height: specR))
            ctx.restoreGState()

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
            ctx.saveGState()
            ctx.setFillColor(colorWith(alpha: p.life))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()

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

