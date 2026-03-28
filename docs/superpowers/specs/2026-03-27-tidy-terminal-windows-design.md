# Tidy Terminal Windows — Design Spec

## Overview

Add a "tidy" button to the expanded notch header that arranges all visible terminal windows (iTerm2 + Terminal.app) into a clean grid layout. Each tap cycles through alternative layouts for the current window count. Supports 1–10 windows with a max of 5 per row.

## Decisions

| Decision | Choice |
|----------|--------|
| Cycling | Each tap rotates through layouts, wraps to default |
| Screen area | Respect menu bar + Dock (`NSScreen.visibleFrame`) |
| Gap between windows | ~12px macOS-style |
| Animation | Smooth slide (~300ms ease-in-out) |
| Button placement | Header of expanded notch view |
| Scope | All visible terminal windows (iTerm2 + Terminal.app) |
| Implementation | Accessibility API (AXUIElement) — no AppleScript |
| Permission | Requires Accessibility access; prompt user on first use |

## Layout Table

Default layout listed first, alternatives follow.

| Count | Default | Alt 1 | Alt 2 |
|-------|---------|-------|-------|
| 1 | Fullscreen | — | — |
| 2 | 2 columns `[2]` | 2 rows `[1,1]` | — |
| 3 | 3 columns `[3]` | 1+2 `[1,2]` | 2+1 `[2,1]` |
| 4 | 2×2 `[2,2]` | 4 columns `[4]` | 1+3 `[1,3]` |
| 5 | 3+2 `[3,2]` | 2+3 `[2,3]` | 5 columns `[5]` |
| 6 | 3×2 `[3,3]` | 2×3 `[2,2,2]` | — |
| 7 | 3+4 `[3,4]` | 4+3 `[4,3]` | 3+2+2 `[3,2,2]` |
| 8 | 3+3+2 `[3,3,2]` | 4×2 `[4,4]` | 2×4 `[2,2,2,2]` |
| 9 | 4+5 `[4,5]` | 3×3 `[3,3,3]` | 5+4 `[5,4]` |
| 10 | 4+3+3 `[4,3,3]` | 5×2 `[5,5]` | 3+4+3 `[3,4,3]` |

Each layout is represented as an array of row sizes. For example, `[3,4]` means 3 windows on the top row, 4 on the bottom row.

## Architecture

### New file: `Integration/TerminalWindowTiler.swift`

`@MainActor @Observable` class that owns all tiling logic so the button can react to state.

**Properties:**
- `lastWindowCount: Int` — detects count changes to reset cycling
- `currentLayoutIndex: Int` — which layout variant is active
- `isAnimating: Bool` — prevents taps during animation

**Public API:**
- `tidy()` — main entry point called by the button. Discovers windows, computes layout, animates into position. On subsequent calls, cycles to next layout.
- `canTidy: Bool` — computed property: true when Accessibility is trusted and not currently animating.

### Window Discovery

Uses `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` to enumerate on-screen windows. Filters by:
- Owner name: `"iTerm2"` or `"Terminal"`
- Window layer: 0 (standard windows only, skip popups/panels)
- Not minimized (on-screen only filter handles this)
- Same screen as the notch panel (compare window origin against `NSScreen.frame`)

Returns an array of discovered windows, each containing: `CGWindowID`, owner PID, current bounds.

### Screen Geometry

- The tiler receives the `NSScreen` from its owning `NotchPanelController` (not `NSScreen.main`, which would be wrong on secondary monitors)
- Query that screen's `visibleFrame` for the usable area (excludes menu bar and Dock)
- Inset by 12px on all edges for macOS-style gaps
- 12px gap between adjacent windows

### Frame Calculation

Given a layout definition (e.g., `[3, 4]`) and the usable screen rect:

1. Divide height equally among rows, minus inter-row gaps
2. For each row, divide width equally among windows in that row, minus inter-column gaps
3. Compute each window's target `CGRect`
4. **Coordinate conversion required:** `NSScreen.visibleFrame` uses AppKit's bottom-left origin. CGWindowList and AXUIElement both use top-left origin. Convert `visibleFrame` to top-left origin before computing target rects: `topLeftY = NSScreen.frame.height - visibleFrame.origin.y - visibleFrame.height`

### Window Positioning

For each terminal window:

1. Get the owning app's PID from CGWindowList info
2. Create `AXUIElementCreateApplication(pid)` for the app
3. Enumerate `kAXWindowsAttribute` to find the matching window (match by comparing current position/size with CGWindowList data)
4. Set `kAXPositionAttribute` (CGPoint) and `kAXSizeAttribute` (CGSize) to reposition

### Animated Repositioning

The Accessibility API sets positions instantly. To achieve smooth animation:

1. Capture each window's current frame from CGWindowList
2. Compute target frames from the layout engine
3. Manual step-based interpolation using structured concurrency (`Task.detached` + `withTaskGroup`). 10 steps at ~25ms each = ~250ms animation. Each step fires AX calls for all windows in parallel.
4. On each step, compute intermediate position/size via cubic ease-in-out and set via AXUIElement
5. Use cubic ease-in-out timing curve (`4t^3` for first half, `1 - (-2t+2)^3/2` for second half)
6. If animation stutters due to AXUIElement IPC overhead with many windows, fall back to instant repositioning as an acceptable degradation

### Permission Handling

On first call to `tidy()`:

1. Check `AXIsProcessTrusted()`
2. If not trusted:
   - Call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` to trigger the system's native permission dialog
   - Return early; user can retry after granting permission

### Cycling Behavior

1. First tap: discover windows, count them, apply default layout (index 0)
2. Subsequent taps: increment `currentLayoutIndex`, wrap to 0 when past the last alternative
3. If window count changes between taps: reset `currentLayoutIndex` to 0, apply default for new count
4. During animation (`isAnimating == true`): ignore taps

### Edge Cases

- **0 terminal windows**: `canTidy` returns false, button appears disabled
- **>10 terminal windows**: tile the first 10 (ordered by CGWindowList front-to-back z-order), leave the rest untouched
- **Windows on different screens**: only tile windows whose origin falls within the same `NSScreen` as the notch panel
- **Minimized windows**: already excluded by `.optionOnScreenOnly` filter

## UI Changes

### ExpandedNotchView

The current `ExpandedNotchView` has no header row — it is a flat `VStack` with the instance list, separator, and "New Instance" button. Add a new header `HStack` at the top of the `VStack` containing the tidy button (grid icon, e.g., `square.grid.2x2`), right-aligned. Styled using `NotchTokens` (the project's design token namespace).

- Enabled state: normal opacity, clickable
- Disabled state: 0.3 opacity when `!tiler.canTidy`
- On tap: calls `tiler.tidy()`

### No other UI changes

The button is the only new UI element. No settings, no preferences panel, no configuration.
