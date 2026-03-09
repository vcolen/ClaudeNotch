import SwiftUI

// MARK: - Design Tokens

enum NotchTokens {
    enum Status {
        static let working = Color(red: 0.3, green: 0.85, blue: 0.4)
        static let waiting = Color(red: 1.0, green: 0.8, blue: 0.2)
        static let idle = Color.white.opacity(0.4)
    }

    enum Surface {
        static let cardBackground = Color.white.opacity(0.06)
        static let cardHover = Color.white.opacity(0.12)
        static let separator = Color.white.opacity(0.1)
        static let edgeHighlight = Color.white.opacity(0.15)
    }

    enum Size {
        static let collapsedHeight: CGFloat = 14
        static let cardCornerRadius: CGFloat = 10
        static let contextBarHeight: CGFloat = 3.5
    }

    enum Animation {
        static let expandSpring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.78)
        static let hoverQuick = SwiftUI.Animation.easeOut(duration: 0.12)
        static let contentReveal = SwiftUI.Animation.easeOut(duration: 0.25)

        /// Returns a stagger delay for the given index, capping total stagger at 250ms.
        static func staggerDelay(index: Int, total: Int) -> Double {
            guard total > 1 else { return 0 }
            let maxStagger = 0.25
            let interval = maxStagger / Double(total)
            return Double(index) * interval
        }
    }
}

// MARK: - InstanceStatus Color Extension

extension InstanceStatus {
    var color: Color {
        switch self {
        case .working: return NotchTokens.Status.working
        case .waitingInput: return NotchTokens.Status.waiting
        case .idle: return NotchTokens.Status.idle
        }
    }
}
