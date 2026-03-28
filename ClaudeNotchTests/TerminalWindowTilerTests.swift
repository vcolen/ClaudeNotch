import CoreGraphics
import Testing
@testable import ClaudeNotch

@Suite("TerminalWindowTiler Layout Table")
struct TilerLayoutTableTests {

    @Test("Layout table covers counts 1 through 10")
    func allCountsCovered() {
        for count in 1...10 {
            let layouts = TerminalWindowTiler.layouts(for: count)
            #expect(!layouts.isEmpty, "No layouts for count \(count)")
        }
    }

    @Test("Each layout row sums to window count")
    func rowsSumToCount() {
        for count in 1...10 {
            for layout in TerminalWindowTiler.layouts(for: count) {
                let sum = layout.reduce(0, +)
                #expect(sum == count, "Layout \(layout) sums to \(sum), expected \(count)")
            }
        }
    }

    @Test("No row exceeds 5 windows")
    func maxFivePerRow() {
        for count in 1...10 {
            for layout in TerminalWindowTiler.layouts(for: count) {
                for row in layout {
                    #expect(row <= 5, "Row has \(row) windows, max is 5")
                }
            }
        }
    }

    @Test("Count 0 returns empty array")
    func zeroWindows() {
        let layouts = TerminalWindowTiler.layouts(for: 0)
        #expect(layouts.isEmpty)
    }

    @Test("Negative count returns empty array")
    func negativeCount() {
        let layouts = TerminalWindowTiler.layouts(for: -1)
        #expect(layouts.isEmpty)
    }

    @Test("Count >10 returns layouts for 10")
    func overTenFallback() {
        let layouts = TerminalWindowTiler.layouts(for: 12)
        let expected = TerminalWindowTiler.layouts(for: 10)
        #expect(layouts == expected)
    }

    @Test("Default layout for 7 is [3,4]")
    func sevenDefault() {
        let layouts = TerminalWindowTiler.layouts(for: 7)
        #expect(layouts[0] == [3, 4])
    }
}

@Suite("TerminalWindowTiler Frame Calculation")
struct TilerFrameTests {

    private let screenRect = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test("Empty layout returns empty frames")
    func emptyLayout() {
        let frames = TerminalWindowTiler.computeFrames(layout: [], in: screenRect, gap: 0)
        #expect(frames.isEmpty)
    }

    @Test("Single window fills the screen rect")
    func singleWindow() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [1], in: screenRect, gap: 0
        )
        #expect(frames.count == 1)
        #expect(frames[0] == screenRect)
    }

    @Test("Two columns split width equally")
    func twoColumns() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [2], in: screenRect, gap: 0
        )
        #expect(frames.count == 2)
        #expect(frames[0].width == 500)
        #expect(frames[1].width == 500)
        #expect(frames[0].height == 600)
    }

    @Test("2x2 grid produces 4 equal rects")
    func twoByTwoGrid() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [2, 2], in: screenRect, gap: 0
        )
        #expect(frames.count == 4)
        for frame in frames {
            #expect(frame.width == 500)
            #expect(frame.height == 300)
        }
    }

    @Test("Gaps reduce window size correctly")
    func gapsApplied() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [2], in: screenRect, gap: 12
        )
        #expect(frames.count == 2)
        // Total width: 1000 - 12 gap between = 988 / 2 = 494 each
        #expect(frames[0].width == 494)
        #expect(frames[1].width == 494)
        // First window at x=0, second at 494+12 = 506
        #expect(frames[0].origin.x == 0)
        #expect(frames[1].origin.x == 506)
    }

    @Test("3+2 layout produces correct frame count and row heights")
    func threeAndTwo() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [3, 2], in: CGRect(x: 0, y: 0, width: 1200, height: 800), gap: 0
        )
        #expect(frames.count == 5)
        // Top row: 3 windows, width 400 each, height 400
        #expect(frames[0].width == 400)
        #expect(frames[0].height == 400)
        // Bottom row: 2 windows, width 600 each, height 400
        #expect(frames[3].width == 600)
        #expect(frames[3].height == 400)
    }

    @Test("Frame origins use top-left coordinate system")
    func topLeftOrigin() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [2, 2], in: CGRect(x: 50, y: 100, width: 1000, height: 600), gap: 0
        )
        // Top-left window
        #expect(frames[0].origin.x == 50)
        #expect(frames[0].origin.y == 100)
        // Bottom-left window
        #expect(frames[2].origin.x == 50)
        #expect(frames[2].origin.y == 400)
    }

    @Test("2x2 layout with gap applies row and column gaps correctly")
    func twoByTwoWithGap() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [2, 2], in: CGRect(x: 0, y: 0, width: 1000, height: 600), gap: 10
        )
        #expect(frames.count == 4)
        // Row height: (600 - 10 gap) / 2 = 295
        #expect(frames[0].height == 295)
        // Col width: (1000 - 10 gap) / 2 = 495
        #expect(frames[0].width == 495)
        // Second row starts at y = 295 + 10 = 305
        #expect(frames[2].origin.y == 305)
        // Second column starts at x = 495 + 10 = 505
        #expect(frames[1].origin.x == 505)
    }

    @Test("Single-column multi-row layout produces correct frames")
    func singleColumnMultiRow() {
        let frames = TerminalWindowTiler.computeFrames(
            layout: [1, 1], in: CGRect(x: 0, y: 0, width: 800, height: 600), gap: 10
        )
        #expect(frames.count == 2)
        // Each window should fill the full width (1 column, no column gap)
        #expect(frames[0].width == 800)
        #expect(frames[1].width == 800)
        // Row height: (600 - 10 gap) / 2 = 295
        #expect(frames[0].height == 295)
        #expect(frames[1].height == 295)
        // First row at y=0, second at 295+10=305
        #expect(frames[0].origin.y == 0)
        #expect(frames[1].origin.y == 305)
    }
}

@Suite("TerminalWindowTiler Window Filtering")
struct TilerWindowFilterTests {

    @Test("isTerminalApp matches iTerm2")
    func matchesiTerm() {
        #expect(TerminalWindowTiler.isTerminalApp("iTerm2"))
    }

    @Test("isTerminalApp matches Terminal")
    func matchesTerminal() {
        #expect(TerminalWindowTiler.isTerminalApp("Terminal"))
    }

    @Test("isTerminalApp rejects other apps")
    func rejectsOther() {
        #expect(!TerminalWindowTiler.isTerminalApp("Safari"))
        #expect(!TerminalWindowTiler.isTerminalApp("Finder"))
        #expect(!TerminalWindowTiler.isTerminalApp(""))
    }

    @Test("WindowInfo initializes from valid dictionary")
    func validDictInit() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowOwnerName as String: "iTerm2",
            kCGWindowLayer as String: 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info != nil)
        #expect(info?.pid == 1234)
        #expect(info?.windowID == 42)
        #expect(info?.bounds == CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    @Test("WindowInfo rejects non-zero layer")
    func rejectsNonZeroLayer() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowOwnerName as String: "iTerm2",
            kCGWindowLayer as String: 1,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects non-terminal apps")
    func rejectsNonTerminal() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowOwnerName as String: "Safari",
            kCGWindowLayer as String: 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects empty dictionary")
    func rejectsEmptyDict() {
        let info = TerminalWindowTiler.WindowInfo(from: [:])
        #expect(info == nil)
    }

    @Test("WindowInfo rejects missing bounds key")
    func rejectsMissingBounds() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowOwnerName as String: "iTerm2",
            kCGWindowLayer as String: 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects malformed bounds dict")
    func rejectsMalformedBounds() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowOwnerName as String: "iTerm2",
            kCGWindowLayer as String: 0,
            kCGWindowBounds as String: ["X": 100, "Y": 200],  // missing Width and Height
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects missing PID")
    func rejectsMissingPID() {
        let dict: [String: Any] = [
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowOwnerName as String: "iTerm2",
            kCGWindowLayer as String: 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects missing window number")
    func rejectsMissingWindowNumber() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowOwnerName as String: "iTerm2",
            kCGWindowLayer as String: 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects missing owner name")
    func rejectsMissingOwnerName() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowLayer as String: 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects missing layer")
    func rejectsMissingLayer() {
        let dict: [String: Any] = [
            kCGWindowOwnerPID as String: 1234,
            kCGWindowNumber as String: 42,
            kCGWindowBounds as String: ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            kCGWindowOwnerName as String: "iTerm2",
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }
}

@Suite("TerminalWindowTiler Cycling")
struct TilerCyclingTests {

    @Test("nextLayoutIndex wraps around")
    func wrapsAround() {
        // 7 windows has 3 layouts: [3,4], [4,3], [3,2,2]
        #expect(TerminalWindowTiler.nextLayoutIndex(current: 0, forCount: 7) == 1)
        #expect(TerminalWindowTiler.nextLayoutIndex(current: 1, forCount: 7) == 2)
        #expect(TerminalWindowTiler.nextLayoutIndex(current: 2, forCount: 7) == 0)
    }

    @Test("nextLayoutIndex for single layout stays at 0")
    func singleLayout() {
        // 1 window has 1 layout: [1]
        #expect(TerminalWindowTiler.nextLayoutIndex(current: 0, forCount: 1) == 0)
    }

    @Test("nextLayoutIndex for count 0 returns 0")
    func zeroCount() {
        #expect(TerminalWindowTiler.nextLayoutIndex(current: 0, forCount: 0) == 0)
    }

    @Test("nextLayoutIndex for negative count returns 0")
    func negativeCount() {
        #expect(TerminalWindowTiler.nextLayoutIndex(current: 0, forCount: -1) == 0)
    }
}

@Suite("TerminalWindowTiler Coordinate Conversion")
struct TilerCoordinateTests {

    @Test("topLeftY converts bottom-left to top-left origin")
    func topLeftConversion() {
        // NSScreen cannot be constructed in tests, so we verify the coordinate math directly.
        // Simulate a 1440x900 screen with a 25px menu bar
        // visibleFrame in Cocoa coords: origin at (0, 0), size 1440x875 (900-25 menu bar)
        // Expected top-left: origin at (0, 25), size 1440x875
        let topLeftY = TerminalWindowTiler.topLeftY(
            fullHeight: 900, visibleOriginY: 0, visibleHeight: 875, fullOriginY: 0
        )
        #expect(topLeftY == 25)
    }

    @Test("topLeftY accounts for non-primary monitor offset")
    func nonPrimaryMonitorOffset() {
        // Non-primary monitor at y=-900 in Cocoa coords
        // full frame: (1440, -900, 1920, 1080)
        // visible frame: (1440, -900, 1920, 1055) — 25px menu bar
        let topLeftY = TerminalWindowTiler.topLeftY(
            fullHeight: 1080, visibleOriginY: -900, visibleHeight: 1055, fullOriginY: -900
        )
        // = 1080 - (-900) - 1055 + (-900) = 1080 + 900 - 1055 - 900 = 25
        #expect(topLeftY == 25)
    }
}

@Suite("TerminalWindowTiler Easing")
struct TilerEasingTests {

    @Test("ease(0) == 0 and ease(1) == 1")
    func easeBoundary() {
        #expect(TerminalWindowTiler.ease(0) == 0)
        #expect(TerminalWindowTiler.ease(1) == 1)
    }

    @Test("ease(0.5) == 0.5")
    func easeMidpoint() {
        #expect(TerminalWindowTiler.ease(0.5) == 0.5)
    }

    @Test("ease is symmetric: ease(t) + ease(1-t) ≈ 1")
    func easeSymmetry() {
        let sum = TerminalWindowTiler.ease(0.25) + TerminalWindowTiler.ease(0.75)
        #expect(abs(sum - 1.0) < 1e-10)
    }

    @Test("ease is monotonically increasing")
    func easeMonotonic() {
        var prev = 0.0
        for i in 1...10 {
            let t = Double(i) / 10.0
            let val = TerminalWindowTiler.ease(t)
            #expect(val >= prev, "ease(\(t)) = \(val) should be >= ease(\(Double(i-1)/10.0)) = \(prev)")
            prev = val
        }
    }

    @Test("interpolate at t=0 returns start rect")
    func interpolateStart() {
        let a = CGRect(x: 10, y: 20, width: 100, height: 200)
        let b = CGRect(x: 50, y: 60, width: 300, height: 400)
        let result = TerminalWindowTiler.interpolate(a, b, 0)
        #expect(result == a)
    }

    @Test("interpolate at t=1 returns end rect")
    func interpolateEnd() {
        let a = CGRect(x: 10, y: 20, width: 100, height: 200)
        let b = CGRect(x: 50, y: 60, width: 300, height: 400)
        let result = TerminalWindowTiler.interpolate(a, b, 1)
        #expect(result == b)
    }
}
