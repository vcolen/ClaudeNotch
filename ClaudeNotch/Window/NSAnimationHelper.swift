import AppKit

enum NSAnimationHelper {
    /// Runs an AppKit animation block, respecting the system reduce-motion preference.
    /// When reduce motion is enabled, duration is set to 0 for instant transitions.
    static func animate(
        duration: Double,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        allowsImplicitAnimation: Bool = false,
        body: (NSAnimationContext) -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = allowsImplicitAnimation
            body(context)
        }
    }

    /// Async variant for use in Task contexts.
    static func animate(
        duration: Double,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        body: @Sendable @escaping (NSAnimationContext) -> Void
    ) async {
        await NSAnimationContext.runAnimationGroup { context in
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = timingFunction
            body(context)
        }
    }
}
