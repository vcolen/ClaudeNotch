import SwiftUI

struct ContextUsageBar: View {
    let percent: Double?

    var body: some View {
        if let percent {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.06))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [barColor(for: percent).opacity(0.7), barColor(for: percent)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, geometry.size.width * CGFloat(percent)))
                }
            }
            .frame(height: NotchTokens.Size.contextBarHeight)
        }
    }

    private func barColor(for percent: Double) -> Color {
        if percent < 0.5 {
            return NotchTokens.Status.working
        } else if percent < 0.8 {
            return NotchTokens.Status.waiting
        } else {
            return Color(red: 0.95, green: 0.3, blue: 0.3)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ContextUsageBar(percent: 0.2)
        ContextUsageBar(percent: 0.6)
        ContextUsageBar(percent: 0.85)
        ContextUsageBar(percent: 1.0)
        ContextUsageBar(percent: nil)
    }
    .frame(width: 200)
    .padding()
    .background(Color.black)
}
