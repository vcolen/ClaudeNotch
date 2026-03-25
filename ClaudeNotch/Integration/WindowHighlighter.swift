import AppKit
import os.log

@MainActor
enum WindowHighlighter {

    private static let log = Logger(subsystem: "com.claudenotch", category: "WindowHighlighter")

    private static var activeWindow: NSWindow?
    private static var flashTask: Task<Void, Never>?

    private static let glowNSColor = NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1.0)
    private static let spread: CGFloat = 40
    private static let cornerRadius: CGFloat = 24

    static func flashiTermWindow() {
        guard let iterm = frontmostiTermWindow() else { return }
        flashTask?.cancel()
        let frame = iterm.frame

        activeWindow?.orderOut(nil)

        let glowFrame = frame.insetBy(dx: -spread, dy: -spread)

        let window = NSWindow(
            contentRect: glowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        // Uses CALayer shadow properties (instead of SwiftUI) for the glow effect
        let container = NSView(frame: NSRect(origin: .zero, size: glowFrame.size))
        container.wantsLayer = true

        let glowRect = NSRect(
            x: spread, y: spread,
            width: frame.width, height: frame.height
        )
        let shapePath = CGPath(
            roundedRect: glowRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        let glow = CALayer()
        glow.frame = NSRect(origin: .zero, size: glowFrame.size)
        glow.shadowColor = glowNSColor.cgColor
        glow.shadowOpacity = 0.55
        glow.shadowRadius = 20
        glow.shadowOffset = .zero
        glow.shadowPath = shapePath

        container.layer?.addSublayer(glow)
        window.contentView = container

        // Start invisible, animate in
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.order(.below, relativeTo: iterm.windowNumber)
        activeWindow = window

        flashTask = Task { @MainActor in
            defer {
                window.orderOut(nil)
                if activeWindow === window {
                    activeWindow = nil
                }
            }

            await NSAnimationHelper.animate(
                duration: NotchTokens.Animation.selectionFadeIn,
                timingFunction: CAMediaTimingFunction(name: .easeOut)
            ) {
                window.animator().alphaValue = 1
            }

            try? await Task.sleep(for: .milliseconds(Int(NotchTokens.Animation.selectionFlashDuration * 1000)))
            guard !Task.isCancelled else { return }

            await NSAnimationHelper.animate(
                duration: NotchTokens.Animation.selectionFadeOut,
                timingFunction: CAMediaTimingFunction(name: .easeIn)
            ) {
                window.animator().alphaValue = 0
            }
        }
    }

    // MARK: - Window Lookup

    struct ITermWindowSnapshot {
        let frame: CGRect
        let windowNumber: Int
    }

    static func frontmostiTermWindow() -> ITermWindowSnapshot? {
        // TODO: CGWindowListCopyWindowInfo deprecated in macOS 14.2 — no direct replacement available yet
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            NSLog("[WindowHighlighter] CGWindowListCopyWindowInfo returned nil — Screen Recording permission may be missing")
            return nil
        }

        guard let info = windowList.first(where: {
            ($0[kCGWindowOwnerName as String] as? String) == "iTerm2"
        }) else {
            NSLog("[WindowHighlighter] No iTerm2 window found on screen")
            return nil
        }

        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else {
            NSLog("[WindowHighlighter] Unexpected window bounds format")
            return nil
        }

        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            NSLog("[WindowHighlighter] No screens available")
            return nil
        }

        guard let windowNumber = info[kCGWindowNumber as String] as? Int else {
            NSLog("[WindowHighlighter] Missing window number")
            return nil
        }

        // Convert from CGWindowList coordinates (top-left origin) to NSWindow coordinates (bottom-left origin)
        let frame = CGRect(
            x: cgBounds.origin.x,
            y: primaryHeight - cgBounds.maxY,
            width: cgBounds.width,
            height: cgBounds.height
        )
        return ITermWindowSnapshot(frame: frame, windowNumber: windowNumber)
    }

    static func iTermWindow(forTTY tty: String?) -> ITermWindowSnapshot? {
        guard let tty else { return frontmostiTermWindow() }

        // TODO: CGWindowListCopyWindowInfo deprecated in macOS 14.2 — no direct replacement available yet
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            log.error("CGWindowListCopyWindowInfo returned nil — Screen Recording permission may be missing")
            return nil
        }

        let itermWindows = windowList.filter {
            ($0[kCGWindowOwnerName as String] as? String) == "iTerm2"
        }

        guard !itermWindows.isEmpty else {
            log.info("No iTerm2 windows found on screen while looking up TTY \"\(tty, privacy: .private)\"")
            return nil
        }

        // If only one iTerm window, return it directly
        if itermWindows.count == 1, let info = itermWindows.first {
            return snapshot(from: info)
        }

        // Multiple windows: validate TTY before AppleScript interpolation (fix injection vulnerability)
        guard isValidTTY(tty) else {
            log.error("TTY \"\(tty, privacy: .private)\" failed validation — falling back to frontmost iTerm window")
            return frontmostiTermWindow()
        }

        // Multiple windows: use AppleScript to find which contains the TTY
        let source = """
        tell application "iTerm"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then
                  return id of w
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            log.error("Failed to compile AppleScript for TTY lookup — falling back to frontmost iTerm window")
            return frontmostiTermWindow()
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            log.error("AppleScript execution failed during TTY lookup: \(error, privacy: .public) — falling back to frontmost iTerm window")
            return frontmostiTermWindow()
        }

        let windowID = result.int32Value
        if let info = itermWindows.first(where: {
            ($0[kCGWindowNumber as String] as? Int32) == windowID
        }) {
            return snapshot(from: info)
        }

        log.warning("AppleScript returned window ID \(windowID) which does not match any on-screen iTerm2 window — falling back to frontmost iTerm window")
        return frontmostiTermWindow()
    }

    /// Returns true if `tty` matches the expected `/dev/ttysNNN` format.
    /// Exposed as `internal` (not `private`) so tests can verify the validation logic.
    nonisolated static func isValidTTY(_ tty: String) -> Bool {
        let ttyPattern = #"^/dev/ttys\d+$"#
        return tty.range(of: ttyPattern, options: .regularExpression) != nil
    }

    private static func snapshot(from info: [String: Any]) -> ITermWindowSnapshot? {
        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else {
            log.error("Window info missing bounds dictionary (kCGWindowBounds)")
            return nil
        }
        guard let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            log.error("Unexpected window bounds format — could not deserialize CGRect")
            return nil
        }
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            log.error("No screens available — cannot convert window coordinates")
            return nil
        }
        guard let windowNumber = info[kCGWindowNumber as String] as? Int else {
            log.error("Window info missing window number (kCGWindowNumber)")
            return nil
        }

        let frame = CGRect(
            x: cgBounds.origin.x,
            y: primaryHeight - cgBounds.maxY,
            width: cgBounds.width,
            height: cgBounds.height
        )
        return ITermWindowSnapshot(frame: frame, windowNumber: windowNumber)
    }
}
