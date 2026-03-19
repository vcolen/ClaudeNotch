import SwiftUI

struct NotchView: View {
    let instanceManager: InstanceManager
    let panelState: PanelState
    let notificationManager: NotificationManager
    var onNewInstance: (() -> Void)?
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    @State private var dismissTask: Task<Void, Never>?
    @State private var notificationDebounceTask: Task<Void, Never>?
    @State private var attentionDismissTask: Task<Void, Never>?

    private var attentionInstanceIds: Set<String> {
        Set(instanceManager.needsAttentionInstances.map(\.id))
    }

    // The window frame extends beyond the visible banner: it includes the notch area (on notch
    // screens), topMargin gap, and shadow padding. Outer clip/shadow are disabled in notification
    // mode so rounding applies to the pill, not the invisible spacer. NotificationBannerView
    // handles its own clip and shadow.
    private var bottomRadius: CGFloat {
        switch panelState.mode {
        case .collapsed: NotchTokens.Size.collapsedCornerRadius
        case .notification: 0
        case .expanded: NotchTokens.Size.expandedCornerRadius
        }
    }

    private var shadowStyle: (color: Color, radius: CGFloat, y: CGFloat) {
        switch panelState.mode {
        case .collapsed, .notification:
            return (.clear, 0, 0)
        case .expanded:
            return (.black.opacity(0.4), 8, 4)
        }
    }

    private var clipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if panelState.hasNotch {
                Color.clear
                    .frame(height: panelState.notchHeight)
            }

            Group {
                switch panelState.mode {
                case .collapsed:
                    collapsedContent
                        .transition(.opacity)
                case .notification:
                    notificationContent
                        .padding(.top, NotchTokens.Notification.topMargin)
                        .transition(.opacity)
                case .expanded:
                    expandedContent
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                if panelState.mode == .expanded {
                    clipShape.fill(.ultraThinMaterial)
                    clipShape.fill(Color.black.opacity(0.3))
                    clipShape
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(clipShape)
        .shadow(color: shadowStyle.color, radius: shadowStyle.radius, y: shadowStyle.y)
        .onHover { hovering in
            if hovering {
                dismissTask?.cancel()
                dismissTask = nil
                expand()
            } else {
                dismissTask?.cancel()
                dismissTask = Task {
                    try? await Task.sleep(for: NotchTokens.Animation.dismissDelay)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { collapse() }
                }
            }
        }
        .animation(NotchTokens.Animation.expandSpring, value: panelState.mode)
        .onChange(of: instanceManager.instances.count) { _, newCount in
            if panelState.mode == .collapsed {
                panelState.contentHeight = CollapsedNotchView.contentHeight(
                    instanceCount: newCount,
                    maxWidth: panelState.notchWidth
                )
            }
        }
        .onChange(of: attentionInstanceIds) { oldIds, newIds in
            let newAttention = newIds.subtracting(oldIds)
            if !newAttention.isEmpty && (panelState.mode == .collapsed || panelState.mode == .notification) {
                attentionDismissTask?.cancel()
                enterNotificationMode()
            }
            if newIds.isEmpty && panelState.mode == .notification {
                attentionDismissTask?.cancel()
                attentionDismissTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    if instanceManager.needsAttentionInstances.isEmpty {
                        notificationManager.dismiss()
                    }
                }
            }
        }
        .onAppear {
            if instanceManager.needsAttentionCount > 0 {
                enterNotificationMode()
            }
        }
    }

    // MARK: - Content Views

    private var collapsedContent: some View {
        CollapsedNotchView(instanceManager: instanceManager, maxWidth: panelState.notchWidth)
    }

    private var notificationContent: some View {
        NotificationBannerView(
            item: notificationManager.currentItem,
            queuePosition: notificationManager.currentIndex,
            queueTotal: notificationManager.queueCount,
            onTap: { item in notificationManager.onTap?(item) },
            onDismiss: { notificationManager.dismiss() }
        )
        .animation(NotchTokens.Notification.swapAnimation, value: notificationManager.currentItem?.id)
    }

    private var expandedContent: some View {
        ExpandedNotchView(
            instanceManager: instanceManager,
            onNewInstance: onNewInstance,
            onSelectInstance: onSelectInstance
        )
    }

    // MARK: - State Transitions

    private func expand() {
        notificationDebounceTask?.cancel()
        attentionDismissTask?.cancel()
        if panelState.mode == .notification {
            // Stop notification rotation without triggering onDismiss callback
            notificationManager.cleanup()
        }
        guard panelState.mode != .expanded else { return }
        panelState.mode = .expanded
        instanceManager.startCostPolling()
        updateContentHeight()
    }

    private func collapse() {
        guard panelState.mode != .collapsed else { return }
        notificationDebounceTask?.cancel()
        attentionDismissTask?.cancel()
        if panelState.mode == .notification {
            notificationManager.cleanup()
        }
        panelState.mode = .collapsed
        instanceManager.stopCostPolling()
        panelState.contentHeight = CollapsedNotchView.contentHeight(
            instanceCount: instanceManager.instances.count,
            maxWidth: panelState.notchWidth
        )
    }

    private func enterNotificationMode() {
        notificationDebounceTask?.cancel()
        notificationDebounceTask = Task {
            do {
                try await Task.sleep(for: NotchTokens.Notification.debounceDelay)
            } catch {
                return
            }
            guard panelState.mode == .collapsed else {
                NSLog("NotchView: notification debounce cancelled or mode changed (mode=%@)", "\(panelState.mode)")
                return
            }

            let instances = instanceManager.needsAttentionInstances
            guard !instances.isEmpty else {
                NSLog("NotchView: no attention instances after debounce, skipping notification")
                return
            }

            let items: [NotificationItem] = instances.compactMap { inst in
                guard let attentionType = inst.attentionType else {
                    assertionFailure("Instance \(inst.id) in needsAttentionInstances but attentionType is nil")
                    return nil
                }
                return NotificationItem(
                    instanceId: inst.id,
                    projectName: inst.projectName,
                    branchName: inst.branchName,
                    terminalIndex: nil,
                    tty: inst.tty,
                    pid: inst.pid,
                    attentionType: attentionType
                )
            }
            .sorted { $0.attentionType < $1.attentionType }

            guard !items.isEmpty else { return }

            // Re-check mode hasn't changed during item construction
            guard !Task.isCancelled, panelState.mode == .collapsed else {
                NSLog("NotchView: notification cancelled before display (mode=%@)", "\(panelState.mode)")
                return
            }

            panelState.mode = .notification
            panelState.contentHeight = NotificationBannerView.contentHeight
            notificationManager.showNotifications(items)
        }
    }

    private func updateContentHeight() {
        let allGroups = instanceManager.needsInputGroups + instanceManager.taskFinishedGroups
            + instanceManager.workingGroups + instanceManager.waitingGroups + instanceManager.idleGroups
        var height: CGFloat = 50 // chrome (button + separator)

        // Section headers (28pt each)
        var sectionCount = 0
        if !instanceManager.needsInputGroups.isEmpty { sectionCount += 1 }
        if !instanceManager.taskFinishedGroups.isEmpty { sectionCount += 1 }
        if !instanceManager.workingGroups.isEmpty { sectionCount += 1 }
        if !instanceManager.waitingGroups.isEmpty { sectionCount += 1 }
        if !instanceManager.idleGroups.isEmpty { sectionCount += 1 }
        height += CGFloat(sectionCount) * 28

        for group in allGroups {
            if group.isSingle {
                height += 68 // single card height
            } else {
                height += 28 + CGFloat(group.count) * 40 + 8 // header + rows + padding
            }
        }

        panelState.contentHeight = max(120, min(height, 420))
    }
}

#Preview {
    NotchView(
        instanceManager: InstanceManager(skipBootstrap: true),
        panelState: PanelState(hasNotch: true, notchHeight: 37),
        notificationManager: NotificationManager()
    )
    .frame(width: 400, height: 500, alignment: .top)
    .background(Color.gray.opacity(0.2))
}
