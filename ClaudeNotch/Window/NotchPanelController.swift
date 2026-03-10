import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    let panel: NotchPanel
    let screen: NSScreen
    let panelState: PanelState
    let instanceManager: InstanceManager

    private let expandedWidth: CGFloat = 340
    private var observationTask: Task<Void, Never>?

    init(screen: NSScreen, instanceManager: InstanceManager) {
        self.screen = screen
        self.instanceManager = instanceManager

        let hasNotch = screen.safeAreaInsets.top > 0
        let notchHeight = screen.safeAreaInsets.top

        let notchWidth: CGFloat
        if hasNotch,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            notchWidth = rightArea.minX - leftArea.maxX
        } else {
            notchWidth = 220
        }

        self.panelState = PanelState(
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            notchWidth: notchWidth
        )

        // Set initial collapsed height based on current instances
        panelState.contentHeight = CollapsedNotchView.contentHeight(
            instanceCount: instanceManager.instances.count,
            maxWidth: notchWidth
        )

        let initialFrame = Self.computeFrame(
            screen: screen,
            expanded: false,
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            collapsedWidth: notchWidth,
            expandedWidth: expandedWidth,
            contentHeight: panelState.contentHeight
        )
        self.panel = NotchPanel(contentRect: initialFrame)

        let notchView = NotchView(
            instanceManager: instanceManager,
            panelState: panelState,
            onNewInstance: {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.message = "Choose a directory for the new Claude instance"
                if let recentDir = RecentProjectsStore.recentProjects.first {
                    panel.directoryURL = URL(fileURLWithPath: recentDir)
                }
                if panel.runModal() == .OK, let url = panel.url {
                    ITermIntegration.launchNewInstance(in: url.path)
                }
            },
            onSelectInstance: { instance in
                ITermIntegration.focusSession(tty: instance.tty, pid: instance.pid)
            }
        )
        panel.setContent(notchView)
        panel.updateCornerRadius(NotchTokens.Size.collapsedCornerRadius)
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
                    self.animateFrameUpdate()
                    self.startObservingState()
                }
            }
        }
    }

    private func animateFrameUpdate() {
        let frame = Self.computeFrame(
            screen: screen,
            expanded: panelState.isExpanded,
            hasNotch: panelState.hasNotch,
            notchHeight: panelState.notchHeight,
            collapsedWidth: panelState.notchWidth,
            expandedWidth: expandedWidth,
            contentHeight: panelState.contentHeight
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchTokens.Animation.frameDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.panel.animator().setFrame(frame, display: true)
        }

        panel.hasShadow = panelState.isExpanded
        panel.updateCornerRadius(panelState.isExpanded ? NotchTokens.Size.expandedCornerRadius : NotchTokens.Size.collapsedCornerRadius)
    }

    private static func computeFrame(
        screen: NSScreen,
        expanded: Bool,
        hasNotch: Bool,
        notchHeight: CGFloat,
        collapsedWidth: CGFloat,
        expandedWidth: CGFloat,
        contentHeight: CGFloat
    ) -> NSRect {
        let screenFrame = screen.frame
        let width = expanded ? expandedWidth : collapsedWidth
        let x = screenFrame.midX - width / 2

        if hasNotch {
            let totalHeight = notchHeight + contentHeight
            let y = screenFrame.maxY - totalHeight
            return NSRect(x: x, y: y, width: width, height: totalHeight)
        } else {
            let y = screenFrame.maxY - contentHeight
            return NSRect(x: x, y: y, width: width, height: contentHeight)
        }
    }

    func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        panel.orderOut(nil)
    }
}
