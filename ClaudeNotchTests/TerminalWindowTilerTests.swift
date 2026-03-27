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
}
