import AppKit
import SwiftUI
import Testing
@testable import ClaudeNotch

@Suite("NotchPanel Tests")
struct NotchPanelTests {

    @Test("ClickThroughHostingView accepts first mouse")
    @MainActor
    func clickThroughAcceptsFirstMouse() {
        let view = ClickThroughHostingView(rootView: EmptyView())
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }

    @Test("NotchPanel can become key")
    @MainActor
    func panelCanBecomeKey() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50))
        #expect(panel.canBecomeKey == true)
    }

    @Test("NotchPanel cannot become main")
    @MainActor
    func panelCannotBecomeMain() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50))
        #expect(panel.canBecomeMain == false)
    }
}
