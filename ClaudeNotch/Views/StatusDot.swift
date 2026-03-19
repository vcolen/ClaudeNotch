import SwiftUI

struct StatusDot: View {
    let status: InstanceStatus
    var isVisible: Bool = true
    var attentionColor: Color? = nil

    @State private var isPulsing = false
    @State private var attentionPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAttention: Bool { attentionColor != nil }

    private var shouldWorkingPulse: Bool {
        status == .working && isVisible && !isAttention
    }

    private var primaryShadowColor: Color {
        if isAttention { return attentionColor!.opacity(0.5) }
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
            .fill(isAttention ? attentionColor! : status.color)
            .frame(width: 7, height: 7)
            .shadow(color: primaryShadowColor, radius: 3)
            .shadow(color: secondaryShadowColor, radius: 2)
            .scaleEffect(isPulsing && shouldWorkingPulse ? 1.12 : 1.0)
            .opacity(dotOpacity)
            .transaction { $0.animation = nil }
            .animation(
                shouldWorkingPulse && !reduceMotion
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .animation(
                isAttention && !reduceMotion
                    ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
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
            .onChange(of: attentionColor) { _, newColor in
                updatePulseState(isAttention: newColor != nil)
            }
    }
}

#Preview {
    HStack(spacing: 12) {
        StatusDot(status: .working)
        StatusDot(status: .waitingInput)
        StatusDot(status: .idle)
        StatusDot(status: .waitingInput, attentionColor: NotchTokens.Status.needsInput)
        StatusDot(status: .idle, attentionColor: NotchTokens.Status.taskFinished)
    }
    .padding()
    .background(Color.black)
}
