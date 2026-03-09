import SwiftUI

struct ExpandedNotchView: View {
    let instanceManager: InstanceManager
    var onNewInstance: (() -> Void)?
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    @State private var isRevealed = false
    @State private var isButtonHovered = false

    var body: some View {
        VStack(spacing: 0) {
            if instanceManager.instances.isEmpty {
                emptyState
            } else {
                instanceList
            }

            separator

            newInstanceButton
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            isRevealed = false
            withAnimation(NotchTokens.Animation.contentReveal) {
                isRevealed = true
            }
        }
    }

    private var instanceList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let working = instanceManager.workingInstances
                let waiting = instanceManager.waitingInstances
                let idle = instanceManager.idleInstances
                let totalCount = working.count + waiting.count + idle.count
                var runningIndex = 0

                if !working.isEmpty {
                    sectionHeader("Running", color: NotchTokens.Status.working)
                    ForEach(working) { instance in
                        let idx = runningIndex
                        let _ = (runningIndex += 1)
                        cardView(instance: instance, index: idx, total: totalCount)
                    }
                }

                if !waiting.isEmpty {
                    sectionHeader("Awaiting Input", color: NotchTokens.Status.waiting)
                    ForEach(waiting) { instance in
                        let idx = runningIndex
                        let _ = (runningIndex += 1)
                        cardView(instance: instance, index: idx, total: totalCount)
                    }
                }

                if !idle.isEmpty {
                    sectionHeader("Idle", color: NotchTokens.Status.idle)
                    ForEach(idle) { instance in
                        let idx = runningIndex
                        let _ = (runningIndex += 1)
                        cardView(instance: instance, index: idx, total: totalCount)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .frame(maxHeight: 380)
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func cardView(instance: ClaudeInstance, index: Int, total: Int) -> some View {
        InstanceCardView(instance: instance) { selected in
            onSelectInstance?(selected)
        }
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : -6)
        .animation(
            .easeOut(duration: 0.25)
                .delay(NotchTokens.Animation.staggerDelay(index: index, total: total)),
            value: isRevealed
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 20, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("No instances running")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var separator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, NotchTokens.Surface.separator, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }

    private var newInstanceButton: some View {
        Button {
            onNewInstance?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("New Instance")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isButtonHovered ? 0.7 : 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isButtonHovered ? Color.white.opacity(0.06) : .clear)
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchTokens.Animation.hoverQuick) {
                isButtonHovered = hovering
            }
        }
    }
}

#Preview {
    ExpandedNotchView(
        instanceManager: InstanceManager()
    )
    .frame(width: 340)
    .background(Color.black)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
}
