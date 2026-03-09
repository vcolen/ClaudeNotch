import SwiftUI

struct StatusDot: View {
    let status: InstanceStatus
    var isVisible: Bool = true

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 7, height: 7)
            .shadow(color: status == .working ? status.color.opacity(0.5) : .clear, radius: 3)
            .shadow(color: status == .waitingInput ? status.color.opacity(0.25) : .clear, radius: 2)
            .scaleEffect(isPulsing && status == .working && isVisible ? 1.12 : 1.0)
            .opacity(isPulsing && status == .working && isVisible ? 0.85 : 1.0)
            .animation(
                status == .working && isVisible
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if status == .working && isVisible {
                    isPulsing = true
                }
            }
            .onChange(of: status) { _, newValue in
                isPulsing = newValue == .working && isVisible
            }
            .onChange(of: isVisible) { _, visible in
                isPulsing = status == .working && visible
            }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(status: .working)
        StatusDot(status: .waitingInput)
        StatusDot(status: .idle)
    }
    .padding()
    .background(Color.black)
}
