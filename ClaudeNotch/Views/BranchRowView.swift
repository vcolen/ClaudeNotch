import SwiftUI

struct BranchRowView: View {
    let instance: ClaudeInstance
    let isLast: Bool
    var onTap: ((ClaudeInstance) -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                treeConnector
                    .frame(width: 12, height: 14)

                Text(instance.branchName ?? "default")
                    .font(NotchTokens.BranchRow.branchFont)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if let model = instance.model {
                    Text(model)
                        .font(NotchTokens.BranchRow.metaFont)
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }

                if let cost = instance.cost {
                    Text(String(format: "$%.2f", cost))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Circle()
                    .fill(instance.needsAttention ? NotchTokens.Status.attention : instance.status.color)
                    .frame(width: 5, height: 5)
            }

            if instance.contextUsagePercent != nil {
                ContextUsageBar(percent: instance.contextUsagePercent)
                    .frame(height: NotchTokens.BranchRow.contextBarHeight)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, NotchTokens.BranchRow.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.06) : .clear)
        )
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

    private var treeConnector: some View {
        let lineColor = Color.white.opacity(0.15)
        return Canvas { context, size in
            let midX = size.width * 0.3
            let midY = size.height / 2
            // Vertical line: top to middle (or full height if not last)
            var vPath = Path()
            vPath.move(to: CGPoint(x: midX, y: 0))
            vPath.addLine(to: CGPoint(x: midX, y: isLast ? midY : size.height))
            context.stroke(vPath, with: .color(lineColor), lineWidth: 0.75)
            // Horizontal arm from midX to right
            var hPath = Path()
            hPath.move(to: CGPoint(x: midX, y: midY))
            hPath.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(hPath, with: .color(lineColor), lineWidth: 0.75)
        }
    }
}
