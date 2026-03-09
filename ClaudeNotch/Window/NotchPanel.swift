import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
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
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = .clear
        contentView = hostingView
    }
}
