import SwiftUI

struct CollapsedNotchView: View {
    let instanceManager: InstanceManager
    let maxWidth: CGFloat

    static let dotSize: CGFloat = 7
    static let dotSpacing: CGFloat = 5
    static let pillHPad: CGFloat = 8
    static let pillVPad: CGFloat = 3
    static let rowSpacing: CGFloat = 3

    var body: some View {
        Group {
            if instanceManager.instances.isEmpty {
                emptyRing
            } else {
                dotGrid
            }
        }
        .padding(.horizontal, Self.pillHPad)
        .padding(.vertical, Self.pillVPad)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black)
        )
    }

    private var emptyRing: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.2), Color.white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .frame(width: 6, height: 6)
    }

    private var dotGrid: some View {
        let dots = dotInfos
        let perRow = Self.dotsPerRow(maxWidth: maxWidth)
        let rows = Self.makeRows(dots: dots, perRow: perRow)

        return VStack(spacing: Self.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.dotSpacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, info in
                        StatusDot(status: info.status, isVisible: true, attentionColor: info.attentionColor)
                    }
                }
            }
        }
    }

    private var dotInfos: [DotInfo] {
        instanceManager.sortedInstances.map {
            DotInfo(status: $0.status, attentionColor: $0.attentionType?.color)
        }
    }

    // MARK: - Layout Calculation (static, shared with PanelState)

    static func dotsPerRow(maxWidth: CGFloat) -> Int {
        let availableWidth = maxWidth - pillHPad * 2
        return max(1, Int((availableWidth + dotSpacing) / (dotSize + dotSpacing)))
    }

    static func contentHeight(instanceCount: Int, maxWidth: CGFloat) -> CGFloat {
        if instanceCount == 0 {
            return 6 + pillVPad * 2 // empty ring
        }
        let perRow = dotsPerRow(maxWidth: maxWidth)
        let rowCount = (instanceCount + perRow - 1) / perRow
        return CGFloat(rowCount) * dotSize + CGFloat(max(0, rowCount - 1)) * rowSpacing + pillVPad * 2
    }

    static func makeRows(dots: [DotInfo], perRow: Int) -> [[DotInfo]] {
        var rows: [[DotInfo]] = []
        var i = 0
        while i < dots.count {
            let end = min(i + perRow, dots.count)
            rows.append(Array(dots[i..<end]))
            i = end
        }
        return rows
    }
}

struct DotInfo {
    let status: InstanceStatus
    let attentionColor: Color?
}

#Preview {
    VStack(spacing: 20) {
        CollapsedNotchView(instanceManager: InstanceManager(skipBootstrap: true), maxWidth: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding()
    .background(Color.gray)
}
