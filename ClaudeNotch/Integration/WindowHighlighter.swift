import AppKit

@MainActor
enum WindowHighlighter {

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

        container.layer?.shadowColor = glowNSColor.cgColor
        container.layer?.shadowOpacity = 0.55
        container.layer?.shadowRadius = 20
        container.layer?.shadowOffset = .zero
        container.layer?.shadowPath = shapePath
        window.contentView = container

        // Start invisible, animate in
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.order(.below, relativeTo: iterm.windowNumber)
        activeWindow = window

        flashTask = Task { @MainActor in
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = NotchTokens.Animation.selectionFadeIn
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }

            try? await Task.sleep(for: .milliseconds(Int(NotchTokens.Animation.selectionFlashDuration * 1000)))
            guard !Task.isCancelled else { return }

            await NSAnimationContext.runAnimationGroup { context in
                context.duration = NotchTokens.Animation.selectionFadeOut
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }
            window.orderOut(nil)
            if activeWindow === window {
                activeWindow = nil
            }
        }
    }

    // MARK: - Window Lookup

    private struct ITermWindowSnapshot {
        let frame: CGRect
        let windowNumber: Int
    }

    private static func frontmostiTermWindow() -> ITermWindowSnapshot? {
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

        guard let boundsValue = info[kCGWindowBounds as String],
              let cgBounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
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
}
