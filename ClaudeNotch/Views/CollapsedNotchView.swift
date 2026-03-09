import SwiftUI

struct CollapsedNotchView: View {
    let instanceManager: InstanceManager

    var body: some View {
        HStack(spacing: 5) {
            if instanceManager.instances.isEmpty {
                // Gradient-stroked ring for empty state
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
            } else {
                let dots = statusDots
                let visible = dots.prefix(5)
                let overflow = dots.count - 5

                ForEach(Array(visible.enumerated()), id: \.offset) { _, status in
                    StatusDot(status: status, isVisible: true)
                }

                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 30)
    }

    private var statusDots: [InstanceStatus] {
        let sorted = instanceManager.sortedInstances
        let working = sorted.filter { $0.status == .working }.map(\.status)
        let waiting = sorted.filter { $0.status == .waitingInput }.map(\.status)
        let idle = sorted.filter { $0.status == .idle }.map(\.status)
        return working + waiting + idle
    }
}

#Preview {
    VStack(spacing: 20) {
        CollapsedNotchView(instanceManager: InstanceManager())
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding()
}
