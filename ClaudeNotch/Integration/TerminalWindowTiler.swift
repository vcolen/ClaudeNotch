import Cocoa
@preconcurrency import ApplicationServices
import QuartzCore
import os.log

@MainActor
@Observable
final class TerminalWindowTiler {

    // MARK: - State

    private struct CycleState {
        var lastWindowCount = 0
        var currentLayoutIndex = 0
    }
    private var cycleState = CycleState()
    private var isAnimating = false
    private weak var screen: NSScreen?

    private var animationTask: Task<Void, Never>?
    private var axWorkTask: Task<Void, Never>?

    /// AXUIElement calls are synchronous Mach IPC round-trips with no shared client-side state,
    /// so they are safe to call from any thread.
    private struct SendableAXWindow: @unchecked Sendable {
        let axElement: AXUIElement
        let startFrame: CGRect
    }

    nonisolated(unsafe) private static let log = Logger(subsystem: "com.claudenotch", category: "TerminalWindowTiler")

    init(screen: NSScreen) {
        self.screen = screen
    }

    func updateScreen(_ newScreen: NSScreen) {
        self.screen = newScreen
    }

    // MARK: - Layout Table

    /// Each layout is an array of row sizes. Example: [3, 4] = 3 on top, 4 on bottom.
    /// First layout in each array is the default.
    nonisolated(unsafe) private static let layoutTable: [Int: [[Int]]] = [
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

    nonisolated static func layouts(for windowCount: Int) -> [[Int]] {
        if windowCount <= 0 { return [] }
        let clamped = min(windowCount, 10)
        return layoutTable[clamped] ?? []
    }

    // MARK: - Frame Calculation

    /// Compute target frames for each window given a layout and screen rect.
    /// The `rect` should already be in top-left origin coordinates.
    /// Windows are assigned top-to-bottom, left-to-right.
    nonisolated static func computeFrames(layout: [Int], in rect: CGRect, gap: CGFloat) -> [CGRect] {
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

    /// Pure coordinate math extracted for testability.
    nonisolated static func topLeftY(fullHeight: CGFloat, visibleOriginY: CGFloat,
                                      visibleHeight: CGFloat, fullOriginY: CGFloat) -> CGFloat {
        fullHeight - visibleOriginY - visibleHeight + fullOriginY
    }

    /// Convert NSScreen.visibleFrame from Cocoa coordinates (bottom-left origin)
    /// to Core Graphics coordinates (top-left origin) for CGWindowList/AXUIElement APIs.
    /// The `+ full.origin.y` term accounts for non-primary monitors whose origin isn't at (0,0).
    nonisolated static func visibleFrameInTopLeft(screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let full = screen.frame
        let y = topLeftY(fullHeight: full.height, visibleOriginY: visible.origin.y,
                          visibleHeight: visible.height, fullOriginY: full.origin.y)
        return CGRect(
            x: visible.origin.x,
            y: y,
            width: visible.width,
            height: visible.height
        )
    }

    // MARK: - Window Discovery

    // Supported terminal emulators. Extend this set to tile additional apps.
    nonisolated(unsafe) private static let terminalAppNames: Set<String> = ["iTerm2", "Terminal"]

    nonisolated static func isTerminalApp(_ name: String) -> Bool {
        terminalAppNames.contains(name)
    }

    struct WindowInfo {
        let pid: pid_t
        let windowID: CGWindowID
        let bounds: CGRect

        private init(pid: pid_t, windowID: CGWindowID, bounds: CGRect) {
            self.pid = pid
            self.windowID = windowID
            self.bounds = bounds
        }

        init?(from dict: [String: Any]) {
            guard
                let ownerName = dict[kCGWindowOwnerName as String] as? String,
                TerminalWindowTiler.isTerminalApp(ownerName),
                let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = dict[kCGWindowOwnerPID as String] as? Int,
                let windowID = dict[kCGWindowNumber as String] as? Int,
                let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            self.init(pid: pid_t(pid), windowID: CGWindowID(windowID), bounds: bounds)
        }
    }

    /// Discover all on-screen terminal windows on the stored screen.
    func discoverWindows() -> [WindowInfo] {
        guard let screen else {
            Self.log.warning("discoverWindows: screen reference is nil (deallocated)")
            return []
        }
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            Self.log.error("CGWindowListCopyWindowInfo returned nil — Screen Recording permission may be missing")
            return []
        }

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
    private nonisolated static func resolveAXWindows(_ windows: [WindowInfo]) -> [(info: WindowInfo, axElement: AXUIElement)] {
        var results: [(info: WindowInfo, axElement: AXUIElement)] = []
        // Group by PID to avoid creating duplicate AX app references
        let byPID = Dictionary(grouping: windows, by: \.pid)
        for (pid, pidWindows) in byPID {
            let app = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                Self.log.warning("Failed to copy AX windows for PID \(pid)")
                continue
            }

            var matchedIndices = Set<Int>()
            for windowInfo in pidWindows {
                for (axIdx, axWindow) in axWindows.enumerated() {
                    guard !matchedIndices.contains(axIdx) else { continue }

                    var posRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                          AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success
                    else {
                        Self.log.warning("Failed to read position/size for AX window \(axIdx) of PID \(pid)")
                        continue
                    }

                    var pos = CGPoint.zero
                    var size = CGSize.zero
                    guard let posRef, let sizeRef,
                          CFGetTypeID(posRef) == AXValueGetTypeID(),
                          CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
                        Self.log.warning("Unexpected AXValue type for AX window \(axIdx) of PID \(pid)")
                        continue
                    }
                    // Force cast is safe: CFGetTypeID verified above
                    guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
                          AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
                        Self.log.warning("Failed to extract AXValue for AX window \(axIdx) of PID \(pid)")
                        continue
                    }

                    // 2-point tolerance: CGWindowList and AXUIElement report slightly different
                    // coordinates due to rounding between Core Graphics and Accessibility frameworks.
                    if abs(pos.x - windowInfo.bounds.origin.x) < 2
                        && abs(pos.y - windowInfo.bounds.origin.y) < 2
                        && abs(size.width - windowInfo.bounds.width) < 2
                        && abs(size.height - windowInfo.bounds.height) < 2 {
                        matchedIndices.insert(axIdx)
                        results.append((info: windowInfo, axElement: axWindow))
                        break
                    }
                }
            }
        }
        return results
    }

    /// Reposition then resize a resolved AX window element.
    /// Position is set first to avoid temporary overflow when a window moves to a smaller area.
    private nonisolated static func setWindowFrame(_ target: CGRect, axElement: AXUIElement) -> Bool {
        var newPos = target.origin
        var newSize = target.size
        guard let posVal = AXValueCreate(.cgPoint, &newPos),
              let sizeVal = AXValueCreate(.cgSize, &newSize) else { return false }
        let posResult = AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, posVal)
        let sizeResult = AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, sizeVal)
        if posResult != .success || sizeResult != .success {
            Self.log.warning("setWindowFrame failed: pos=\(posResult.rawValue) size=\(sizeResult.rawValue)")
            return false
        }
        return true
    }

    // MARK: - Permission

    nonisolated static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var canTidy: Bool {
        Self.isAccessibilityTrusted && !isAnimating
    }

    // MARK: - Cycling

    nonisolated static func nextLayoutIndex(current: Int, forCount windowCount: Int) -> Int {
        let layouts = Self.layouts(for: windowCount)
        guard layouts.count > 1 else { return 0 }
        return (current + 1) % layouts.count
    }

    // MARK: - Tidy

    private static let gap: CGFloat = 12

    func tidy() {
        if isAnimating { Self.log.debug("Tidy skipped: animation in progress"); return }
        guard let screen else { Self.log.debug("Tidy skipped: no screen"); return }

        if !Self.isAccessibilityTrusted {
            Self.log.info("Requesting accessibility permission")
            Self.requestAccessibility()
            return
        }

        let windows = discoverWindows()
        let count = min(windows.count, 10)
        if windows.count > 10 {
            Self.log.info("Clamping \(windows.count) terminal windows to max 10")
        }
        Self.log.info("Tiling \(count) terminal windows")
        guard count > 0 else {
            Self.log.debug("Tidy: no terminal windows found")
            return
        }

        // Reset cycling if window count changed
        if count != cycleState.lastWindowCount {
            cycleState.currentLayoutIndex = 0
            cycleState.lastWindowCount = count
        } else {
            cycleState.currentLayoutIndex = Self.nextLayoutIndex(current: cycleState.currentLayoutIndex, forCount: count)
        }

        let layouts = Self.layouts(for: count)
        guard cycleState.currentLayoutIndex < layouts.count else {
            assertionFailure("Layout index \(cycleState.currentLayoutIndex) out of bounds for \(layouts.count) layouts")
            Self.log.error("Layout index \(self.cycleState.currentLayoutIndex) out of bounds for \(layouts.count) layouts")
            return
        }
        let layout = layouts[cycleState.currentLayoutIndex]

        let usableRect = Self.visibleFrameInTopLeft(screen: screen)
        let insetRect = usableRect.insetBy(dx: Self.gap, dy: Self.gap)
        let targetFrames = Self.computeFrames(layout: layout, in: insetRect, gap: Self.gap)

        guard targetFrames.count == count else {
            Self.log.error("Frame count mismatch: \(targetFrames.count) vs \(count)")
            return
        }

        let tilableWindows = Array(windows.prefix(count))

        // Resolve AX elements ONCE before animation starts.
        let resolved = Self.resolveAXWindows(tilableWindows)
        Self.log.info("Resolved \(resolved.count)/\(count) AX windows")
        guard !resolved.isEmpty else {
            Self.log.warning("Could not resolve any AX windows")
            return
        }
        if resolved.count < count {
            Self.log.warning("Resolved only \(resolved.count)/\(count) AX windows; snapping resolved subset")
            for (i, pair) in resolved.enumerated() where i < targetFrames.count {
                _ = Self.setWindowFrame(targetFrames[i], axElement: pair.axElement)
            }
            return
        }
        animateWindows(resolved, to: targetFrames)
    }

    // MARK: - Animation

    /// 10 steps at ~25ms each = ~250ms animation. Each step fires AX calls
    /// for all windows in parallel; total time is stepCount * (sleep + IPC latency).
    private static let tileStepCount = 10

    /// Cubic ease-in-out: smooth acceleration then deceleration.
    nonisolated static func ease(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    nonisolated static func interpolate(_ from: CGRect, _ to: CGRect, _ t: Double) -> CGRect {
        let et = ease(t)
        return CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * et,
            y: from.origin.y + (to.origin.y - from.origin.y) * et,
            width: from.width + (to.width - from.width) * et,
            height: from.height + (to.height - from.height) * et
        )
    }

    private func animateWindows(_ resolved: [(info: WindowInfo, axElement: AXUIElement)], to targets: [CGRect]) {
        isAnimating = true
        animationTask?.cancel()
        axWorkTask?.cancel()

        // Respect Reduce Motion accessibility setting — snap immediately
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            for (i, pair) in resolved.enumerated() {
                _ = Self.setWindowFrame(targets[i], axElement: pair.axElement)
            }
            isAnimating = false
            return
        }

        let windows = resolved.map { SendableAXWindow(axElement: $0.axElement, startFrame: $0.info.bounds) }
        let stepCount = Self.tileStepCount

        // Pre-compute all interpolated frames for each step (let-bound for Sendable)
        let stepFrames: [[CGRect]] = (1...stepCount).map { step in
            let t = Double(step) / Double(stepCount)
            return zip(windows.map(\.startFrame), targets).map { Self.interpolate($0, $1, t) }
        }
        let finalTargets = targets

        // Detached task runs AX calls off the main actor.
        // A regular Task awaits it and clears isAnimating on @MainActor.
        let axWork = Task.detached(priority: .userInitiated) {
            for step in 0..<stepCount {
                guard !Task.isCancelled else { break }
                let frames = stepFrames[step]

                await withTaskGroup(of: Void.self) { group in
                    for (i, window) in windows.enumerated() {
                        let frame = frames[i]
                        // Skip AX call when delta < 1pt (avoids wasted IPC)
                        let prevFrame = step > 0 ? stepFrames[step - 1][i] : window.startFrame
                        let dx = abs(frame.origin.x - prevFrame.origin.x)
                        let dy = abs(frame.origin.y - prevFrame.origin.y)
                        let dw = abs(frame.width - prevFrame.width)
                        let dh = abs(frame.height - prevFrame.height)
                        if dx < 1 && dy < 1 && dw < 1 && dh < 1 { continue }

                        group.addTask {
                            _ = TerminalWindowTiler.setWindowFrame(frame, axElement: window.axElement)
                        }
                    }
                }

                if step < stepCount - 1 {
                    try? await Task.sleep(for: .milliseconds(25))
                }
            }

            // Final snap to exact targets for pixel-perfect end state
            if !Task.isCancelled {
                await withTaskGroup(of: Void.self) { group in
                    for (i, window) in windows.enumerated() {
                        let target = finalTargets[i]
                        group.addTask {
                            _ = TerminalWindowTiler.setWindowFrame(target, axElement: window.axElement)
                        }
                    }
                }
            }
        }
        axWorkTask = axWork

        // This Task inherits @MainActor — awaits the detached work then clears state
        animationTask = Task {
            await axWork.value
            isAnimating = false
        }
    }

    // MARK: - Teardown

    func cancel() {
        axWorkTask?.cancel()
        axWorkTask = nil
        animationTask?.cancel()
        animationTask = nil
        isAnimating = false
    }
}
