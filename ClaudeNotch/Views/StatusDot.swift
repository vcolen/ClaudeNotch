import SwiftUI

struct StatusDot: View {
    let status: InstanceStatus
    var isVisible: Bool = true
    var attentionType: AttentionType? = nil

    @State private var isPulsing = false
    @State private var attentionPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAttention: Bool { attentionType != nil }
    private var attentionColor: Color? { attentionType?.color }

    private var shouldWorkingPulse: Bool {
        status == .working && isVisible && !isAttention
    }

    private var primaryShadowColor: Color {
        if let color = attentionColor { return color.opacity(0.5) }
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

    private func updatePulseState(isAttention: Bool) {
        attentionPulse = isAttention && !reduceMotion
        isPulsing = status == .working && isVisible && !isAttention && !reduceMotion
    }

    var body: some View {
        Circle()
            .fill(attentionColor ?? status.color)
            .frame(width: 7, height: 7)
            .shadow(color: primaryShadowColor, radius: 3)
            .shadow(color: secondaryShadowColor, radius: 2)
            .scaleEffect(isPulsing && shouldWorkingPulse ? 1.12 : 1.0)
            .opacity(dotOpacity)
            .transaction { $0.animation = nil }
            .animation(
                shouldWorkingPulse && !reduceMotion
                    ? .easeInOut(duration: NotchTokens.Animation.workingPulseDuration).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .animation(
                isAttention && !reduceMotion
                    ? .easeInOut(duration: NotchTokens.Animation.attentionPulseDuration).repeatForever(autoreverses: true)
                    : .default,
                value: attentionPulse
            )
            .onAppear {
                if shouldWorkingPulse && !reduceMotion {
                    isPulsing = true
                }
                if isAttention && !reduceMotion {
                    attentionPulse = true
                }
            }
            .onChange(of: status) { _, _ in
                updatePulseState(isAttention: isAttention)
            }
            .onChange(of: isVisible) { _, _ in
                updatePulseState(isAttention: isAttention)
            }
            .onChange(of: attentionType) { _, newType in
                updatePulseState(isAttention: newType != nil)
            }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(status: .working)
        StatusDot(status: .waitingInput)
        StatusDot(status: .idle)
        StatusDot(status: .waitingInput, attentionType: .needsInput)
        StatusDot(status: .idle, attentionType: .taskFinished)
    }
    .padding()
    .background(Color.black)
}
