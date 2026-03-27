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

    // MARK: - Window Discovery

    private static let terminalAppNames: Set<String> = ["iTerm2", "Terminal"]

    static func isTerminalApp(_ name: String) -> Bool {
        terminalAppNames.contains(name)
    }

    struct WindowInfo {
        let pid: pid_t
        let windowID: CGWindowID
        let bounds: CGRect

        init?(from dict: [String: Any]) {
            guard
                let ownerName = dict["kCGWindowOwnerName" as String] as? String,
                TerminalWindowTiler.isTerminalApp(ownerName),
                let layer = dict["kCGWindowLayer" as String] as? Int, layer == 0,
                let pid = dict["kCGWindowOwnerPID" as String] as? Int,
                let windowID = dict["kCGWindowNumber" as String] as? Int,
                let boundsDict = dict["kCGWindowBounds" as String] as? [String: Any],
                let x = (boundsDict["X"] as? NSNumber)?.doubleValue,
                let y = (boundsDict["Y"] as? NSNumber)?.doubleValue,
                let w = (boundsDict["Width"] as? NSNumber)?.doubleValue,
                let h = (boundsDict["Height"] as? NSNumber)?.doubleValue
            else { return nil }

            self.pid = pid_t(pid)
            self.windowID = CGWindowID(windowID)
            self.bounds = CGRect(x: x, y: y, width: w, height: h)
        }
    }

    /// Discover all on-screen terminal windows on the given screen.
    func discoverWindows(on screen: NSScreen) -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let screenFrame = screen.frame
        // Convert screen frame to top-left origin for comparison with CGWindowList bounds
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let screenTopLeftY = primaryHeight - screenFrame.maxY
        let screenRectTopLeft = CGRect(
            x: screenFrame.origin.x,
            y: screenTopLeftY,
            width: screenFrame.width,
            height: screenFrame.height
        )

        return windowList.compactMap { WindowInfo(from: $0) }
            .filter { screenRectTopLeft.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
    }

    // MARK: - AX Positioning

    /// Resolve AXUIElement references for windows before animation starts.
    /// This avoids re-matching by bounds on every animation tick (which would break
    /// after the first tick moves the window away from its original position).
    static func resolveAXWindows(_ windows: [WindowInfo]) -> [(info: WindowInfo, axElement: AXUIElement)] {
        var results: [(WindowInfo, AXUIElement)] = []
        // Group by PID to avoid creating duplicate AX app references
        let byPID = Dictionary(grouping: windows, by: \.pid)
        for (pid, pidWindows) in byPID {
            let app = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            for windowInfo in pidWindows {
                for axWindow in axWindows {
                    var posRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                          AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success
                    else { continue }

                    var pos = CGPoint.zero
                    var size = CGSize.zero
                    AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
                    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

                    if abs(pos.x - windowInfo.bounds.origin.x) < 2
                        && abs(pos.y - windowInfo.bounds.origin.y) < 2
                        && abs(size.width - windowInfo.bounds.width) < 2
                        && abs(size.height - windowInfo.bounds.height) < 2 {
                        results.append((windowInfo, axWindow))
                        break
                    }
                }
            }
        }
        return results
    }

    /// Move and resize a resolved AX window element.
    static func setWindowFrame(_ target: CGRect, axElement: AXUIElement) {
        var newPos = target.origin
        var newSize = target.size
        guard let posVal = AXValueCreate(.cgPoint, &newPos),
              let sizeVal = AXValueCreate(.cgSize, &newSize) else { return }
        AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, sizeVal)
        AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, posVal)
    }
}
