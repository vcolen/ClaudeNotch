import AppKit
import QuartzCore

@MainActor
enum WaterDropAnimator {

    private static var activeTask: Task<Void, Never>?
    private static var activeDisplayLink: CADisplayLink?

    // MARK: - Animation Geometry

    struct AnimationGeometry: Sendable {
        let rect: CGRect
        let cornerRadius: CGFloat
        let perimeter: CGFloat
        private let lutPoints: [CGPoint]
        private let lutNormals: [CGVector]
        static let lutCount = 256

        init(rect: CGRect, cornerRadius: CGFloat) {
            self.rect = rect
            self.cornerRadius = min(cornerRadius, min(rect.width, rect.height) / 2)
            self.perimeter = Self.perimeter(for: rect, cornerRadius: self.cornerRadius)

            var points = [CGPoint]()
            var normals = [CGVector]()
            points.reserveCapacity(Self.lutCount)
            normals.reserveCapacity(Self.lutCount)

            for i in 0..<Self.lutCount {
                let t = CGFloat(i) / CGFloat(Self.lutCount)
                points.append(Self.computePoint(at: t, rect: rect, cornerRadius: self.cornerRadius, perimeter: self.perimeter))
                normals.append(Self.computeNormal(at: t, rect: rect, cornerRadius: self.cornerRadius, perimeter: self.perimeter))
            }
            self.lutPoints = points
            self.lutNormals = normals
        }

        func pointOnBorder(at t: CGFloat) -> CGPoint {
            let wrapped = Self.wrap(t)
            let index = wrapped * CGFloat(Self.lutCount)
            let i0 = Int(index) % Self.lutCount
            let i1 = (i0 + 1) % Self.lutCount
            let frac = index - CGFloat(i0)
            let p0 = lutPoints[i0]
            let p1 = lutPoints[i1]
            return CGPoint(x: p0.x + (p1.x - p0.x) * frac, y: p0.y + (p1.y - p0.y) * frac)
        }

        func normalOnBorder(at t: CGFloat) -> CGVector {
            let wrapped = Self.wrap(t)
            let index = wrapped * CGFloat(Self.lutCount)
            let i0 = Int(index) % Self.lutCount
            let i1 = (i0 + 1) % Self.lutCount
            let frac = index - CGFloat(i0)
            let n0 = lutNormals[i0]
            let n1 = lutNormals[i1]
            return CGVector(dx: n0.dx + (n1.dx - n0.dx) * frac, dy: n0.dy + (n1.dy - n0.dy) * frac)
        }

        // MARK: Direct computation (LUT building + testing)

        static func perimeter(for rect: CGRect, cornerRadius r: CGFloat) -> CGFloat {
            2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r) + 2 * .pi * r
        }

        /// Maps normalized t (0..1) to a point on the rounded-rect perimeter.
        /// t=0 is top-center, winding clockwise.
        static func computePoint(at t: CGFloat, rect: CGRect, cornerRadius r: CGFloat, perimeter: CGFloat) -> CGPoint {
            let x = rect.origin.x, y = rect.origin.y
            let w = rect.width, h = rect.height

            let wrapped = wrap(t)
            var d = wrapped * perimeter

            let tr = (w / 2) - r            // top-right straight
            let arc = CGFloat.pi * r / 2    // quarter-circle
            let ri = h - 2 * r              // right side
            let bo = w - 2 * r              // bottom
            let le = h - 2 * r              // left side

            let segments: [CGFloat] = [tr, arc, ri, arc, bo, arc, le, arc, tr]
            var s = 0
            while s < segments.count && d > segments[s] {
                d -= segments[s]
                s += 1
            }
            if s >= segments.count { s = segments.count - 1; d = segments[s] }
            let f = segments[s] > 0 ? d / segments[s] : 0

            switch s {
            case 0: return CGPoint(x: x + w / 2 + f * tr, y: y)
            case 1:
                let a = -CGFloat.pi / 2 + f * CGFloat.pi / 2
                return CGPoint(x: x + w - r + cos(a) * r, y: y + r + sin(a) * r)
            case 2: return CGPoint(x: x + w, y: y + r + f * ri)
            case 3:
                let a = f * CGFloat.pi / 2
                return CGPoint(x: x + w - r + cos(a) * r, y: y + h - r + sin(a) * r)
            case 4: return CGPoint(x: x + w - r - f * bo, y: y + h)
            case 5:
                let a = CGFloat.pi / 2 + f * CGFloat.pi / 2
                return CGPoint(x: x + r + cos(a) * r, y: y + h - r + sin(a) * r)
            case 6: return CGPoint(x: x, y: y + h - r - f * le)
            case 7:
                let a = CGFloat.pi + f * CGFloat.pi / 2
                return CGPoint(x: x + r + cos(a) * r, y: y + r + sin(a) * r)
            case 8: return CGPoint(x: x + r + f * tr, y: y)
            default: return CGPoint(x: x + w / 2, y: y)
            }
        }

        static func computeNormal(at t: CGFloat, rect: CGRect, cornerRadius r: CGFloat, perimeter: CGFloat) -> CGVector {
            let dt: CGFloat = 0.003
            let p0 = computePoint(at: t, rect: rect, cornerRadius: r, perimeter: perimeter)
            let t1 = wrap(t + dt)
            let p1 = computePoint(at: t1, rect: rect, cornerRadius: r, perimeter: perimeter)
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let len = hypot(dx, dy)
            guard len > 0 else { return CGVector(dx: 0, dy: -1) }
            // Inward normal: rotate tangent 90° CW (for CW winding in y-down coords)
            return CGVector(dx: -dy / len, dy: dx / len)
        }

        static func projectilePosition(t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let dist = hypot(dx, dy)
            let g = 600 + dist * 1.5
            let vx = dx
            let vy = dy - 0.5 * g
            return CGPoint(
                x: from.x + vx * t,
                y: from.y + vy * t + 0.5 * g * t * t
            )
        }

        static func returnPosition(t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let dist = hypot(dx, dy)
            let g = 500 + dist * 1.2
            let vx = dx
            let vy = dy - 0.5 * g
            return CGPoint(
                x: from.x + vx * t,
                y: from.y + vy * t + 0.5 * g * t * t
            )
        }

        static func wrap(_ t: CGFloat) -> CGFloat {
            let m = t.truncatingRemainder(dividingBy: 1)
            return m < 0 ? m + 1 : m
        }
    }

    // MARK: - Adaptive Scaling

    private static func scaleFactor(for terminalFrame: CGRect) -> CGFloat {
        let minDim = min(terminalFrame.width, terminalFrame.height)
        if minDim < 300 { return 0.6 }
        if minDim > 2500 { return 1.3 }
        return 1.0
    }

    // MARK: - Color Helper

    static func nsColor(for instance: ClaudeInstance) -> NSColor {
        if let attention = instance.attentionType {
            switch attention {
            case .needsInput:
                return NSColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 1.0)
            case .taskFinished:
                return NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
            }
        }
        switch instance.status {
        case .working:
            return NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0)
        case .waitingInput:
            return NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
        case .idle:
            return NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
        }
    }

    // MARK: - Public API

    static func animate(
        from notchCenter: CGPoint,
        to terminalFrame: CGRect,
        terminalWindowNumber: Int,
        color: NSColor,
        on screen: NSScreen
    ) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            WindowHighlighter.flashiTermWindow()
            return
        }

        // Cancel any running animation
        activeTask?.cancel()
        activeDisplayLink?.invalidate()

        let scale = scaleFactor(for: terminalFrame)
        let screenFrame = screen.frame

        // Convert screen coordinates to flipped view coordinates (y=0 at top)
        let viewNotch = CGPoint(
            x: notchCenter.x - screenFrame.origin.x,
            y: screenFrame.maxY - notchCenter.y
        )
        let viewTermRect = CGRect(
            x: terminalFrame.origin.x - screenFrame.origin.x,
            y: screenFrame.maxY - terminalFrame.maxY,
            width: terminalFrame.width,
            height: terminalFrame.height
        )

        let geometry = AnimationGeometry(
            rect: viewTermRect,
            cornerRadius: NotchTokens.Animation.terminalCornerRadius
        )

        // Create overlay window
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        let view = WaterDropView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            notchCenter: viewNotch,
            geometry: geometry,
            color: color,
            scale: scale
        )
        window.contentView = view
        window.orderFrontRegardless()

        let totalDuration = NotchTokens.Animation.waterDropFlightDur
            + NotchTokens.Animation.waterDropImpactDur
            + NotchTokens.Animation.waterDropRaceDur
            + NotchTokens.Animation.waterDropMergeDur
            + NotchTokens.Animation.waterDropReturnDur

        activeTask = Task { @MainActor in
            let displayLink = view.displayLink(target: view, selector: #selector(WaterDropView.handleDisplayLink(_:)))
            displayLink.add(to: .main, forMode: .common)
            activeDisplayLink = displayLink

            defer {
                displayLink.invalidate()
                if activeDisplayLink === displayLink {
                    activeDisplayLink = nil
                }
                window.orderOut(nil)
                if activeTask?.isCancelled == true || activeTask == nil {
                    // Already cleaned up
                } else {
                    activeTask = nil
                }
            }

            try? await Task.sleep(for: .seconds(totalDuration))
        }
    }
}
