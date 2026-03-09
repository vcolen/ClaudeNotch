import AppKit
import Observation

@Observable
final class PanelState {
    var isExpanded = false
    var contentHeight: CGFloat = 12 // overridden by controller on init
    var hasNotch: Bool
    var notchHeight: CGFloat
    var notchWidth: CGFloat

    init(hasNotch: Bool, notchHeight: CGFloat = 0, notchWidth: CGFloat = 220) {
        self.hasNotch = hasNotch
        self.notchHeight = notchHeight
        self.notchWidth = notchWidth
    }
}
