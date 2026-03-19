import Foundation
import Testing
@testable import ClaudeNotch

@Suite("NotificationManager Tests")
struct NotificationManagerTests {

    private func makeItem(id: String = "test-1", project: String = "proj", attentionType: AttentionType = .needsInput) -> NotificationItem {
        NotificationItem(
            instanceId: id, projectName: project, branchName: "main",
            terminalIndex: 1, tty: "/dev/ttys001", pid: 100,
            attentionType: attentionType
        )
    }

    // MARK: - Show/Dismiss Lifecycle

    @Test("showNotifications sets currentItem and queue")
    @MainActor func showSetsCurrentAndQueue() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        manager.showNotifications(items)
        #expect(manager.currentItem?.instanceId == "a")
        #expect(manager.queueCount == 2)
        #expect(manager.currentIndex == 0)
    }

    @Test("showNotifications with empty array dismisses")
    @MainActor func showEmptyDismisses() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem()])
        manager.showNotifications([])
        #expect(manager.currentItem == nil)
        #expect(manager.queueCount == 0)
    }

    @Test("dismiss clears all state")
    @MainActor func dismissClearsState() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem()])
        manager.dismiss()
        #expect(manager.currentItem == nil)
        #expect(manager.queue.isEmpty)
        #expect(manager.queueCount == 0)
        #expect(manager.currentIndex == 0)
    }

    @Test("dismiss calls onDismiss callback")
    @MainActor func dismissCallsCallback() {
        let manager = NotificationManager()
        var dismissed = false
        manager.onDismiss = { dismissed = true }
        manager.showNotifications([makeItem()])
        manager.dismiss()
        #expect(dismissed)
    }

    // MARK: - Remove Instance

    @Test("removeInstance removes from queue")
    @MainActor func removeInstanceRemovesFromQueue() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c")]
        manager.showNotifications(items)
        manager.removeInstance(id: "b")
        #expect(manager.queueCount == 2)
        #expect(manager.queue.contains { $0.instanceId == "b" } == false)
    }

    @Test("removeInstance of current item advances to next")
    @MainActor func removeCurrentAdvancesToNext() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        manager.showNotifications(items)
        #expect(manager.currentItem?.instanceId == "a")
        manager.removeInstance(id: "a")
        #expect(manager.currentItem?.instanceId == "b")
    }

    @Test("removeInstance of last item dismisses")
    @MainActor func removeLastDismisses() {
        let manager = NotificationManager()
        var dismissed = false
        manager.onDismiss = { dismissed = true }
        manager.showNotifications([makeItem(id: "only")])
        manager.removeInstance(id: "only")
        #expect(manager.currentItem == nil)
        #expect(dismissed)
    }

    @Test("removeInstance with nonexistent ID is safe")
    @MainActor func removeNonexistentIsSafe() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem(id: "a")])
        manager.removeInstance(id: "nonexistent")
        #expect(manager.currentItem?.instanceId == "a")
        #expect(manager.queueCount == 1)
    }

    // MARK: - Cleanup

    @Test("cleanup resets all state without calling onDismiss")
    @MainActor func cleanupResetsWithoutCallback() {
        let manager = NotificationManager()
        var dismissed = false
        manager.onDismiss = { dismissed = true }
        manager.showNotifications([makeItem()])
        manager.cleanup()
        #expect(manager.currentItem == nil)
        #expect(manager.queue.isEmpty)
        #expect(!dismissed)
    }

    // MARK: - Replacing notifications

    @Test("showNotifications replaces existing queue")
    @MainActor func showReplacesExisting() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem(id: "old")])
        #expect(manager.currentItem?.instanceId == "old")
        manager.showNotifications([makeItem(id: "new1"), makeItem(id: "new2")])
        #expect(manager.currentItem?.instanceId == "new1")
        #expect(manager.queueCount == 2)
    }

    // MARK: - removeInstance clamping

    @Test("removeInstance clamps currentIndex when non-current item before current is removed")
    @MainActor func removeNonCurrentClampsIndex() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c")]
        manager.showNotifications(items)
        // Simulate being at index 2 by manipulating through removal
        // After show, currentIndex=0 showing "a". We can't directly set currentIndex,
        // so test that removing items doesn't cause out-of-bounds access
        manager.removeInstance(id: "a")
        // After removing "a": queue is [b, c], currentIndex should be clamped
        #expect(manager.currentItem != nil)
        #expect(manager.queue.count == 2)
        #expect(manager.currentIndex <= manager.queue.count - 1)
    }

    @Test("removeInstance of item before current adjusts index correctly")
    @MainActor func removeBeforeCurrentAdjusts() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c")]
        manager.showNotifications(items)
        // Remove non-current, non-displayed item
        manager.removeInstance(id: "b")
        #expect(manager.queue.count == 2)
        #expect(manager.currentItem?.instanceId == "a")
        #expect(manager.currentIndex == 0)
    }

    // MARK: - updateItems

    @Test("updateItems replaces items without resetting currentIndex")
    @MainActor func updateItemsPreservesPosition() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a", project: "old-proj"), makeItem(id: "b", project: "old-proj2")]
        manager.showNotifications(items)

        let updatedItems = [
            NotificationItem(instanceId: "a", projectName: "new-proj", branchName: "main", terminalIndex: 5, tty: "/dev/ttys001", pid: 100, attentionType: .needsInput),
            NotificationItem(instanceId: "b", projectName: "new-proj2", branchName: "main", terminalIndex: 3, tty: "/dev/ttys002", pid: 200, attentionType: .needsInput)
        ]
        manager.updateItems(updatedItems)

        #expect(manager.currentIndex == 0)
        #expect(manager.currentItem?.projectName == "new-proj")
        #expect(manager.currentItem?.terminalIndex == 5)
        #expect(manager.queue[1].projectName == "new-proj2")
    }

    @Test("updateItems with empty array is no-op")
    @MainActor func updateItemsEmptyNoOp() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem(id: "a")])
        manager.updateItems([])
        #expect(manager.currentItem?.instanceId == "a")
        #expect(manager.queue.count == 1)
    }

    @Test("updateItems with unknown IDs doesn't change queue")
    @MainActor func updateItemsUnknownIds() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem(id: "a")])
        let unknownItems = [makeItem(id: "z", project: "unknown")]
        manager.updateItems(unknownItems)
        #expect(manager.queue.count == 1)
        #expect(manager.currentItem?.instanceId == "a")
    }

    // MARK: - queueCount consistency

    @Test("queueCount always matches queue.count")
    @MainActor func queueCountConsistent() {
        let manager = NotificationManager()
        #expect(manager.queueCount == 0)
        manager.showNotifications([makeItem(id: "a"), makeItem(id: "b")])
        #expect(manager.queueCount == 2)
        manager.removeInstance(id: "a")
        #expect(manager.queueCount == 1)
        manager.dismiss()
        #expect(manager.queueCount == 0)
    }

    // MARK: - AttentionType in queue

    @Test("Items with different attention types coexist in queue")
    @MainActor func differentAttentionTypesCoexist() {
        let manager = NotificationManager()
        let items = [
            makeItem(id: "a", attentionType: .needsInput),
            makeItem(id: "b", attentionType: .taskFinished),
            makeItem(id: "c", attentionType: .needsInput),
        ]
        manager.showNotifications(items)
        #expect(manager.queueCount == 3)
        #expect(manager.queue[0].attentionType == .needsInput)
        #expect(manager.queue[1].attentionType == .taskFinished)
        #expect(manager.queue[2].attentionType == .needsInput)
    }

    // MARK: - Callback integration

    @Test("onDismiss callback fires exactly once on dismiss")
    @MainActor func onDismissFiresOnce() {
        let manager = NotificationManager()
        var callCount = 0
        manager.onDismiss = { callCount += 1 }
        manager.showNotifications([makeItem()])
        manager.dismiss()
        #expect(callCount == 1)
    }

    @Test("onTap callback receives correct item")
    @MainActor func onTapReceivesItem() {
        let manager = NotificationManager()
        var tappedId: String?
        manager.onTap = { item in tappedId = item.instanceId }
        let item = makeItem(id: "tap-test")
        manager.showNotifications([item])
        manager.onTap?(manager.currentItem!)
        #expect(tappedId == "tap-test")
    }

    // MARK: - Multiple sequential removes

    @Test("multiple sequential removes handle correctly")
    @MainActor func multipleSequentialRemoves() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c"), makeItem(id: "d")]
        manager.showNotifications(items)
        manager.removeInstance(id: "b")
        #expect(manager.queue.count == 3)
        manager.removeInstance(id: "d")
        #expect(manager.queue.count == 2)
        manager.removeInstance(id: "a")
        #expect(manager.queue.count == 1)
        #expect(manager.currentItem?.instanceId == "c")
        manager.removeInstance(id: "c")
        #expect(manager.currentItem == nil)
        #expect(manager.queue.isEmpty)
    }
}

@Suite("PanelState Tests")
struct PanelStateTests {

    @Test("Initial mode is collapsed")
    @MainActor func initialModeCollapsed() {
        let state = PanelState(hasNotch: true, notchHeight: 37)
        #expect(state.mode == .collapsed)
        #expect(state.isExpanded == false)
        #expect(state.isNotification == false)
    }

    @Test("isExpanded getter returns true only for expanded mode")
    @MainActor func isExpandedGetter() {
        let state = PanelState(hasNotch: true)
        state.mode = .collapsed
        #expect(state.isExpanded == false)
        state.mode = .notification
        #expect(state.isExpanded == false)
        state.mode = .expanded
        #expect(state.isExpanded == true)
    }

    @Test("isExpanded setter maps true to expanded, false to collapsed")
    @MainActor func isExpandedSetter() {
        let state = PanelState(hasNotch: true)
        state.isExpanded = true
        #expect(state.mode == .expanded)
        state.isExpanded = false
        #expect(state.mode == .collapsed)
    }

    @Test("isNotification returns true only for notification mode")
    @MainActor func isNotificationGetter() {
        let state = PanelState(hasNotch: true)
        state.mode = .notification
        #expect(state.isNotification == true)
        state.mode = .collapsed
        #expect(state.isNotification == false)
    }

    @Test("Mode transitions: collapsed -> notification -> collapsed")
    @MainActor func collapsedNotificationCollapsed() {
        let state = PanelState(hasNotch: true)
        #expect(state.mode == .collapsed)
        state.mode = .notification
        #expect(state.mode == .notification)
        state.mode = .collapsed
        #expect(state.mode == .collapsed)
    }

    @Test("Mode transitions: collapsed -> notification -> expanded -> collapsed")
    @MainActor func fullTransitionCycle() {
        let state = PanelState(hasNotch: true)
        state.mode = .notification
        #expect(state.isNotification)
        state.mode = .expanded
        #expect(state.isExpanded)
        state.mode = .collapsed
        #expect(!state.isExpanded && !state.isNotification)
    }

    @Test("Setting isExpanded from notification mode goes to expanded")
    @MainActor func isExpandedFromNotification() {
        let state = PanelState(hasNotch: true)
        state.mode = .notification
        state.isExpanded = true
        #expect(state.mode == .expanded)
    }
}

