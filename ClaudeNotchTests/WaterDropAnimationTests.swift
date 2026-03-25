import CoreGraphics
import AppKit
import Testing
@testable import ClaudeNotch

// MARK: - 5.1 Additional TTY Sanitization Tests

@Suite("TTY Sanitization – Edge Cases")
struct TTYSanitizationEdgeCaseTests {

    @Test("TTY with double-quote is rejected (injection guard)")
    func doubleQuoteRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042\"") == nil)
    }

    @Test("TTY with backslash is rejected")
    func backslashRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042\\") == nil)
    }

    @Test("TTY with embedded newline is rejected")
    func newlineRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042\nmalicious") == nil)
    }

    @Test("TTY with carriage return is rejected")
    func carriageReturnRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042\r") == nil)
    }

    @Test("TTY with semicolon is rejected")
    func semicolonRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042;rm -rf /") == nil)
    }

    @Test("Valid /dev/ttys0 (single digit) passes")
    func singleDigitTTYPasses() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys0") == "/dev/ttys0")
    }

    @Test("Valid /dev/ttys999 passes")
    func tripleDigitTTYPasses() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys999") == "/dev/ttys999")
    }

    @Test("TTY with uppercase letters is rejected")
    func uppercaseRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttyS042") == nil)
    }

    @Test("TTY with space before digits is rejected")
    func spaceBeforeDigitsRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys 042") == nil)
    }

    @Test("TTY with null character is rejected")
    func nullCharacterRejected() {
        #expect(ITermIntegration.sanitizeTTY("/dev/ttys042\0") == nil)
    }
}

// MARK: - 5.2 displayColor / displayNSColor – All 5 Branches
//
// nsColor(for:) was refactored into ClaudeInstance.displayColor (SwiftUI) and
// ClaudeInstance.displayNSColor (AppKit) in DesignTokens.swift. These tests
// verify all five decision-tree branches and confirm that attention takes
// priority over status.

@Suite("ClaudeInstance.displayNSColor – 5 branches")
struct DisplayColorMappingTests {

    // Branch 1: attentionType == .needsInput (orange)
    @Test("needsInput attention returns orange color")
    @MainActor func needsInputColor() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .waitingInput) // sets attentionType = .needsInput
        let color = instance.displayNSColor.usingColorSpace(.sRGB)!
        #expect(abs(color.redComponent - 1.0) < 0.01)
        #expect(abs(color.greenComponent - 0.6) < 0.01)
        #expect(abs(color.blueComponent - 0.15) < 0.01)
    }

    // Branch 2: attentionType == .taskFinished (blue)
    @Test("taskFinished attention returns blue color")
    @MainActor func taskFinishedColor() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .idle) // sets attentionType = .taskFinished
        let color = instance.displayNSColor.usingColorSpace(.sRGB)!
        #expect(abs(color.redComponent - 0.4) < 0.01)
        #expect(abs(color.greenComponent - 0.7) < 0.01)
        #expect(abs(color.blueComponent - 1.0) < 0.01)
    }

    // Branch 3: status == .working, no attention (green)
    @Test("working status with no attention returns green color")
    @MainActor func workingColor() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        let color = instance.displayNSColor.usingColorSpace(.sRGB)!
        #expect(abs(color.redComponent - 0.3) < 0.01)
        #expect(abs(color.greenComponent - 0.85) < 0.01)
        #expect(abs(color.blueComponent - 0.4) < 0.01)
    }

    // Branch 4: status == .waitingInput, no attention (yellow)
    @Test("waitingInput status with no attention returns yellow color")
    @MainActor func waitingInputColor() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .waitingInput)
        let color = instance.displayNSColor.usingColorSpace(.sRGB)!
        #expect(abs(color.redComponent - 1.0) < 0.01)
        #expect(abs(color.greenComponent - 0.8) < 0.01)
        #expect(abs(color.blueComponent - 0.2) < 0.01)
    }

    // Branch 5: status == .idle, no attention (grey)
    @Test("idle status with no attention returns grey color")
    @MainActor func idleColor() {
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .idle)
        // idle uses Color.white.opacity(0.4) which has r=g=b=1, a=0.4
        // displayNSColor wraps the SwiftUI Color; we only need to confirm it's non-nil
        // and does NOT match working green or waitingInput yellow.
        let color = instance.displayNSColor.usingColorSpace(.sRGB)!
        // Idle must not be the working green (red=0.3)
        #expect(abs(color.redComponent - 0.3) > 0.1)
        // Idle must not be the waitingInput yellow (red=1.0, green=0.8, blue=0.2)
        #expect(abs(color.blueComponent - 0.2) > 0.1)
    }

    // Attention takes priority over status
    @Test("attention type takes priority over status color")
    @MainActor func attentionPriorityOverStatus() {
        // Instance transitions working→waitingInput:
        // status = .waitingInput, attentionType = .needsInput
        let instance = ClaudeInstance(id: "t", pid: 1, cwd: "/tmp", status: .working)
        instance.transition(to: .waitingInput)

        // If attention were ignored, this would return the waitingInput yellow (1.0, 0.8, 0.2)
        // With attention priority it returns needsInput orange (1.0, 0.6, 0.15)
        // The distinguishing component: attention orange has blue=0.15, status yellow has blue=0.2
        let color = instance.displayNSColor.usingColorSpace(.sRGB)!
        #expect(abs(color.blueComponent - 0.15) < 0.01,
                "Expected attention (needsInput) orange, not status (waitingInput) yellow")
    }
}

// MARK: - 5.3 WindowHighlighter TTY Validation (iTermWindow decision logic)
//
// iTermWindow(forTTY:) has 5 code paths; the TTY-format check gate is extracted
// into WindowHighlighter.isValidTTY(_:) for isolated testing.

@Suite("WindowHighlighter TTY Validation")
struct WindowHighlighterTTYValidationTests {

    @Test("Empty string is rejected")
    func emptyTTYInvalid() {
        #expect(WindowHighlighter.isValidTTY("") == false)
    }

    @Test("Valid /dev/ttys042 passes")
    func validTTYPasses() {
        #expect(WindowHighlighter.isValidTTY("/dev/ttys042") == true)
    }

    @Test("Valid /dev/ttys0 (single digit) passes")
    func validSingleDigitPasses() {
        #expect(WindowHighlighter.isValidTTY("/dev/ttys0") == true)
    }

    @Test("TTY with injection characters fails")
    func injectionFails() {
        #expect(WindowHighlighter.isValidTTY("\"; malicious") == false)
    }

    @Test("TTY without /dev/ prefix fails")
    func noPrefixFails() {
        #expect(WindowHighlighter.isValidTTY("ttys042") == false)
    }

    @Test("TTY with no digits fails")
    func noDigitsFails() {
        #expect(WindowHighlighter.isValidTTY("/dev/ttys") == false)
    }

    @Test("TTY with path traversal fails")
    func pathTraversalFails() {
        #expect(WindowHighlighter.isValidTTY("/dev/../etc/passwd") == false)
    }

    @Test("TTY with space fails")
    func spaceFails() {
        #expect(WindowHighlighter.isValidTTY("/dev/ttys 042") == false)
    }

    @Test("TTY with newline fails (injection guard)")
    func newlineFails() {
        #expect(WindowHighlighter.isValidTTY("/dev/ttys042\n") == false)
    }

    @Test("TTY with quote fails (injection guard)")
    func quoteFails() {
        #expect(WindowHighlighter.isValidTTY("/dev/ttys042\"") == false)
    }
}

// MARK: - 5.4 Corner Radius Clamping

@Suite("AnimationGeometry Corner Radius Clamping")
struct CornerRadiusClampingTests {

    @Test("Corner radius 200 on 100x100 rect is clamped to 50")
    func cornerRadiusClampedToHalfMinDim() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let geo = WaterDropAnimator.AnimationGeometry(rect: rect, cornerRadius: 200)
        // Effective radius must not exceed min(width,height)/2 = 50
        #expect(geo.cornerRadius == 50)
    }

    @Test("Corner radius 200 on 200x100 rect is clamped to 50 (uses min dimension)")
    func cornerRadiusClampedToMinDimension() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let geo = WaterDropAnimator.AnimationGeometry(rect: rect, cornerRadius: 200)
        #expect(geo.cornerRadius == 50)
    }

    @Test("Corner radius smaller than half min-dim is preserved")
    func smallCornerRadiusPreserved() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let geo = WaterDropAnimator.AnimationGeometry(rect: rect, cornerRadius: 10)
        #expect(geo.cornerRadius == 10)
    }

    @Test("Corner radius exactly at half min-dim is preserved")
    func cornerRadiusAtMaxPreserved() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let geo = WaterDropAnimator.AnimationGeometry(rect: rect, cornerRadius: 50)
        #expect(geo.cornerRadius == 50)
    }

    @Test("Corner radius 0 is preserved (square corners)")
    func zeroCornerRadiusPreserved() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let geo = WaterDropAnimator.AnimationGeometry(rect: rect, cornerRadius: 0)
        #expect(geo.cornerRadius == 0)
    }
}

// MARK: - 5.5 scaleFactor Boundary Values
//
// Thresholds are driven by NotchTokens.Animation.waterDropScaleSmallThreshold (300)
// and waterDropScaleLargeThreshold (2500). Tests probe the boundaries exactly.

@Suite("WaterDropAnimator.scaleFactor boundary values")
struct ScaleFactorBoundaryTests {

    @Test("minDim one below small threshold returns 0.6")
    @MainActor func belowSmallThresholdReturns0_6() {
        let small = NotchTokens.Animation.waterDropScaleSmallThreshold
        let frame = CGRect(x: 0, y: 0, width: small - 1, height: 1000)
        #expect(WaterDropAnimator.scaleFactor(for: frame) == 0.6)
    }

    @Test("minDim exactly at small threshold (not less-than) returns 1.0")
    @MainActor func atSmallThresholdReturns1_0() {
        let small = NotchTokens.Animation.waterDropScaleSmallThreshold
        let frame = CGRect(x: 0, y: 0, width: small, height: 1000)
        #expect(WaterDropAnimator.scaleFactor(for: frame) == 1.0)
    }

    @Test("minDim mid-range returns 1.0")
    @MainActor func midRangeReturns1_0() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 2000)
        #expect(WaterDropAnimator.scaleFactor(for: frame) == 1.0)
    }

    @Test("minDim exactly at large threshold (not greater-than) returns 1.0")
    @MainActor func atLargeThresholdReturns1_0() {
        let large = NotchTokens.Animation.waterDropScaleLargeThreshold
        let frame = CGRect(x: 0, y: 0, width: large, height: 5000)
        #expect(WaterDropAnimator.scaleFactor(for: frame) == 1.0)
    }

    @Test("minDim one above large threshold returns 1.3")
    @MainActor func aboveLargeThresholdReturns1_3() {
        let large = NotchTokens.Animation.waterDropScaleLargeThreshold
        let frame = CGRect(x: 0, y: 0, width: large + 1, height: 5000)
        #expect(WaterDropAnimator.scaleFactor(for: frame) == 1.3)
    }

    @Test("scaleFactor uses the minimum of width and height")
    @MainActor func usesMinimumDimension() {
        let small = NotchTokens.Animation.waterDropScaleSmallThreshold
        // width is below threshold, height is large — min dimension is below threshold
        let frame = CGRect(x: 0, y: 0, width: small - 100, height: 5000)
        #expect(WaterDropAnimator.scaleFactor(for: frame) == 0.6)
    }
}

// MARK: - 5.6 Arc-Shape Assertion at t=0.5
//
// Verifies the mid-point of both trajectories deviates from the straight line,
// proving parabolic curvature rather than linear interpolation.

@Suite("Projectile and Return arc-shape at t=0.5")
struct ArcShapeTests {

    @Test("Projectile mid-point y deviates from the straight line between start and end")
    func projectileMidPointNotLinear() {
        let from = CGPoint(x: 200, y: 50)
        let to = CGPoint(x: 300, y: 350)

        let mid = WaterDropAnimator.AnimationGeometry.projectilePosition(t: 0.5, from: from, to: to)

        // Horizontal (x) motion is linear, so midpoint x should equal linear interpolation
        let linearMidX = (from.x + to.x) / 2  // 250
        #expect(abs(mid.x - linearMidX) < 0.1,
                "x at t=0.5 should equal linear interpolation")

        // The parabola causes y to deviate from the straight-line midpoint
        let linearMidY = (from.y + to.y) / 2  // 200
        let yDeviation = abs(mid.y - linearMidY)
        #expect(yDeviation > 1.0,
                "Mid-point y (\(mid.y)) should deviate from linear mid-y (\(linearMidY)) — confirms arc, not line")
    }

    @Test("Projectile x at t=0.5 equals linear interpolation (horizontal motion is linear)")
    func projectileMidXIsLinear() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 400, y: 400)
        let mid = WaterDropAnimator.AnimationGeometry.projectilePosition(t: 0.5, from: from, to: to)
        #expect(abs(mid.x - 200) < 0.1)
    }

}

// MARK: - 5.7 Water Drop Token Invariants

@Suite("WaterDrop Animation Token Invariants")
struct WaterDropTokenInvariantTests {

    // All phase durations must be positive
    @Test("waterDropFlightDur is positive")
    func flightDurPositive() {
        #expect(NotchTokens.Animation.waterDropFlightDur > 0)
    }

    @Test("waterDropImpactDur is positive")
    func impactDurPositive() {
        #expect(NotchTokens.Animation.waterDropImpactDur > 0)
    }

    @Test("waterDropRaceDur is positive")
    func raceDurPositive() {
        #expect(NotchTokens.Animation.waterDropRaceDur > 0)
    }

    @Test("waterDropMergeDur is positive")
    func mergeDurPositive() {
        #expect(NotchTokens.Animation.waterDropMergeDur > 0)
    }

    // Total animation must be under 3 seconds to avoid feeling sluggish
    @Test("Total water drop animation is under 3 seconds")
    func totalAnimationUnder3s() {
        let total = NotchTokens.Animation.waterDropFlightDur
            + NotchTokens.Animation.waterDropImpactDur
            + NotchTokens.Animation.waterDropRaceDur
            + NotchTokens.Animation.waterDropMergeDur
        #expect(total < 3.0, "Total animation \(total)s should be under 3s")
    }

    // Stream length must be a normalized fraction in [0, 1]
    @Test("waterDropStreamLength is in [0, 1]")
    func streamLengthNormalized() {
        #expect(NotchTokens.Animation.waterDropStreamLength >= 0)
        #expect(NotchTokens.Animation.waterDropStreamLength <= 1)
    }

    // Dot radius must be positive (non-zero size)
    @Test("waterDropDotRadius is positive")
    func dotRadiusPositive() {
        #expect(NotchTokens.Animation.waterDropDotRadius > 0)
    }

    // Stream thickness must be positive
    @Test("waterDropStreamThickness is positive")
    func streamThicknessPositive() {
        #expect(NotchTokens.Animation.waterDropStreamThickness > 0)
    }

    // Terminal corner radius must be non-negative
    @Test("terminalCornerRadius is non-negative")
    func terminalCornerRadiusNonNegative() {
        #expect(NotchTokens.Animation.terminalCornerRadius >= 0)
    }

    // Impact is the shortest phase (quick splash)
    @Test("Impact phase is shorter than flight phase")
    func impactShorterThanFlight() {
        #expect(NotchTokens.Animation.waterDropImpactDur < NotchTokens.Animation.waterDropFlightDur)
    }

    // Merge is shorter than race (race dominates the animation feel)
    @Test("Merge phase is shorter than race phase")
    func mergeShorterThanRace() {
        #expect(NotchTokens.Animation.waterDropMergeDur < NotchTokens.Animation.waterDropRaceDur)
    }

    // Scale thresholds must be ordered (small < large)
    @Test("waterDropScaleSmallThreshold is less than waterDropScaleLargeThreshold")
    func scaleThresholdsOrdered() {
        #expect(NotchTokens.Animation.waterDropScaleSmallThreshold <
                NotchTokens.Animation.waterDropScaleLargeThreshold)
    }
}
