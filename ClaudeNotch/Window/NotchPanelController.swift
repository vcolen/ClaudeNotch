import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    let panel: NotchPanel
    let screen: NSScreen
    let panelState: PanelState
    let instanceManager: InstanceManager
    let notificationManager: NotificationManager

    private let expandedWidth: CGFloat = 340
    private var observationTask: Task<Void, Never>?

    init(screen: NSScreen, instanceManager: InstanceManager, notificationManager: NotificationManager) {
        self.screen = screen
        self.instanceManager = instanceManager
        self.notificationManager = notificationManager

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
            mode: .collapsed,
            hasNotch: hasNotch,
            notchHeight: notchHeight,
            collapsedWidth: notchWidth,
            expandedWidth: 340,
            contentHeight: panelState.contentHeight
        )
        self.panel = NotchPanel(contentRect: initialFrame)

        // Wire notification callbacks
        notificationManager.onDismiss = { [weak self] in
            guard let self else { return }
            if self.panelState.mode == .notification {
                self.panelState.mode = .collapsed
                self.panelState.contentHeight = CollapsedNotchView.contentHeight(
                    instanceCount: self.instanceManager.instances.count,
                    maxWidth: self.panelState.notchWidth
                )
            }
        }
        notificationManager.onTap = { [weak self] item in
            guard let self else { return }
            self.instanceManager.clearAttention(for: item.instanceId)
            self.notificationManager.dismiss()
            Task {
                await ITermIntegration.focusSession(tty: item.tty, pid: item.pid)
            }
        }

        let notchView = NotchView(
            instanceManager: instanceManager,
            panelState: panelState,
            notificationManager: notificationManager,
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
                _ = self.panelState.mode
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
            mode: panelState.mode,
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

        switch panelState.mode {
        case .collapsed:
            panel.hasShadow = false
            panel.updateCornerRadius(NotchTokens.Size.collapsedCornerRadius)
        case .notification:
            panel.hasShadow = true
            panel.updateCornerRadius(NotchTokens.Notification.cornerRadius)
        case .expanded:
            panel.hasShadow = true
            panel.updateCornerRadius(NotchTokens.Size.expandedCornerRadius)
        }
    }

    private static func computeFrame(
        screen: NSScreen,
        mode: NotchMode,
        hasNotch: Bool,
        notchHeight: CGFloat,
        collapsedWidth: CGFloat,
        expandedWidth: CGFloat,
        contentHeight: CGFloat
    ) -> NSRect {
        let screenFrame = screen.frame

        let width: CGFloat
        switch mode {
        case .collapsed:
            width = collapsedWidth
        case .notification:
            width = min(collapsedWidth + 80, 320)
        case .expanded:
            width = expandedWidth
        }

        let x = screenFrame.midX - width / 2

        if hasNotch {
            let totalHeight: CGFloat
            if mode == .notification {
                totalHeight = notchHeight + NotificationBannerView.contentHeight
            } else {
                totalHeight = notchHeight + contentHeight
            }
            let y = screenFrame.maxY - totalHeight
            return NSRect(x: x, y: y, width: width, height: totalHeight)
        } else {
            let effectiveHeight = mode == .notification ? NotificationBannerView.contentHeight : contentHeight
            let y = screenFrame.maxY - effectiveHeight
            return NSRect(x: x, y: y, width: width, height: effectiveHeight)
        }
    }

    func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        panel.orderOut(nil)
    }
}
