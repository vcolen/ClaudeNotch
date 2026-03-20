import SwiftUI

// MARK: - Motion-aware Animation

func withMotionAnimation<Result>(
    _ animation: Animation?,
    reduceMotion: Bool,
    body: () throws -> Result
) rethrows -> Result {
    if reduceMotion {
        return try body()
    } else {
        return try withAnimation(animation) {
            try body()
        }
    }
}

// MARK: - HoverHighlight

struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let hoverColor: Color
    let idleColor: Color

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? hoverColor : idleColor)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withMotionAnimation(NotchTokens.Animation.hoverQuick, reduceMotion: reduceMotion) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverHighlight(
        cornerRadius: CGFloat = NotchTokens.Size.cardCornerRadius,
        hoverColor: Color = NotchTokens.Surface.cardHover,
        idleColor: Color = NotchTokens.Surface.cardBackground
    ) -> some View {
        modifier(HoverHighlight(
            cornerRadius: cornerRadius,
            hoverColor: hoverColor,
            idleColor: idleColor
        ))
    }
}

// MARK: - StaggerReveal

struct StaggerReveal: ViewModifier {
    let isRevealed: Bool
    let index: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed ? 0 : (reduceMotion ? 0 : NotchTokens.Animation.revealOffset))
            .animation(
                reduceMotion
                    ? .none
                    : NotchTokens.Animation.contentReveal
                        .delay(NotchTokens.Animation.staggerDelay(index: index, total: total)),
                value: isRevealed
            )
    }
}

extension View {
    func staggerReveal(isRevealed: Bool, index: Int, total: Int) -> some View {
        modifier(StaggerReveal(isRevealed: isRevealed, index: index, total: total))
    }
}
