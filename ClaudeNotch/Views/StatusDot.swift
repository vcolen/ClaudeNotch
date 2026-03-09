import SwiftUI

struct StatusDot: View {
    let status: InstanceStatus
    var isVisible: Bool = true
    var isAttention: Bool = false

    @State private var isPulsing = false
    @State private var attentionPulse = false

    private var shouldWorkingPulse: Bool {
        status == .working && isVisible && !isAttention
    }

    var body: some View {
        Circle()
            .fill(isAttention ? NotchTokens.Status.attention : status.color)
            .frame(width: 7, height: 7)
            .shadow(color: isAttention ? NotchTokens.Status.attention.opacity(0.5) : (status == .working ? status.color.opacity(0.5) : .clear), radius: 3)
            .shadow(color: !isAttention && status == .waitingInput ? status.color.opacity(0.25) : .clear, radius: 2)
            .scaleEffect(isPulsing && shouldWorkingPulse ? 1.12 : 1.0)
            .opacity(isAttention ? (attentionPulse ? 0.55 : 1.0) : (isPulsing && shouldWorkingPulse ? 0.85 : 1.0))
            .animation(
                shouldWorkingPulse
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .animation(
                isAttention
                    ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                    : .default,
                value: attentionPulse
            )
            .onAppear {
                if shouldWorkingPulse {
                    isPulsing = true
                }
                if isAttention {
                    attentionPulse = true
                }
            }
            .onChange(of: status) { _, newValue in
                isPulsing = newValue == .working && isVisible && !isAttention
            }
            .onChange(of: isVisible) { _, visible in
                isPulsing = status == .working && visible && !isAttention
            }
            .onChange(of: isAttention) { _, attention in
                attentionPulse = attention
                isPulsing = !attention && status == .working && isVisible
            }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(status: .working)
        StatusDot(status: .waitingInput)
        StatusDot(status: .idle)
        StatusDot(status: .waitingInput, isAttention: true)
    }
    .padding()
    .background(Color.black)
}
