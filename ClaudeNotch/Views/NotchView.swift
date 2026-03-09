import SwiftUI

struct NotchView: View {
    let instanceManager: InstanceManager
    let panelState: PanelState
    var onNewInstance: (() -> Void)?
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    @State private var dismissTask: Task<Void, Never>?

    private var bottomRadius: CGFloat {
        panelState.isExpanded ? 16 : 8
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

            if panelState.isExpanded {
                expandedContent
                    .transition(.opacity)
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                if panelState.isExpanded {
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
            color: panelState.isExpanded ? .black.opacity(0.4) : .clear,
            radius: panelState.isExpanded ? 8 : 0,
            y: panelState.isExpanded ? 4 : 0
        )
        .onHover { hovering in
            if hovering {
                dismissTask?.cancel()
                dismissTask = nil
                expand()
            } else {
                dismissTask?.cancel()
                dismissTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { collapse() }
                }
            }
        }
        .animation(NotchTokens.Animation.expandSpring, value: panelState.isExpanded)
        .onChange(of: instanceManager.instances.count) { _, newCount in
            if !panelState.isExpanded {
                panelState.contentHeight = CollapsedNotchView.contentHeight(
                    instanceCount: newCount,
                    maxWidth: panelState.notchWidth
                )
            }
        }
    }

    private var collapsedContent: some View {
        CollapsedNotchView(instanceManager: instanceManager, maxWidth: panelState.notchWidth)
    }

    private var expandedContent: some View {
        ExpandedNotchView(
            instanceManager: instanceManager,
            onNewInstance: onNewInstance,
            onSelectInstance: onSelectInstance
        )
    }

    private func expand() {
        guard !panelState.isExpanded else { return }
        panelState.isExpanded = true
        instanceManager.startCostPolling()
        updateContentHeight()
    }

    private func collapse() {
        guard panelState.isExpanded else { return }
        panelState.isExpanded = false
        instanceManager.stopCostPolling()
        panelState.contentHeight = CollapsedNotchView.contentHeight(
            instanceCount: instanceManager.instances.count,
            maxWidth: panelState.notchWidth
        )
    }

    private func updateContentHeight() {
        let allGroups = instanceManager.workingGroups + instanceManager.waitingGroups + instanceManager.idleGroups
        var height: CGFloat = 50 // chrome (button + separator)

        // Section headers (~28pt each)
        var sectionCount = 0
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
        instanceManager: InstanceManager(),
        panelState: PanelState(hasNotch: true, notchHeight: 37)
    )
    .frame(width: 400, height: 500, alignment: .top)
    .background(Color.gray.opacity(0.2))
}
