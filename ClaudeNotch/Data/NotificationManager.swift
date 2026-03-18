import Foundation
import Observation

@MainActor
@Observable
final class NotificationManager {
    private(set) var currentItem: NotificationItem?
    private(set) var queue: [NotificationItem] = []
    var queueCount: Int { queue.count }
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
        currentIndex = 0
        currentItem = items[0]
        lifecycleTask?.cancel()
        lifecycleTask = Task {
            let firstDisplayTime = queue.count > 1
                ? NotchTokens.Notification.rotationInterval
                : NotchTokens.Notification.dismissTimeout
            try? await Task.sleep(for: firstDisplayTime)

            // After sleep, queue may have been modified — use while loop for safe bounds checking
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

    func updateItems(_ items: [NotificationItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            if let idx = queue.firstIndex(where: { $0.instanceId == item.instanceId }) {
                queue[idx] = item
                if currentItem?.instanceId == item.instanceId {
                    currentItem = item
                }
            }
        }
    }

    func dismiss() {
        cleanup()
        onDismiss?()
    }

    func removeInstance(id: String) {
        queue.removeAll { $0.instanceId == id }

        if queue.isEmpty {
            dismiss()
            return
        }

        // Always clamp currentIndex after any removal
        currentIndex = min(currentIndex, queue.count - 1)
        currentItem = queue[currentIndex]
    }

    func cleanup() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        currentItem = nil
        queue = []
        currentIndex = 0
    }
}
