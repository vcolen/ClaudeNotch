import Cocoa
@preconcurrency import ApplicationServices
import QuartzCore

@Observable
final class TerminalWindowTiler {

    // MARK: - State

    var lastWindowCount = 0
    var currentLayoutIndex = 0
    var isAnimating = false
    private weak var screen: NSScreen?

    init(screen: NSScreen) {
        self.screen = screen
    }

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

    // MARK: - Permission

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var canTidy: Bool {
        Self.isAccessibilityTrusted
    }

    // MARK: - Cycling

    static func nextLayoutIndex(current: Int, forCount windowCount: Int) -> Int {
        let layouts = Self.layouts(for: windowCount)
        guard layouts.count > 1 else { return 0 }
        return (current + 1) % layouts.count
    }

    // MARK: - Tidy

    private static let gap: CGFloat = 12

    func tidy() {
        guard !isAnimating, let screen else { return }

        if !Self.isAccessibilityTrusted {
            Self.requestAccessibility()
            return
        }

        let windows = discoverWindows(on: screen)
        let count = min(windows.count, 10)
        guard count > 0 else { return }

        // Reset cycling if window count changed
        if count != lastWindowCount {
            currentLayoutIndex = 0
            lastWindowCount = count
        } else {
            currentLayoutIndex = Self.nextLayoutIndex(current: currentLayoutIndex, forCount: count)
        }

        let layouts = Self.layouts(for: count)
        guard currentLayoutIndex < layouts.count else { return }
        let layout = layouts[currentLayoutIndex]

        let usableRect = Self.visibleFrameInTopLeft(screen: screen)
        let insetRect = usableRect.insetBy(dx: Self.gap, dy: Self.gap)
        let targetFrames = Self.computeFrames(layout: layout, in: insetRect, gap: Self.gap)

        guard targetFrames.count == count else { return }

        let tilableWindows = Array(windows.prefix(count))

        // Resolve AX elements ONCE before animation starts.
        let resolved = Self.resolveAXWindows(tilableWindows)
        guard resolved.count == count else {
            // Fallback: couldn't resolve all windows, snap instantly
            for (i, pair) in resolved.enumerated() where i < targetFrames.count {
                Self.setWindowFrame(targetFrames[i], axElement: pair.axElement)
            }
            return
        }
        animateWindows(resolved, to: targetFrames)
    }

    // MARK: - Animation

    private func animateWindows(_ resolved: [(info: WindowInfo, axElement: AXUIElement)], to targets: [CGRect]) {
        isAnimating = true
        let startFrames = resolved.map(\.info.bounds)
        let duration: Double = 0.3
        let startTime = CACurrentMediaTime()

        @Sendable func ease(_ t: Double) -> Double {
            t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }

        @Sendable func interpolate(_ from: CGRect, _ to: CGRect, _ t: Double) -> CGRect {
            let et = ease(t)
            return CGRect(
                x: from.origin.x + (to.origin.x - from.origin.x) * et,
                y: from.origin.y + (to.origin.y - from.origin.y) * et,
                width: from.width + (to.width - from.width) * et,
                height: from.height + (to.height - from.height) * et
            )
        }

        // nonisolated(unsafe) to satisfy Sendable requirements for the timer closure.
        // Safe because the timer fires on the main RunLoop.
        nonisolated(unsafe) let resolvedUnsafe = resolved
        nonisolated(unsafe) let selfUnsafe = self

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)

            for (i, pair) in resolvedUnsafe.enumerated() {
                let frame = interpolate(startFrames[i], targets[i], progress)
                TerminalWindowTiler.setWindowFrame(frame, axElement: pair.axElement)
            }

            if progress >= 1.0 {
                timer.invalidate()
                for (i, pair) in resolvedUnsafe.enumerated() {
                    TerminalWindowTiler.setWindowFrame(targets[i], axElement: pair.axElement)
                }
                selfUnsafe.isAnimating = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
