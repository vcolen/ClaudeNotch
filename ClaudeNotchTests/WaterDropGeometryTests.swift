import CoreGraphics
import Testing
@testable import ClaudeNotch

@Suite("WaterDrop AnimationGeometry")
struct WaterDropGeometryTests {

    private let rect = CGRect(x: 100, y: 200, width: 400, height: 300)
    private let r: CGFloat = 10

    private var geometry: WaterDropAnimator.AnimationGeometry {
        WaterDropAnimator.AnimationGeometry(rect: rect, cornerRadius: r)
    }

    private var perimeter: CGFloat {
        WaterDropAnimator.AnimationGeometry.perimeter(for: rect, cornerRadius: r)
    }

    // MARK: - pointOnBorder

    @Test("t=0 maps to top-center")
    func topCenter() {
        let p = geometry.pointOnBorder(at: 0)
        #expect(abs(p.x - (rect.midX)) < 1)
        #expect(abs(p.y - rect.minY) < 1)
    }

    @Test("t=0.5 maps to bottom-center")
    func bottomCenter() {
        let p = geometry.pointOnBorder(at: 0.5)
        #expect(abs(p.x - (rect.midX)) < 2)
        #expect(abs(p.y - rect.maxY) < 2)
    }

    @Test("t=1.0 wraps back to top-center")
    func fullLoop() {
        let p0 = geometry.pointOnBorder(at: 0)
        let p1 = geometry.pointOnBorder(at: 1.0)
        #expect(abs(p0.x - p1.x) < 1)
        #expect(abs(p0.y - p1.y) < 1)
    }

    @Test("t=0.25 is on the right side")
    func rightSide() {
        let p = geometry.pointOnBorder(at: 0.25)
        #expect(p.x > rect.midX)
    }

    // MARK: - normalOnBorder

    @Test("Normal at top-center points inward (downward in y-down coords)")
    func normalTopCenter() {
        let n = geometry.normalOnBorder(at: 0)
        // Inward from top edge → positive dy (pointing into the rect)
        #expect(n.dy > 0)
    }

    @Test("Normal at bottom-center points inward (upward)")
    func normalBottomCenter() {
        let n = geometry.normalOnBorder(at: 0.5)
        #expect(n.dy < 0)
    }

    @Test("Normal vectors are roughly unit length")
    func normalUnitLength() {
        for t in stride(from: 0.0, to: 1.0, by: 0.1) {
            let n = geometry.normalOnBorder(at: CGFloat(t))
            let len = hypot(n.dx, n.dy)
            #expect(abs(len - 1.0) < 0.1, "Normal at t=\(t) has length \(len)")
        }
    }

    // MARK: - projectilePosition

    @Test("Projectile at t=0 equals start point")
    func projectileStart() {
        let from = CGPoint(x: 200, y: 50)
        let to = CGPoint(x: 300, y: 350)
        let pos = WaterDropAnimator.AnimationGeometry.projectilePosition(t: 0, from: from, to: to)
        #expect(abs(pos.x - from.x) < 0.001)
        #expect(abs(pos.y - from.y) < 0.001)
    }

    @Test("Projectile at t=1 equals end point")
    func projectileEnd() {
        let from = CGPoint(x: 200, y: 50)
        let to = CGPoint(x: 300, y: 350)
        let pos = WaterDropAnimator.AnimationGeometry.projectilePosition(t: 1, from: from, to: to)
        #expect(abs(pos.x - to.x) < 0.001)
        #expect(abs(pos.y - to.y) < 0.001)
    }

    // MARK: - LUT vs direct computation

    @Test("LUT values match direct computation within 1px")
    func lutMatchesDirect() {
        let geo = geometry
        for i in 0..<WaterDropAnimator.AnimationGeometry.lutCount {
            let t = CGFloat(i) / CGFloat(WaterDropAnimator.AnimationGeometry.lutCount)
            let lutPt = geo.pointOnBorder(at: t)
            let directPt = WaterDropAnimator.AnimationGeometry.computePoint(
                at: t, rect: rect, cornerRadius: r, perimeter: perimeter
            )
            #expect(abs(lutPt.x - directPt.x) < 1, "LUT x mismatch at t=\(t)")
            #expect(abs(lutPt.y - directPt.y) < 1, "LUT y mismatch at t=\(t)")
        }
    }

    @Test("LUT normals match direct computation")
    func lutNormalsMatchDirect() {
        let geo = geometry
        for i in stride(from: 0, to: WaterDropAnimator.AnimationGeometry.lutCount, by: 16) {
            let t = CGFloat(i) / CGFloat(WaterDropAnimator.AnimationGeometry.lutCount)
            let lutN = geo.normalOnBorder(at: t)
            let directN = WaterDropAnimator.AnimationGeometry.computeNormal(
                at: t, rect: rect, cornerRadius: r, perimeter: perimeter
            )
            #expect(abs(lutN.dx - directN.dx) < 0.1, "LUT normal dx mismatch at t=\(t)")
            #expect(abs(lutN.dy - directN.dy) < 0.1, "LUT normal dy mismatch at t=\(t)")
        }
    }

    // MARK: - Perimeter

    @Test("Perimeter is positive and reasonable")
    func perimeterReasonable() {
        let p = perimeter
        let approxPerimeter = 2 * (rect.width + rect.height) // upper bound (no corner rounding)
        #expect(p > 0)
        #expect(p < approxPerimeter)
    }

    // MARK: - wrap

    @Test("wrap keeps values in [0,1)")
    func wrapBounds() {
        #expect(WaterDropAnimator.AnimationGeometry.wrap(0.5) == 0.5)
        #expect(abs(WaterDropAnimator.AnimationGeometry.wrap(1.5) - 0.5) < 0.001)
        #expect(abs(WaterDropAnimator.AnimationGeometry.wrap(-0.25) - 0.75) < 0.001)
    }
}
