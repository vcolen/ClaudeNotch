import SwiftUI

// MARK: - Design Tokens

enum NotchTokens {
    enum Status {
        static let working = Color(red: 0.3, green: 0.85, blue: 0.4)
        static let waiting = Color(red: 1.0, green: 0.8, blue: 0.2)
        static let idle = Color.white.opacity(0.4)
        static let attention = Color(red: 1.0, green: 0.6, blue: 0.15)
    }

    enum Branch {
        static let separator = Color.white.opacity(0.25)
        static let name = Color.white.opacity(0.45)
    }

    enum Surface {
        static let cardBackground = Color.white.opacity(0.06)
        static let cardHover = Color.white.opacity(0.12)
        static let separator = Color.white.opacity(0.1)
        static let edgeHighlight = Color.white.opacity(0.15)
    }

    enum Size {
        static let cardCornerRadius: CGFloat = 10
        static let contextBarHeight: CGFloat = 3.5
        static let expandedCornerRadius: CGFloat = 16
        static let collapsedCornerRadius: CGFloat = 8
    }

    enum ProjectGroup {
        static let containerBackground = Color.white.opacity(0.03)
        static let containerCornerRadius: CGFloat = 8
        static let headerFont = Font.system(size: 12, weight: .semibold)
        static let countBadgeFont = Font.system(size: 9, design: .monospaced)
        static let countBadgeColor = Color.white.opacity(0.3)
    }

    enum BranchRow {
        static let branchFont = Font.system(size: 11, weight: .regular)
        static let metaFont = Font.system(size: 10)
        static let verticalPadding: CGFloat = 4
        static let contextBarHeight: CGFloat = 2.5
    }

    enum Notification {
        static let bannerHeight: CGFloat = 48
        static let cornerRadius: CGFloat = 12
        static let dismissTimeout: Duration = .seconds(5)
        static let rotationInterval: Duration = .seconds(4)
        static let swapAnimation = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.82)
        static let debounceDelay: Duration = .milliseconds(500)
    }

    enum Animation {
        static let expandSpring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.78)
        static let hoverQuick = SwiftUI.Animation.easeOut(duration: 0.12)
        static let contentReveal = SwiftUI.Animation.easeOut(duration: 0.25)
        static let frameDuration: Double = 0.4
        static let dismissDelay: Duration = .milliseconds(300)

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

// MARK: - ClaudeInstance Display Color

extension ClaudeInstance {
    var displayColor: Color {
        needsAttention ? NotchTokens.Status.attention : status.color
    }
}
