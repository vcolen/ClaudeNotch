import SwiftUI

struct NotchView: View {
    let instanceManager: InstanceManager
    let panelState: PanelState
    let notificationManager: NotificationManager
    var onNewInstance: (() -> Void)?
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    @State private var dismissTask: Task<Void, Never>?
    @State private var notificationDebounceTask: Task<Void, Never>?

    private var attentionInstanceIds: Set<String> {
        Set(instanceManager.needsAttentionInstances.map(\.id))
    }

    private var bottomRadius: CGFloat {
        switch panelState.mode {
        case .collapsed: NotchTokens.Size.collapsedCornerRadius
        case .notification: NotchTokens.Notification.cornerRadius
        case .expanded: NotchTokens.Size.expandedCornerRadius
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

            switch panelState.mode {
            case .collapsed:
                collapsedContent
                    .transition(.opacity)
            case .notification:
                notificationContent
                    .transition(.opacity)
            case .expanded:
                expandedContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
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
        .shadow(
            color: panelState.mode == .expanded ? .black.opacity(0.4) : (panelState.mode == .notification ? .black.opacity(0.2) : .clear),
            radius: panelState.mode == .expanded ? 8 : (panelState.mode == .notification ? 4 : 0),
            y: panelState.mode == .expanded ? 4 : (panelState.mode == .notification ? 2 : 0)
        )
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
            if !newAttention.isEmpty && panelState.mode == .collapsed {
                enterNotificationMode()
            }
            if newIds.isEmpty && panelState.mode == .notification {
                notificationManager.dismiss()
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
        if panelState.mode == .notification {
            // Cancel notification lifecycle without triggering onDismiss → mode change
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
            try? await Task.sleep(for: NotchTokens.Notification.debounceDelay)
            guard !Task.isCancelled, panelState.mode == .collapsed else { return }

            let instances = instanceManager.needsAttentionInstances
            guard !instances.isEmpty else { return }

            // Build items synchronously first, then look up tab indices async
            var items: [NotificationItem] = instances.map { inst in
                NotificationItem(
                    instanceId: inst.id,
                    projectName: inst.projectName,
                    branchName: inst.branchName,
                    terminalIndex: nil,
                    tty: inst.tty,
                    pid: inst.pid
                )
            }

            // Re-check state hasn't changed during our work
            guard !Task.isCancelled, panelState.mode == .collapsed else { return }

            panelState.mode = .notification
            panelState.contentHeight = NotificationBannerView.contentHeight
            notificationManager.showNotifications(items)

            // Look up tab indices in the background and update items
            for i in items.indices {
                guard !Task.isCancelled else { return }
                if let tty = items[i].tty {
                    if let tabIndex = await ITermIntegration.lookupTabIndex(forTTY: tty) {
                        items[i] = NotificationItem(
                            instanceId: items[i].instanceId,
                            projectName: items[i].projectName,
                            branchName: items[i].branchName,
                            terminalIndex: tabIndex,
                            tty: items[i].tty,
                            pid: items[i].pid
                        )
                    }
                }
            }
            // Update with enriched items if still in notification mode
            guard !Task.isCancelled, panelState.mode == .notification else { return }
            notificationManager.showNotifications(items)
        }
    }

    private func updateContentHeight() {
        let allGroups = instanceManager.needsAttentionGroups + instanceManager.workingGroups + instanceManager.waitingGroups + instanceManager.idleGroups
        var height: CGFloat = 50 // chrome (button + separator)

        // Section headers (~28pt each)
        var sectionCount = 0
        if !instanceManager.needsAttentionGroups.isEmpty { sectionCount += 1 }
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
