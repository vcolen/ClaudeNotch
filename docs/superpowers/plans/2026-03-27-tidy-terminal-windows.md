# Tidy Terminal Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a button to the expanded notch that tiles all visible terminal windows into clean grid layouts using the Accessibility API, with cycling through alternatives on each tap.

**Architecture:** New `TerminalWindowTiler` class in `Integration/` handles window discovery (CGWindowList), layout computation (static lookup table), and positioning (AXUIElement). The tidy button is added to the `ExpandedNotchView` header. Animation uses step-based interpolation with structured concurrency for smooth repositioning.

> **Post-implementation note:** Implementation deviated from this plan in several ways (animation uses `Task.detached` + `withTaskGroup` instead of CVDisplayLink, permission handling uses `AXIsProcessTrustedWithOptions` with prompt instead of manual Settings navigation, class is annotated with `@MainActor`). See the actual source code for current behavior.

**Tech Stack:** Swift, Accessibility API (AXUIElement), CoreGraphics (CGWindowList), CVDisplayLink, SwiftUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-27-tidy-terminal-windows-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| Create: `ClaudeNotch/Integration/TerminalWindowTiler.swift` | Layout table, window discovery, frame calculation, AX positioning, animation, cycling state |
| Create: `ClaudeNotchTests/TerminalWindowTilerTests.swift` | Tests for layout table, frame calculation, coordinate conversion, cycling logic |
| Modify: `ClaudeNotch/Views/ExpandedNotchView.swift` | Add tidy button to new header HStack |
| Modify: `ClaudeNotch/Views/NotchView.swift` | Pass `TerminalWindowTiler` to ExpandedNotchView |
| Modify: `ClaudeNotch/Window/NotchPanelController.swift` | Create `TerminalWindowTiler` with screen reference, pass to NotchView |
| Modify: `ClaudeNotch.xcodeproj` | Add new files to Xcode project |

---

### Task 1: Layout Table & Frame Calculation (Pure Logic)

The layout table and frame calculator are pure functions with no system dependencies — testable in isolation.

**Files:**
- Create: `ClaudeNotch/Integration/TerminalWindowTiler.swift`
- Create: `ClaudeNotchTests/TerminalWindowTilerTests.swift`

- [ ] **Step 1: Write failing tests for layout table**

In `ClaudeNotchTests/TerminalWindowTilerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerLayoutTableTests 2>&1 | tail -20`
Expected: FAIL — `TerminalWindowTiler` type does not exist

- [ ] **Step 3: Implement layout table**

In `ClaudeNotch/Integration/TerminalWindowTiler.swift`:

```swift
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerLayoutTableTests 2>&1 | tail -20`
Expected: PASS — all 6 tests green

- [ ] **Step 5: Write failing tests for frame calculation**

Append to `ClaudeNotchTests/TerminalWindowTilerTests.swift`:

```swift
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
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerFrameTests 2>&1 | tail -20`
Expected: FAIL — `computeFrames` does not exist

- [ ] **Step 7: Implement frame calculation**

Add to `TerminalWindowTiler.swift`:

```swift
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
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerFrameTests 2>&1 | tail -20`
Expected: PASS — all 6 tests green

- [ ] **Step 9: Commit**

```bash
git add ClaudeNotch/Integration/TerminalWindowTiler.swift ClaudeNotchTests/TerminalWindowTilerTests.swift
git commit -m "feat: add layout table and frame calculation for terminal tiler"
```

**Note:** Also add both files to the Xcode project. If `xcodebuild` can't find them, the project file needs updating. Check that `ClaudeNotch.xcodeproj/project.pbxproj` includes both new files in the appropriate targets (ClaudeNotch for the source, ClaudeNotchTests for the test). Use the pattern from existing files like `ProcessScanner.swift` and `ProcessScannerTests.swift`.

---

### Task 2: Window Discovery & AX Positioning

Discover terminal windows via CGWindowList and reposition via Accessibility API. This task has system dependencies (needs real windows) so tests focus on the data structures and filtering logic.

**Files:**
- Modify: `ClaudeNotch/Integration/TerminalWindowTiler.swift`
- Modify: `ClaudeNotchTests/TerminalWindowTilerTests.swift`

- [ ] **Step 1: Write failing tests for window info struct and terminal app filtering**

Append to `ClaudeNotchTests/TerminalWindowTilerTests.swift`:

```swift
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
            "kCGWindowOwnerPID": 1234,
            "kCGWindowNumber": 42,
            "kCGWindowBounds": ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            "kCGWindowOwnerName": "iTerm2",
            "kCGWindowLayer": 0,
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
            "kCGWindowOwnerPID": 1234,
            "kCGWindowNumber": 42,
            "kCGWindowBounds": ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            "kCGWindowOwnerName": "iTerm2",
            "kCGWindowLayer": 1,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }

    @Test("WindowInfo rejects non-terminal apps")
    func rejectsNonTerminal() {
        let dict: [String: Any] = [
            "kCGWindowOwnerPID": 1234,
            "kCGWindowNumber": 42,
            "kCGWindowBounds": ["X": 100, "Y": 200, "Width": 800, "Height": 600],
            "kCGWindowOwnerName": "Safari",
            "kCGWindowLayer": 0,
        ]
        let info = TerminalWindowTiler.WindowInfo(from: dict)
        #expect(info == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerWindowFilterTests 2>&1 | tail -20`
Expected: FAIL — `isTerminalApp` and `WindowInfo` do not exist

- [ ] **Step 3: Implement WindowInfo struct, isTerminalApp, and discovery**

Add to `TerminalWindowTiler.swift`:

```swift
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
                let x = boundsDict["X"] as? CGFloat,
                let y = boundsDict["Y"] as? CGFloat,
                let w = boundsDict["Width"] as? CGFloat,
                let h = boundsDict["Height"] as? CGFloat
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
        AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, sizeVal)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerWindowFilterTests 2>&1 | tail -20`
Expected: PASS — all 5 tests green

- [ ] **Step 5: Commit**

```bash
git add ClaudeNotch/Integration/TerminalWindowTiler.swift ClaudeNotchTests/TerminalWindowTilerTests.swift
git commit -m "feat: add window discovery and AX positioning to terminal tiler"
```

---

### Task 3: Animation & Tidy Orchestration

Wire up the CVDisplayLink animation, cycling logic, permission check, and the main `tidy()` entry point.

**Files:**
- Modify: `ClaudeNotch/Integration/TerminalWindowTiler.swift`
- Modify: `ClaudeNotchTests/TerminalWindowTilerTests.swift`

- [ ] **Step 1: Write failing tests for cycling logic**

Append to `ClaudeNotchTests/TerminalWindowTilerTests.swift`:

```swift
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

    @Test("Accessibility permission check returns bool")
    func permissionCheck() {
        // Just verifies the function exists and returns a Bool
        let _ = TerminalWindowTiler.isAccessibilityTrusted
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerCyclingTests 2>&1 | tail -20`
Expected: FAIL — `nextLayoutIndex` and `isAccessibilityTrusted` do not exist

- [ ] **Step 3: Implement cycling logic, permission check, and animated tidy**

Add to `TerminalWindowTiler.swift`:

```swift
    // MARK: - State

    var lastWindowCount = 0
    var currentLayoutIndex = 0
    var isAnimating = false
    private weak var screen: NSScreen?

    init(screen: NSScreen) {
        self.screen = screen
    }

    // MARK: - Permission

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
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
        // This avoids re-matching by bounds on every tick (which breaks after first move).
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

        // Ease-in-out cubic
        func ease(_ t: Double) -> Double {
            t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }

        func interpolate(_ from: CGRect, _ to: CGRect, _ t: Double) -> CGRect {
            let et = ease(t)
            return CGRect(
                x: from.origin.x + (to.origin.x - from.origin.x) * et,
                y: from.origin.y + (to.origin.y - from.origin.y) * et,
                width: from.width + (to.width - from.width) * et,
                height: from.height + (to.height - from.height) * et
            )
        }

        // Timer-based animation (main thread, ~60fps)
        // Using Timer instead of CVDisplayLink for simplicity — AX IPC is the bottleneck, not frame timing.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)

            for (i, pair) in resolved.enumerated() {
                let frame = interpolate(startFrames[i], targets[i], progress)
                Self.setWindowFrame(frame, axElement: pair.axElement)
            }

            if progress >= 1.0 {
                timer.invalidate()
                // Final snap to exact target positions
                for (i, pair) in resolved.enumerated() {
                    Self.setWindowFrame(targets[i], axElement: pair.axElement)
                }
                self?.isAnimating = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
```

**Note on animation:** The spec suggested CVDisplayLink but a `Timer` at 60fps is simpler and sufficient here — AXUIElement IPC round-trips are the real bottleneck, not frame timing precision. If animation stutters with many windows, the snap-to-final at `progress >= 1.0` ensures correctness.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerCyclingTests 2>&1 | tail -20`
Expected: PASS — all 3 tests green

- [ ] **Step 5: Run all tiler tests together**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' -only-testing ClaudeNotchTests/TilerLayoutTableTests -only-testing ClaudeNotchTests/TilerFrameTests -only-testing ClaudeNotchTests/TilerWindowFilterTests -only-testing ClaudeNotchTests/TilerCyclingTests 2>&1 | tail -20`
Expected: PASS — all tests green

- [ ] **Step 6: Commit**

```bash
git add ClaudeNotch/Integration/TerminalWindowTiler.swift ClaudeNotchTests/TerminalWindowTilerTests.swift
git commit -m "feat: add animation, cycling, and tidy orchestration"
```

---

### Task 4: UI Integration — Tidy Button in Expanded Notch

Wire the tiler into the view hierarchy and add the button.

**Files:**
- Modify: `ClaudeNotch/Window/NotchPanelController.swift`
- Modify: `ClaudeNotch/Views/NotchView.swift`
- Modify: `ClaudeNotch/Views/ExpandedNotchView.swift`

- [ ] **Step 1: Create TerminalWindowTiler in NotchPanelController and pass to NotchView**

In `ClaudeNotch/Window/NotchPanelController.swift`:
- Add property alongside existing ones: `private var tiler: TerminalWindowTiler?`
- In the method that creates the `NotchView` (around line 68), create the tiler using the controller's screen:
  ```swift
  let tiler = TerminalWindowTiler(screen: self.screen)
  self.tiler = tiler
  ```
- Update the `NotchView(...)` initializer call (around line 68-123) to include the tiler. The current call looks like:
  ```swift
  let notchView = NotchView(
      instanceManager: instanceManager,
      panelState: panelState,
      notificationManager: notificationManager,
      onNewInstance: { ... },
      onSelectInstance: { ... }
  )
  ```
  Add `tiler: tiler` parameter:
  ```swift
  let notchView = NotchView(
      instanceManager: instanceManager,
      panelState: panelState,
      notificationManager: notificationManager,
      tiler: tiler,
      onNewInstance: { ... },
      onSelectInstance: { ... }
  )
  ```

- [ ] **Step 2: Thread tiler through NotchView to ExpandedNotchView**

In `ClaudeNotch/Views/NotchView.swift`:
- Add property: `var tiler: TerminalWindowTiler?`
- In `expandedContent` (line 159-164), pass it:
  ```swift
  ExpandedNotchView(
      instanceManager: instanceManager,
      tiler: tiler,
      onNewInstance: onNewInstance,
      onSelectInstance: onSelectInstance
  )
  ```

- [ ] **Step 3: Add tidy button to ExpandedNotchView**

In `ClaudeNotch/Views/ExpandedNotchView.swift`:
- Add property: `var tiler: TerminalWindowTiler?`
- Add state: `@State private var isTidyHovered = false`
- Add new `header` computed property with the tidy button:

```swift
    private var header: some View {
        HStack {
            Spacer()
            Button {
                tiler?.tidy()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(
                        tiler?.canTidy == true
                            ? (isTidyHovered ? 0.7 : 0.45)
                            : 0.15
                    ))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isTidyHovered ? Color.white.opacity(0.06) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(tiler?.canTidy != true)
            .onHover { hovering in
                withMotionAnimation(NotchTokens.Animation.hoverQuick, reduceMotion: reduceMotion) {
                    isTidyHovered = hovering
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
```

- In `body`, insert `header` at the top of the VStack, before the `if instanceManager.instances.isEmpty` block:

```swift
    var body: some View {
        VStack(spacing: 0) {
            header

            if instanceManager.instances.isEmpty {
                emptyState
            } else {
                instanceList
            }

            separator

            newInstanceButton
        }
        // ... rest unchanged
    }
```

- [ ] **Step 4: Update the Preview to include tiler parameter**

Update the `#Preview` at the bottom of `ExpandedNotchView.swift`:
```swift
#Preview {
    ExpandedNotchView(
        instanceManager: InstanceManager(),
        tiler: nil
    )
    .frame(width: 340)
    .background(Color.black)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -scheme ClaudeNotch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run full test suite to verify no regressions**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add ClaudeNotch/Window/NotchPanelController.swift ClaudeNotch/Views/NotchView.swift ClaudeNotch/Views/ExpandedNotchView.swift
git commit -m "feat: add tidy terminals button to expanded notch header"
```

---

### Task 5: Xcode Project File & Final Verification

Ensure new files are in the Xcode project and everything builds and tests cleanly.

**Files:**
- Modify: `ClaudeNotch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Verify new files are in Xcode project**

Run: `grep -c "TerminalWindowTiler" ClaudeNotch.xcodeproj/project.pbxproj`

If the count is 0, the files need to be added. Use the pattern from existing files (e.g., `ProcessScanner.swift`) to add:
- `ClaudeNotch/Integration/TerminalWindowTiler.swift` to the ClaudeNotch target
- `ClaudeNotchTests/TerminalWindowTilerTests.swift` to the ClaudeNotchTests target

- [ ] **Step 2: Clean build**

Run: `xcodebuild clean build -scheme ClaudeNotch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -scheme ClaudeNotch -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass (existing + new tiler tests)

- [ ] **Step 4: Commit if project file changed**

```bash
git add ClaudeNotch.xcodeproj/project.pbxproj
git commit -m "chore: add TerminalWindowTiler files to Xcode project"
```

- [ ] **Step 5: Manual smoke test**

Build and run the app. Verify:
1. Expanded notch shows the grid icon button in the top-right of the header
2. If Accessibility permission is not granted, tapping prompts for permission
3. With permission granted and terminal windows open, tapping tiles them
4. Subsequent taps cycle through alternative layouts
5. Button is disabled (dimmed) when no terminal windows are visible
