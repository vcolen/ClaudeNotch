import Foundation
import Observation

@MainActor
@Observable
final class NotificationManager {
    private(set) var currentItem: NotificationItem?
    private(set) var queue: [NotificationItem] = []
    private(set) var queueCount: Int = 0
    private(set) var currentIndex: Int = 0

    private var lifecycleTask: Task<Void, Never>?

    var onDismiss: (() -> Void)?
    var onTap: ((NotificationItem) -> Void)?

    func showNotifications(_ items: [NotificationItem]) {
        guard !items.isEmpty else {
            dismiss()
            return
        }
        queue = items
        queueCount = items.count
        currentIndex = 0
        currentItem = items[0]
        lifecycleTask?.cancel()
        lifecycleTask = Task {
            let firstDisplayTime = queue.count > 1
                ? NotchTokens.Notification.rotationInterval
                : NotchTokens.Notification.dismissTimeout
            try? await Task.sleep(for: firstDisplayTime)

            // After sleep, queue may have been modified — check bounds
            var nextIndex = 1
            while nextIndex < queue.count {
                guard !Task.isCancelled else { return }
                currentIndex = nextIndex
                currentItem = queue[nextIndex]
                try? await Task.sleep(for: NotchTokens.Notification.rotationInterval)
                nextIndex += 1
            }
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        currentItem = nil
        queue = []
        queueCount = 0
        currentIndex = 0
        onDismiss?()
    }

    func removeInstance(id: String) {
        queue.removeAll { $0.instanceId == id }
        queueCount = queue.count
        if currentItem?.instanceId == id {
            if queue.isEmpty {
                dismiss()
                return
            }
            let nextIndex = min(currentIndex, queue.count - 1)
            currentIndex = nextIndex
            currentItem = queue[nextIndex]
        }
        if queue.isEmpty {
            dismiss()
        }
    }

    func cleanup() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        currentItem = nil
        queue = []
        queueCount = 0
        currentIndex = 0
    }
}
