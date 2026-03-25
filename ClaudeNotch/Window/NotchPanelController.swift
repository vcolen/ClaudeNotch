import AppKit
import SwiftUI

@MainActor
final class NotchPanelController {
    let panel: NotchPanel
    private(set) var screen: NSScreen
    let panelState: PanelState
    let instanceManager: InstanceManager
    let notificationManager: NotificationManager

    private let expandedWidth: CGFloat = 340
    private var observationTask: Task<Void, Never>?

    init(screen: NSScreen, instanceManager: InstanceManager) {
        self.screen = screen
        self.instanceManager = instanceManager
        self.notificationManager = NotificationManager()

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

        let initialFrame = Self.computeFrame(
            screen: screen,
            mode: .collapsed,
            hasNotch: geo.hasNotch,
            notchHeight: geo.notchHeight,
            collapsedWidth: geo.notchWidth,
            expandedWidth: expandedWidth,
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
            onSelectInstance: { [weak instanceManager, weak self] instance in
                guard let instanceManager, let self else { return }
                instanceManager.clearAttention(for: instance.id)

                // Launch from where the user clicked (the card)
                let notchCenter = NSEvent.mouseLocation
                let color = WaterDropAnimator.nsColor(for: instance)

                Task { @MainActor in
                    await ITermIntegration.focusSession(tty: instance.tty, pid: instance.pid)
                    try? await Task.sleep(for: .milliseconds(150))

                    guard let iterm = WindowHighlighter.iTermWindow(forTTY: instance.tty)
                        ?? WindowHighlighter.frontmostiTermWindow() else { return }

                    WaterDropAnimator.animate(
                        from: notchCenter,
                        to: iterm.frame,
                        terminalWindowNumber: iterm.windowNumber,
                        color: color,
                        on: self.screen
                    )
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

        guard panel.frame != frame else { return }

        NSAnimationHelper.animate(
            duration: NotchTokens.Animation.frameDuration,
            timingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
            allowsImplicitAnimation: true
        ) {
            self.panel.animator().setFrame(frame, display: true)
        }

        panel.hasShadow = (panelState.mode == .expanded)
        switch panelState.mode {
        case .collapsed:
            panel.updateCornerRadius(NotchTokens.Size.collapsedCornerRadius)
        case .notification:
            panel.updateCornerRadius(0)
        case .expanded:
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
            width = hasNotch ? max(collapsedWidth, 300) : min(collapsedWidth + 80, 320)
        case .expanded:
            width = expandedWidth
        }

        let x = screenFrame.midX - width / 2
        let notificationHeight = NotchTokens.Notification.topMargin + NotificationBannerView.contentHeight + NotchTokens.Notification.shadowPadding

        if hasNotch {
            let totalHeight = mode == .notification
                ? notchHeight + notificationHeight
                : notchHeight + contentHeight
            let y = screenFrame.maxY - totalHeight
            return NSRect(x: x, y: y, width: width, height: totalHeight)
        } else {
            let effectiveHeight = mode == .notification ? notificationHeight : contentHeight
            let y = screenFrame.maxY - effectiveHeight
            return NSRect(x: x, y: y, width: width, height: effectiveHeight)
        }
    }

    func updateScreen(_ newScreen: NSScreen) {
        screen = newScreen
        let geo = ScreenGeometry(screen: newScreen)

        panelState.hasNotch = geo.hasNotch
        panelState.notchHeight = geo.notchHeight
        panelState.notchWidth = geo.notchWidth

        if panelState.mode == .collapsed {
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
