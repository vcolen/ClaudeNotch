import SwiftUI

struct InstanceCardView: View {
    let instance: ClaudeInstance
    var onTap: ((ClaudeInstance) -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top row: project name + status badge
            HStack(alignment: .center) {
                HStack(spacing: 0) {
                    Text(instance.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)

                    if let branch = instance.branchName {
                        Text("  /  ")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(NotchTokens.Branch.separator)
                            .lineLimit(1)

                        Text(branch)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(NotchTokens.Branch.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                statusBadge
            }

            // Bottom row: model + cost
            HStack(spacing: 6) {
                if let model = instance.model {
                    Text(model)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                if let cost = instance.cost {
                    Text(formattedCost(cost))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            // Context bar
            if instance.contextUsagePercent != nil {
                ContextUsageBar(percent: instance.contextUsagePercent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: NotchTokens.Size.cardCornerRadius, style: .continuous)
                .fill(isHovered ? NotchTokens.Surface.cardHover : NotchTokens.Surface.cardBackground)
        )
        .overlay {
            // Status color bleed for working or attention instances
            if instance.status == .working || instance.needsAttention {
                RoundedRectangle(cornerRadius: NotchTokens.Size.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [instance.displayColor.opacity(0.06), .clear],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            // Top-edge highlight on hover
            if isHovered {
                RoundedRectangle(cornerRadius: NotchTokens.Size.cardCornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchTokens.Animation.hoverQuick) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onTap?(instance)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(instance.displayColor)
                .frame(width: 5, height: 5)

            Text(instance.attentionType?.displayName ?? instance.status.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(instance.displayColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(instance.displayColor.opacity(0.12))
        )
    }

    private func formattedCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }
}

#Preview {
    VStack(spacing: 4) {
        InstanceCardView(instance: {
            let i = ClaudeInstance(id: "test-1", pid: 1234, cwd: "/Users/dev/my-project", status: .working)
            i.model = "opus 4.6"
            i.cost = 1.23
            i.contextUsagePercent = 0.65
            i.branchName = "main"
            return i
        }())

        InstanceCardView(instance: {
            let i = ClaudeInstance(id: "test-2", pid: 5678, cwd: "/Users/dev/other-project", status: .waitingInput)
            i.model = "sonnet 4.6"
            i.cost = 0.45
            i.contextUsagePercent = 0.3
            i.branchName = "feature/PROJ-1234-implement-user-auth-flow"
            return i
        }())

        InstanceCardView(instance: {
            let i = ClaudeInstance(id: "test-3", pid: 9999, cwd: "/Users/dev/idle-project", status: .idle)
            return i
        }())
    }
    .padding(8)
    .frame(width: 340)
    .background(Color.black)
}
