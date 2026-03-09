import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    let panel: NotchPanel
    let screen: NSScreen
    let panelState: PanelState
    let instanceManager: InstanceManager

    private let collapsedWidth: CGFloat = 220
    private let expandedWidth: CGFloat = 340
    private let hoverZoneHeight: CGFloat = 6

    private var observationTask: Task<Void, Never>?

    init(screen: NSScreen, instanceManager: InstanceManager) {
        self.screen = screen
        self.instanceManager = instanceManager

        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = screen.safeAreaInsets.top
        self.panelState = PanelState(hasNotch: hasNotch, notchHeight: notchHeight)

        let initialFrame = Self.computeFrame(
            screen: screen,
            expanded: false,
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            collapsedWidth: collapsedWidth,
            expandedWidth: expandedWidth,
            hoverZoneHeight: hoverZoneHeight,
            contentHeight: panelState.contentHeight
        )
        self.panel = NotchPanel(contentRect: initialFrame)

        let notchView = NotchView(
            instanceManager: instanceManager,
            panelState: panelState,
            onNewInstance: {
                let recentDirs = RecentProjectsStore.recentProjects
                if let firstDir = recentDirs.first {
                    ITermIntegration.launchNewInstance(in: firstDir)
                } else {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Choose a directory for the new Claude instance"
                    if panel.runModal() == .OK, let url = panel.url {
                        ITermIntegration.launchNewInstance(in: url.path)
                    }
                }
            },
            onSelectInstance: { instance in
                ITermIntegration.focusSession(tty: instance.tty, pid: instance.pid)
            }
        )
        panel.setContent(notchView)
        panel.orderFrontRegardless()

        startObservingState()
    }

    private func startObservingState() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            guard let self else { return }
            withObservationTracking {
                _ = self.panelState.isExpanded
                _ = self.panelState.contentHeight
            } onChange: {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateFrame()
                    self.startObservingState()
                }
            }
        }
    }

    func updateFrame() {
        let frame = Self.computeFrame(
            screen: screen,
            expanded: panelState.isExpanded,
            hasNotch: panelState.hasNotch,
            notchHeight: panelState.notchHeight,
            collapsedWidth: collapsedWidth,
            expandedWidth: expandedWidth,
            hoverZoneHeight: hoverZoneHeight,
            contentHeight: panelState.contentHeight
        )
        panel.setFrame(frame, display: true, animate: panelState.isExpanded)
    }

    private static func computeFrame(
        screen: NSScreen,
        expanded: Bool,
        hasNotch: Bool,
        notchHeight: CGFloat,
        collapsedWidth: CGFloat,
        expandedWidth: CGFloat,
        hoverZoneHeight: CGFloat,
        contentHeight: CGFloat
    ) -> NSRect {
        let screenFrame = screen.frame
        let width = expanded ? expandedWidth : collapsedWidth
        let x = screenFrame.midX - width / 2

        if hasNotch {
            // Panel extends from screen top (behind notch) downward.
            // Total height = notch area + visible content below notch.
            let totalHeight = notchHeight + contentHeight
            let y = screenFrame.maxY - totalHeight
            return NSRect(x: x, y: y, width: width, height: totalHeight)
        } else {
            // External display: thin hover zone at top
            let height = expanded ? contentHeight : hoverZoneHeight
            let y = screenFrame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }

    func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        panel.orderOut(nil)
    }
}
