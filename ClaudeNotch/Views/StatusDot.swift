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

    private var primaryShadowColor: Color {
        if isAttention { return NotchTokens.Status.attention.opacity(0.5) }
        if status == .working { return status.color.opacity(0.5) }
        return .clear
    }

    private var secondaryShadowColor: Color {
        !isAttention && status == .waitingInput ? status.color.opacity(0.25) : .clear
    }

    private var dotOpacity: Double {
        if isAttention { return attentionPulse ? 0.55 : 1.0 }
        if isPulsing && shouldWorkingPulse { return 0.85 }
        return 1.0
    }

    private func updatePulseState(status: InstanceStatus, isVisible: Bool, isAttention: Bool) {
        attentionPulse = isAttention
        isPulsing = status == .working && isVisible && !isAttention
    }

    var body: some View {
        Circle()
            .fill(isAttention ? NotchTokens.Status.attention : status.color)
            .frame(width: 7, height: 7)
            .shadow(color: primaryShadowColor, radius: 3)
            .shadow(color: secondaryShadowColor, radius: 2)
            .scaleEffect(isPulsing && shouldWorkingPulse ? 1.12 : 1.0)
            .opacity(dotOpacity)
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
                updatePulseState(status: newValue, isVisible: isVisible, isAttention: isAttention)
            }
            .onChange(of: isVisible) { _, visible in
                updatePulseState(status: status, isVisible: visible, isAttention: isAttention)
            }
            .onChange(of: isAttention) { _, attention in
                updatePulseState(status: status, isVisible: isVisible, isAttention: attention)
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
