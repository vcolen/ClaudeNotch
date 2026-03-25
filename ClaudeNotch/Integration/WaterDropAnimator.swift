import AppKit
import QuartzCore
import os.log

/// Singleton animation coordinator that drives the water-drop selection effect.
///
/// **Responsibility:** `WaterDropAnimator` owns the overlay `NSWindow` and the
/// `CADisplayLink`/`Task` pair for a single animation run. Only one animation runs at
/// a time; calling `animate(...)` while an animation is in flight cancels the previous one.
///
/// **Reduce-motion:** When `NSWorkspace.accessibilityDisplayShouldReduceMotion` is `true`,
/// `animate(...)` falls back to a plain `WindowHighlighter.flashiTermWindow()` call and
/// returns immediately without creating any view or task.
///
/// **5-phase lifecycle** — see `WaterDropView` for per-phase rendering details.
@MainActor
enum WaterDropAnimator {

    private static let log = Logger(subsystem: "com.claudenotch", category: "WaterDropAnimator")

    private struct RunningAnimation {
        let task: Task<Void, Never>
        let displayLink: CADisplayLink
        let window: NSWindow
    }
    private static var running: RunningAnimation?

    // MARK: - Animation Geometry

    /// Precomputed lookup table (LUT) for positions and inward normals along a rounded-rect perimeter.
    ///
    /// Computing exact perimeter coordinates involves arc-length parameterization and trig.
    /// `AnimationGeometry` builds `lutCount` (256) evenly-spaced samples once at init time.
    /// Per-frame queries use linear interpolation between adjacent samples, keeping each
    /// frame's cost O(1).
    struct AnimationGeometry: Sendable {
        let rect: CGRect
        let cornerRadius: CGFloat
        let perimeter: CGFloat
        private let lutPoints: [CGPoint]
        private let lutNormals: [CGVector]
        /// Number of evenly-spaced LUT samples covering the full perimeter (t ∈ [0, 1)).
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
        /// t=0 is top-center, winding clockwise (y-down screen coords).
        ///
        /// The perimeter is divided into **9 segments** rather than the usual 8 because
        /// the top edge is split at its midpoint to place t=0 at top-center (above the notch):
        ///
        /// - 0: top-right half-edge (center → top-right corner tangent)
        /// - 1: top-right arc (quarter-circle)
        /// - 2: right edge (top-right → bottom-right corner tangent)
        /// - 3: bottom-right arc (quarter-circle)
        /// - 4: bottom edge (right → left)
        /// - 5: bottom-left arc (quarter-circle)
        /// - 6: left edge (bottom-left → top-left corner tangent)
        /// - 7: top-left arc (quarter-circle)
        /// - 8: top-left half-edge (top-left corner tangent → center)
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

        /// Computes the inward-pointing unit normal at parameter `t` using forward finite differences.
        ///
        /// The tangent is estimated by sampling `computePoint` at `t` and `t + dt` (dt = 0.003),
        /// which is small enough to stay within a single segment on any realistically sized terminal.
        /// Because the perimeter winds **clockwise** in y-down screen coordinates, rotating the
        /// tangent 90° clockwise (`dx, dy → -dy, dx`) yields a vector pointing inward (toward
        /// the rect's center). The result depends on `isFlipped` being `true` on `WaterDropView`,
        /// which establishes the y-down coordinate system.
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

        static func wrap(_ t: CGFloat) -> CGFloat {
            let m = t.truncatingRemainder(dividingBy: 1)
            return m < 0 ? m + 1 : m
        }

        // MARK: - Trajectory Helpers

        /// Shared parabolic arc formula used by both outbound and return trajectories.
        ///
        /// Models projectile motion: constant horizontal velocity plus a quadratic vertical term.
        /// Gravity `g = gravityBase + distance × gravityScale` scales with the travel distance so
        /// the arc curvature looks proportionate regardless of notch-to-terminal layout.
        static func parabolicArc(t: CGFloat, from: CGPoint, to: CGPoint,
                                 gravityBase: CGFloat, gravityScale: CGFloat) -> CGPoint {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let dist = hypot(dx, dy)
            let g = gravityBase + dist * gravityScale
            let vx = dx
            let vy = dy - 0.5 * g
            return CGPoint(
                x: from.x + vx * t,
                y: from.y + vy * t + 0.5 * g * t * t
            )
        }

        /// Parabolic arc for the outbound (notch → terminal border) flight.
        static func projectilePosition(t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
            parabolicArc(t: t, from: from, to: to, gravityBase: 600, gravityScale: 1.5)
        }

        /// Parabolic arc for the return (terminal border → notch) flight.
        /// Uses a lower base gravity (500 vs 600) for a gentler, floatier feel.
        static func returnPosition(t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
            parabolicArc(t: t, from: from, to: to, gravityBase: 500, gravityScale: 1.2)
        }
    }

    // MARK: - Adaptive Scaling

    static func scaleFactor(for terminalFrame: CGRect) -> CGFloat {
        let minDim = min(terminalFrame.width, terminalFrame.height)
        if minDim < NotchTokens.Animation.waterDropScaleSmallThreshold { return 0.6 }
        if minDim > NotchTokens.Animation.waterDropScaleLargeThreshold { return 1.3 }
        return 1.0
    }

    // MARK: - Public API

    static func animate(
        from clickOrigin: CGPoint,
        to terminalFrame: CGRect,
        color: NSColor,
        on screen: NSScreen
    ) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            WindowHighlighter.flashiTermWindow()
            return
        }

        // Cancel any running animation and tear down its window immediately
        // to prevent a brief overlap with the new overlay window.
        running?.task.cancel()
        running?.displayLink.invalidate()
        running?.window.orderOut(nil)
        running = nil

        let scale = scaleFactor(for: terminalFrame)
        let screenFrame = screen.frame

        // Convert screen coordinates to flipped view coordinates (y=0 at top)
        let viewOrigin = CGPoint(
            x: clickOrigin.x - screenFrame.origin.x,
            y: screenFrame.maxY - clickOrigin.y
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
            notchCenter: viewOrigin,
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

        let task = Task { @MainActor in
            defer {
                running?.displayLink.invalidate()
                running?.window.orderOut(nil)
                running = nil
            }

            do {
                try await Task.sleep(for: .seconds(totalDuration))
            } catch is CancellationError {
                // Normal cancellation (e.g. new animation started): clean up via defer
            } catch {
                log.error("Unexpected error in animation timer: \(error, privacy: .public)")
            }
        }

        let displayLink = view.displayLink(target: view, selector: #selector(WaterDropView.handleDisplayLink(_:)))
        displayLink.add(to: .main, forMode: .common)
        running = RunningAnimation(task: task, displayLink: displayLink, window: window)
    }
}
