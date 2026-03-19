import SwiftUI

struct NotificationBannerView: View {
    let item: NotificationItem?
    let queuePosition: Int
    let queueTotal: Int
    var onTap: ((NotificationItem) -> Void)?
    var onDismiss: (() -> Void)?

    static let contentHeight: CGFloat = NotchTokens.Notification.bannerHeight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let item {
            bannerContent(item: item)
                .id(item.id)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                )
        }
    }

    private func bannerContent(item: NotificationItem) -> some View {
        HStack(spacing: 8) {
            StatusDot(status: .waitingInput, isVisible: true, isAttention: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Needs attention \u{00B7} \(item.projectName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let branch = item.branchName {
                    Text(branch)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            if queueTotal > 1 {
                Text("\(queuePosition + 1)/\(queueTotal)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: Self.contentHeight)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Color.black
                LinearGradient(
                    colors: [NotchTokens.Status.attention.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: NotchTokens.Notification.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?(item)
        }
    }

}

#Preview {
    VStack(spacing: 12) {
        NotificationBannerView(
            item: NotificationItem(
                instanceId: "test-1",
                projectName: "my-project",
                branchName: "main",
                terminalIndex: 3,
                tty: "/dev/ttys001",
                pid: 1234
            ),
            queuePosition: 1,
            queueTotal: 3
        )

        NotificationBannerView(
            item: NotificationItem(
                instanceId: "test-2",
                projectName: "other-project",
                branchName: "feature/auth",
                terminalIndex: nil,
                tty: nil,
                pid: 5678
            ),
            queuePosition: 0,
            queueTotal: 1
        )
    }
    .frame(width: 320)
    .background(Color.gray.opacity(0.2))
}
