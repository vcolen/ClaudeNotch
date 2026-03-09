import AppKit
import Observation

@Observable
final class PanelState {
    var isExpanded = false
    var contentHeight: CGFloat = NotchTokens.Size.collapsedHeight
    var hasNotch: Bool
    var notchHeight: CGFloat // safeAreaInsets.top value

    init(hasNotch: Bool, notchHeight: CGFloat = 0) {
        self.hasNotch = hasNotch
        self.notchHeight = notchHeight
    }
}
