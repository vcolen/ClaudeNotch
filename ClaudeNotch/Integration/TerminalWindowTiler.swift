import Cocoa
import ApplicationServices

@Observable
final class TerminalWindowTiler {

    // MARK: - Layout Table

    /// Each layout is an array of row sizes. Example: [3, 4] = 3 on top, 4 on bottom.
    /// First layout in each array is the default.
    private static let layoutTable: [Int: [[Int]]] = [
        1:  [[1]],
        2:  [[2], [1, 1]],
        3:  [[3], [1, 2], [2, 1]],
        4:  [[2, 2], [4], [1, 3]],
        5:  [[3, 2], [2, 3], [5]],
        6:  [[3, 3], [2, 2, 2]],
        7:  [[3, 4], [4, 3], [3, 2, 2]],
        8:  [[3, 3, 2], [4, 4], [2, 2, 2, 2]],
        9:  [[4, 5], [3, 3, 3], [5, 4]],
        10: [[4, 3, 3], [5, 5], [3, 4, 3]],
    ]

    static func layouts(for windowCount: Int) -> [[Int]] {
        if windowCount <= 0 { return [] }
        let clamped = min(windowCount, 10)
        return layoutTable[clamped] ?? []
    }

    // MARK: - Frame Calculation

    /// Compute target frames for each window given a layout and screen rect.
    /// The `rect` should already be in top-left origin coordinates.
    /// Windows are assigned top-to-bottom, left-to-right.
    static func computeFrames(layout: [Int], in rect: CGRect, gap: CGFloat) -> [CGRect] {
        guard !layout.isEmpty else { return [] }
        let rowCount = layout.count
        let totalRowGaps = gap * CGFloat(rowCount - 1)
        let rowHeight = (rect.height - totalRowGaps) / CGFloat(rowCount)

        var frames: [CGRect] = []
        for (rowIndex, columnsInRow) in layout.enumerated() {
            let totalColGaps = gap * CGFloat(columnsInRow - 1)
            let colWidth = (rect.width - totalColGaps) / CGFloat(columnsInRow)
            let y = rect.origin.y + CGFloat(rowIndex) * (rowHeight + gap)

            for col in 0..<columnsInRow {
                let x = rect.origin.x + CGFloat(col) * (colWidth + gap)
                frames.append(CGRect(x: x, y: y, width: colWidth, height: rowHeight))
            }
        }
        return frames
    }

    /// Convert NSScreen.visibleFrame (bottom-left origin) to top-left origin
    /// for use with CGWindowList/AXUIElement coordinate system.
    static func visibleFrameInTopLeft(screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let full = screen.frame
        let topLeftY = full.height - visible.origin.y - visible.height + full.origin.y
        return CGRect(
            x: visible.origin.x,
            y: topLeftY,
            width: visible.width,
            height: visible.height
        )
    }
}
