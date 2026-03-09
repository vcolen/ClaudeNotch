import SwiftUI

struct ProjectGroupView: View {
    let group: ProjectGroup
    var onSelectInstance: ((ClaudeInstance) -> Void)?

    var body: some View {
        if group.isSingle {
            InstanceCardView(instance: group.instances[0]) { selected in
                onSelectInstance?(selected)
            }
        } else {
            multiInstanceView
        }
    }

    private var multiInstanceView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Project header
            HStack(spacing: 6) {
                Text(group.displayName)
                    .font(NotchTokens.ProjectGroup.headerFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("(\(group.count))")
                    .font(NotchTokens.ProjectGroup.countBadgeFont)
                    .foregroundStyle(NotchTokens.ProjectGroup.countBadgeColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)

            // Branch rows — zero spacing so tree lines connect
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.instances.enumerated()), id: \.element.id) { index, instance in
                    BranchRowView(
                        instance: instance,
                        isLast: index == group.instances.count - 1
                    ) { selected in
                        onSelectInstance?(selected)
                    }
                }
            }
            .padding(.leading, 10)
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: NotchTokens.ProjectGroup.containerCornerRadius, style: .continuous)
                .fill(NotchTokens.ProjectGroup.containerBackground)
        )
    }
}
