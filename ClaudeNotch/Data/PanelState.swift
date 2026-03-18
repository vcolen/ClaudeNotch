import AppKit
import Observation

enum NotchMode: Equatable {
    case collapsed
    case notification
    case expanded
}

@Observable
final class PanelState {
    var mode: NotchMode = .collapsed
    var contentHeight: CGFloat = 12 // overridden by controller on init
    var hasNotch: Bool
    var notchHeight: CGFloat
    var notchWidth: CGFloat

    var isExpanded: Bool {
        get { mode == .expanded }
        set { mode = newValue ? .expanded : .collapsed }
    }

    var isNotification: Bool { mode == .notification }

    init(hasNotch: Bool, notchHeight: CGFloat = 0, notchWidth: CGFloat = NotchTokens.Size.defaultCollapsedWidth) {
        self.hasNotch = hasNotch
        self.notchHeight = notchHeight
        self.notchWidth = notchWidth
    }
}
