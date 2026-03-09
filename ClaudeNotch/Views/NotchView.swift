import SwiftUI

struct NotchView: View {
    let instanceManager: InstanceManager
    let panelState: PanelState
    var onNewInstance: (() -> Void)?
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    @State private var dismissTask: Task<Void, Never>?

    private var notchShape: NotchShape {
        NotchShape(bottomRadius: panelState.isExpanded ? 14 : 12)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Invisible spacer that sits behind the physical notch
            if panelState.hasNotch {
                Color.clear
                    .frame(height: panelState.notchHeight)
            }

            // Visible content below the notch
            if panelState.isExpanded {
                expandedContent
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.95, anchor: .top)
                                .combined(with: .offset(y: -8))
                                .combined(with: .opacity),
                            removal: .opacity.combined(with: .offset(y: -4))
                        )
                    )
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .frame(width: panelState.isExpanded ? 340 : nil)
        .background(
            ZStack {
                // Layer 1: Dark base
                notchShape
                    .fill(Color.black.opacity(0.85))

                // Layer 2: Glass material (only when expanded on notch screens)
                if panelState.isExpanded && panelState.hasNotch {
                    notchShape
                        .fill(.ultraThinMaterial)
                }

                // Layer 3: Edge highlight
                notchShape
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .drawingGroup()
            }
        )
        .clipShape(notchShape)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
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
    }

    private var collapsedContent: some View {
        CollapsedNotchView(instanceManager: instanceManager)
            .frame(height: NotchTokens.Size.collapsedHeight)
    }

    private var expandedContent: some View {
        ExpandedNotchView(
            instanceManager: instanceManager,
            panelState: panelState,
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
        panelState.contentHeight = NotchTokens.Size.collapsedHeight
    }

    private func updateContentHeight() {
        let instanceCount = instanceManager.instances.count
        let cardHeight: CGFloat = 76
        let chrome: CGFloat = 50 // button + divider + padding
        let estimatedHeight = max(
            120,
            min(CGFloat(instanceCount) * cardHeight + chrome, 420)
        )
        panelState.contentHeight = estimatedHeight
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
