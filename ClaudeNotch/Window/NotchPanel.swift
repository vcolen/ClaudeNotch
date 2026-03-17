import AppKit
import SwiftUI

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchPanel: NSPanel {
    private weak var hostingLayer: CALayer?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setContent(_ view: some View) {
        let hostingView = ClickThroughHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = CGColor.clear
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.cornerCurve = .continuous
        if #available(macOS 14.0, *) {
            hostingView.sceneBridgingOptions = []
        }
        contentView = hostingView
        hostingLayer = hostingView.layer
    }

    func updateCornerRadius(_ radius: CGFloat) {
        hostingLayer?.cornerRadius = radius
        hostingLayer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }
}
