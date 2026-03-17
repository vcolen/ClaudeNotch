import AppKit
import SwiftUI

@MainActor
enum WindowHighlighter {

    private static var activeWindow: NSWindow?

    static func flashiTermWindow() {
        guard let frame = frontmostiTermWindowFrame() else { return }

        activeWindow?.orderOut(nil)

        let inset: CGFloat = -4
        let glowFrame = frame.insetBy(dx: inset, dy: inset)

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
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        let hostingView = NSHostingView(
            rootView: RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NotchTokens.Status.attention, lineWidth: 3)
                .padding(2)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = CGColor.clear
        window.contentView = hostingView

        window.alphaValue = 1
        window.orderFrontRegardless()
        activeWindow = window

        DispatchQueue.main.asyncAfter(deadline: .now() + NotchTokens.Animation.selectionFlashDuration) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NotchTokens.Animation.selectionFlashDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
                if activeWindow === window {
                    activeWindow = nil
                }
            }
        }
    }

    private static func frontmostiTermWindowFrame() -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  ownerName == "iTerm2",
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"]
            else { continue }

            // CGWindowList uses top-left origin; convert to NSWindow bottom-left origin
            let screenHeight = NSScreen.main?.frame.height ?? 0
            return CGRect(x: x, y: screenHeight - y - h, width: w, height: h)
        }

        return nil
    }
}
