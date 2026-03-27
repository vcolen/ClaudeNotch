import SwiftUI

struct ExpandedNotchView: View {
    let instanceManager: InstanceManager
    var tiler: TerminalWindowTiler?
    var onNewInstance: (() -> Void)?
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    @State private var isRevealed = false
    // Managed inline because hover state drives foreground text opacity.
    @State private var isButtonHovered = false
    @State private var isTidyHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

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
            if !reduceMotion { isRevealed = false }
            withMotionAnimation(NotchTokens.Animation.contentReveal, reduceMotion: reduceMotion) {
                isRevealed = true
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                tiler?.tidy()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(
                        tiler?.canTidy == true
                            ? (isTidyHovered ? 0.8 : 0.5)
                            : 0.3
                    ))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isTidyHovered ? Color.white.opacity(0.06) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(tiler?.canTidy != true)
            .onHover { hovering in
                withMotionAnimation(NotchTokens.Animation.hoverQuick, reduceMotion: reduceMotion) {
                    isTidyHovered = hovering
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var instanceList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let sections: [(title: String, color: Color, groups: [ProjectGroup])] = [
                    ("Needs Input", NotchTokens.Status.needsInput, instanceManager.needsInputGroups),
                    ("Finished", NotchTokens.Status.taskFinished, instanceManager.taskFinishedGroups),
                    ("Running", NotchTokens.Status.working, instanceManager.workingGroups),
                    ("Awaiting Input", NotchTokens.Status.waiting, instanceManager.waitingGroups),
                    ("Idle", NotchTokens.Status.idle, instanceManager.idleGroups),
                ]
                let activeSections = sections.filter { !$0.groups.isEmpty }
                let totalGroups = activeSections.reduce(0) { $0 + $1.groups.count }
                var runningIndex = 0

                ForEach(activeSections, id: \.title) { section in
                    sectionHeader(section.title, color: section.color)
                    ForEach(section.groups) { group in
                        let idx = runningIndex
                        let _ = (runningIndex += 1)
                        groupView(group: group, index: idx, total: totalGroups)
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

    private func groupView(group: ProjectGroup, index: Int, total: Int) -> some View {
        ProjectGroupView(group: group) { selected in
            onSelectInstance?(selected)
        }
        .staggerReveal(isRevealed: isRevealed, index: index, total: total)
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
            withMotionAnimation(NotchTokens.Animation.hoverQuick, reduceMotion: reduceMotion) {
                isButtonHovered = hovering
            }
        }
    }
}

#Preview {
    ExpandedNotchView(
        instanceManager: InstanceManager(),
        tiler: nil
    )
    .frame(width: 340)
    .background(Color.black)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
}
