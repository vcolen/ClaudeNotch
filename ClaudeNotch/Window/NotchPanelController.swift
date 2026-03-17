import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    let panel: NotchPanel
    private(set) var screen: NSScreen
    let panelState: PanelState
    let instanceManager: InstanceManager

    private let expandedWidth: CGFloat = 340
    private var observationTask: Task<Void, Never>?

    init(screen: NSScreen, instanceManager: InstanceManager) {
        self.screen = screen
        self.instanceManager = instanceManager

        let geo = ScreenGeometry(screen: screen)

        self.panelState = PanelState(
            hasNotch: geo.hasNotch,
            notchHeight: geo.notchHeight,
            notchWidth: geo.notchWidth
        )

        panelState.contentHeight = CollapsedNotchView.contentHeight(
            instanceCount: instanceManager.instances.count,
            maxWidth: geo.notchWidth
        )

        let initialFrame = NSRect(
            x: screen.frame.midX - geo.notchWidth / 2,
            y: screen.frame.maxY - (geo.notchHeight + panelState.contentHeight),
            width: geo.notchWidth,
            height: geo.notchHeight + panelState.contentHeight
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
            onSelectInstance: { [weak instanceManager] instance in
                guard let instanceManager else { return }
                instanceManager.clearAttention(for: instance.id)
                Task {
                    await ITermIntegration.focusSession(tty: instance.tty, pid: instance.pid)
                }
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
        let frame = currentFrame()

        panel.hasShadow = panelState.isExpanded
        panel.updateCornerRadius(panelState.isExpanded ? NotchTokens.Size.expandedCornerRadius : NotchTokens.Size.collapsedCornerRadius)

        guard panel.frame != frame else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchTokens.Animation.frameDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.panel.animator().setFrame(frame, display: true)
        }
    }

    private func currentFrame() -> NSRect {
        let screenFrame = screen.frame
        let width = panelState.isExpanded ? expandedWidth : panelState.notchWidth
        let totalHeight = panelState.notchHeight + panelState.contentHeight
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - totalHeight,
            width: width,
            height: totalHeight
        )
    }

    func updateScreen(_ newScreen: NSScreen) {
        screen = newScreen
        let geo = ScreenGeometry(screen: newScreen)

        panelState.hasNotch = geo.hasNotch
        panelState.notchHeight = geo.notchHeight
        panelState.notchWidth = geo.notchWidth

        if !panelState.isExpanded {
            panelState.contentHeight = CollapsedNotchView.contentHeight(
                instanceCount: instanceManager.instances.count,
                maxWidth: geo.notchWidth
            )
        }

        animateFrameUpdate()
    }

    func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        panel.orderOut(nil)
    }

    private struct ScreenGeometry {
        let hasNotch: Bool
        let notchHeight: CGFloat
        let notchWidth: CGFloat

        init(screen: NSScreen) {
            hasNotch = screen.safeAreaInsets.top > 0
            notchHeight = screen.safeAreaInsets.top
            if hasNotch,
               let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea {
                notchWidth = rightArea.minX - leftArea.maxX
            } else if hasNotch {
                assertionFailure("Screen has notch but no auxiliary top areas")
                notchWidth = NotchTokens.Size.defaultCollapsedWidth
            } else {
                notchWidth = NotchTokens.Size.defaultCollapsedWidth
            }
        }
    }
}
