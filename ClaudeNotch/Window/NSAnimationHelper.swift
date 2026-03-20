import AppKit

@MainActor
enum NSAnimationHelper {
    /// Runs an AppKit animation block, respecting the system reduce-motion preference.
    /// When reduce motion is enabled, duration is set to 0 for instant transitions.
    static func animate(
        duration: Double,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        allowsImplicitAnimation: Bool = false,
        body: () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = allowsImplicitAnimation
            body()
        }
    }

    /// Async variant for use in Task contexts.
    /// Respects the system reduce-motion preference (same as the synchronous overload).
    static func animate(
        duration: Double,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
        allowsImplicitAnimation: Bool = false,
        body: @Sendable @escaping () -> Void
    ) async {
        await NSAnimationContext.runAnimationGroup { context in
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = allowsImplicitAnimation
            body()
        }
    }
}
