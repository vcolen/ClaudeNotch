import AppKit

@MainActor
enum WindowHighlighter {

    private static var activeWindow: NSWindow?

    private static let glowNSColor = NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1.0)
    private static let spread: CGFloat = 40
    private static let cornerRadius: CGFloat = 24

    static func flashiTermWindow() {
        guard let frame = frontmostiTermWindowFrame() else { return }

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

        // Pure CALayer glow — no SwiftUI, smooth anti-aliased shadows
        let container = NSView(frame: NSRect(origin: .zero, size: glowFrame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear
        container.layer?.masksToBounds = false

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

        // Single smooth glow — large radius + moderate opacity for a soft neon look
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
        if let itermWindowNumber = frontmostiTermWindowNumber() {
            window.order(.below, relativeTo: itermWindowNumber)
        }
        activeWindow = window

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + NotchTokens.Animation.selectionFlashDuration) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
                if activeWindow === window {
                    activeWindow = nil
                }
            }
        }
    }

    // MARK: - Window Lookup

    private static func frontmostiTermWindowFrame() -> CGRect? {
        guard let info = frontmostiTermWindowInfo(),
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let w = boundsDict["Width"],
              let h = boundsDict["Height"]
        else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: x, y: primaryHeight - y - h, width: w, height: h)
    }

    private static func frontmostiTermWindowNumber() -> Int? {
        guard let info = frontmostiTermWindowInfo(),
              let num = info[kCGWindowNumber as String] as? Int
        else { return nil }
        return num
    }

    private static func frontmostiTermWindowInfo() -> [String: Any]? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return windowList.first { info in
            (info[kCGWindowOwnerName as String] as? String) == "iTerm2"
        }
    }
}
