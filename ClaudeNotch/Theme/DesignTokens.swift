import SwiftUI

// MARK: - Design Tokens

enum NotchTokens {
    enum Status {
        static let working = Color(red: 0.3, green: 0.85, blue: 0.4)
        static let waiting = Color(red: 1.0, green: 0.8, blue: 0.2)
        static let idle = Color.white.opacity(0.4)
        static let needsInput = Color(red: 1.0, green: 0.6, blue: 0.15)
        static let taskFinished = Color(red: 0.4, green: 0.7, blue: 1.0)
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
        static let defaultCollapsedWidth: CGFloat = 220
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
        static let cornerRadius: CGFloat = bannerHeight / 2  // pill shape, auto-adapts if height changes
        static let shadowPadding: CGFloat = 8  // room for the banner's drop shadow below the pill
        static let topMargin: CGFloat = 8  // vertical gap above the banner pill (below notch on notch screens, from screen top otherwise)
        static let dismissTimeout: Duration = .seconds(5)
        static let rotationInterval: Duration = .seconds(4)
        static let swapAnimation = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.82)
        static let debounceDelay: Duration = .seconds(1)
    }

    enum Animation {
        static let expandSpring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.78)
        static let hoverQuick = SwiftUI.Animation.easeOut(duration: 0.12)
        static let contentReveal = SwiftUI.Animation.easeOut(duration: 0.25)
        static let frameDuration: Double = 0.4
        static let dismissDelay: Duration = .milliseconds(300)
        static let revealOffset: CGFloat = -6

        static let selectionFlashDuration: Double = 0.6
        static let selectionFadeIn: Double = 0.25
        static let selectionFadeOut: Double = 0.5

        static let workingPulseDuration: Double = 1.1
        static let attentionPulseDuration: Double = 1.5  // Must be > workingPulseDuration for visual hierarchy

        // Water drop selection animation
        static let waterDropFlightDur: Double = 0.65
        static let waterDropImpactDur: Double = 0.08
        static let waterDropRaceDur: Double = 0.60
        static let waterDropMergeDur: Double = 0.12
        static let waterDropReturnDur: Double = 0.50
        static let waterDropStreamThickness: CGFloat = 6
        static let waterDropStreamLength: CGFloat = 0.10
        static let waterDropDotRadius: CGFloat = 5
        static let terminalCornerRadius: CGFloat = 10

        /// Returns a stagger delay for the given index. The total spread across all items is distributed within 250ms.
        static func staggerDelay(index: Int, total: Int) -> Double {
            guard total > 1, index >= 0 else { return 0 }
            let maxStagger = 0.25
            let interval = maxStagger / Double(total)
            return Double(min(index, total - 1)) * interval
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

// MARK: - AttentionType Presentation

extension AttentionType {
    var color: Color {
        switch self {
        case .needsInput:  return NotchTokens.Status.needsInput
        case .taskFinished: return NotchTokens.Status.taskFinished
        }
    }

    var displayName: String {
        switch self {
        case .needsInput:  return "Needs Input"
        case .taskFinished: return "Finished"
        }
    }

    var bannerTitle: String {
        switch self {
        case .needsInput:  return "Claude needs input"
        case .taskFinished: return "Claude finished task"
        }
    }
}

// MARK: - ClaudeInstance Display Color

extension ClaudeInstance {
    var displayColor: Color {
        if let attentionType { return attentionType.color }
        return status.color
    }
}
