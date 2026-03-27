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

Single class that owns all tiling logic. Conforms to `@Observable` so the button can react to state.

**Properties:**
- `lastWindowCount: Int` — detects count changes to reset cycling
- `currentLayoutIndex: Int` — which layout variant is active
- `isAnimating: Bool` — prevents taps during animation

**Public API:**
- `tidy()` — main entry point called by the button. Discovers windows, computes layout, animates into position. On subsequent calls, cycles to next layout.
- `canTidy: Bool` — computed property: true when Accessibility is trusted and terminal windows exist.

### Window Discovery

Uses `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` to enumerate on-screen windows. Filters by:
- Owner name: `"iTerm2"` or `"Terminal"`
- Window layer: 0 (standard windows only, skip popups/panels)
- Not minimized (on-screen only filter handles this)
- Same screen as the notch panel (compare window origin against `NSScreen.frame`)

Returns an array of discovered windows, each containing: `CGWindowID`, owner PID, current bounds, window title.

### Screen Geometry

- Query `NSScreen.main?.visibleFrame` for the usable area (excludes menu bar and Dock)
- Inset by 12px on all edges for macOS-style gaps
- 12px gap between adjacent windows

### Frame Calculation

Given a layout definition (e.g., `[3, 4]`) and the usable screen rect:

1. Divide height equally among rows, minus inter-row gaps
2. For each row, divide width equally among windows in that row, minus inter-column gaps
3. Compute each window's target `CGRect`
4. Note: CGWindowList uses top-left origin coords; `AXUIElement` position also uses top-left origin — no coordinate flip needed between them

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
3. Use a display-link timer (or `NSAnimationHelper` pattern from the existing codebase) to interpolate over ~300ms
4. On each tick, compute intermediate position/size and set via AXUIElement
5. Use ease-in-out timing curve (same `CAMediaTimingFunction` pattern as existing animations)

### Permission Handling

On first call to `tidy()`:

1. Check `AXIsProcessTrusted()`
2. If not trusted:
   - Show a brief explanation (can use a small popover from the button)
   - Open System Settings → Privacy → Accessibility via `NSWorkspace.shared.open(URL)`
   - Disable the button until permission is granted
   - Poll `AXIsProcessTrusted()` briefly after opening Settings (every 1s for ~30s)

### Cycling Behavior

1. First tap: discover windows, count them, apply default layout (index 0)
2. Subsequent taps: increment `currentLayoutIndex`, wrap to 0 when past the last alternative
3. If window count changes between taps: reset `currentLayoutIndex` to 0, apply default for new count
4. During animation (`isAnimating == true`): ignore taps

### Edge Cases

- **0 terminal windows**: `canTidy` returns false, button appears disabled
- **>10 terminal windows**: tile the first 10 (ordered by CGWindowList order), leave the rest untouched
- **Windows on different screens**: only tile windows whose origin falls within the same `NSScreen` as the notch panel
- **Minimized windows**: already excluded by `.optionOnScreenOnly` filter

## UI Changes

### ExpandedNotchView

Add a tidy button (grid icon, e.g., `square.grid.2x2`) to the header row, right-aligned. Styled to match existing header controls using `DesignTokens`.

- Enabled state: normal opacity, clickable
- Disabled state: 0.3 opacity when `!tiler.canTidy`
- On tap: calls `tiler.tidy()`

### No other UI changes

The button is the only new UI element. No settings, no preferences panel, no configuration.
