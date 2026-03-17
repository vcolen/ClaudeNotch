import Foundation
import Testing
@testable import ClaudeNotch

@MainActor
@Suite("NotificationManager Tests")
struct NotificationManagerTests {

    private func makeItem(id: String = "test-1", project: String = "proj") -> NotificationItem {
        NotificationItem(
            instanceId: id, projectName: project, branchName: "main",
            terminalIndex: 1, tty: "/dev/ttys001", pid: 100
        )
    }

    // MARK: - Show/Dismiss Lifecycle

    @Test("showNotifications sets currentItem and queue")
    func showSetsCurrentAndQueue() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        manager.showNotifications(items)
        #expect(manager.currentItem?.instanceId == "a")
        #expect(manager.queueCount == 2)
        #expect(manager.currentIndex == 0)
    }

    @Test("showNotifications with empty array dismisses")
    func showEmptyDismisses() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem()])
        manager.showNotifications([])
        #expect(manager.currentItem == nil)
        #expect(manager.queueCount == 0)
    }

    @Test("dismiss clears all state")
    func dismissClearsState() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem()])
        manager.dismiss()
        #expect(manager.currentItem == nil)
        #expect(manager.queue.isEmpty)
        #expect(manager.queueCount == 0)
        #expect(manager.currentIndex == 0)
    }

    @Test("dismiss calls onDismiss callback")
    func dismissCallsCallback() {
        let manager = NotificationManager()
        var dismissed = false
        manager.onDismiss = { dismissed = true }
        manager.showNotifications([makeItem()])
        manager.dismiss()
        #expect(dismissed)
    }

    // MARK: - Remove Instance

    @Test("removeInstance removes from queue")
    func removeInstanceRemovesFromQueue() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b"), makeItem(id: "c")]
        manager.showNotifications(items)
        manager.removeInstance(id: "b")
        #expect(manager.queueCount == 2)
        #expect(manager.queue.contains { $0.instanceId == "b" } == false)
    }

    @Test("removeInstance of current item advances to next")
    func removeCurrentAdvancesToNext() {
        let manager = NotificationManager()
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        manager.showNotifications(items)
        #expect(manager.currentItem?.instanceId == "a")
        manager.removeInstance(id: "a")
        #expect(manager.currentItem?.instanceId == "b")
    }

    @Test("removeInstance of last item dismisses")
    func removeLastDismisses() {
        let manager = NotificationManager()
        var dismissed = false
        manager.onDismiss = { dismissed = true }
        manager.showNotifications([makeItem(id: "only")])
        manager.removeInstance(id: "only")
        #expect(manager.currentItem == nil)
        #expect(dismissed)
    }

    @Test("removeInstance with nonexistent ID is safe")
    func removeNonexistentIsSafe() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem(id: "a")])
        manager.removeInstance(id: "nonexistent")
        #expect(manager.currentItem?.instanceId == "a")
        #expect(manager.queueCount == 1)
    }

    // MARK: - Cleanup

    @Test("cleanup resets all state without calling onDismiss")
    func cleanupResetsWithoutCallback() {
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
    func showReplacesExisting() {
        let manager = NotificationManager()
        manager.showNotifications([makeItem(id: "old")])
        #expect(manager.currentItem?.instanceId == "old")
        manager.showNotifications([makeItem(id: "new1"), makeItem(id: "new2")])
        #expect(manager.currentItem?.instanceId == "new1")
        #expect(manager.queueCount == 2)
    }
}

@MainActor
@Suite("PanelState Tests")
struct PanelStateTests {

    @Test("Initial mode is collapsed")
    func initialModeCollapsed() {
        let state = PanelState(hasNotch: true, notchHeight: 37)
        #expect(state.mode == .collapsed)
        #expect(state.isExpanded == false)
        #expect(state.isNotification == false)
    }

    @Test("isExpanded getter returns true only for expanded mode")
    func isExpandedGetter() {
        let state = PanelState(hasNotch: true)
        state.mode = .collapsed
        #expect(state.isExpanded == false)
        state.mode = .notification
        #expect(state.isExpanded == false)
        state.mode = .expanded
        #expect(state.isExpanded == true)
    }

    @Test("isExpanded setter maps true to expanded, false to collapsed")
    func isExpandedSetter() {
        let state = PanelState(hasNotch: true)
        state.isExpanded = true
        #expect(state.mode == .expanded)
        state.isExpanded = false
        #expect(state.mode == .collapsed)
    }

    @Test("isNotification returns true only for notification mode")
    func isNotificationGetter() {
        let state = PanelState(hasNotch: true)
        state.mode = .notification
        #expect(state.isNotification == true)
        state.mode = .collapsed
        #expect(state.isNotification == false)
    }

    @Test("Mode transitions: collapsed -> notification -> collapsed")
    func collapsedNotificationCollapsed() {
        let state = PanelState(hasNotch: true)
        #expect(state.mode == .collapsed)
        state.mode = .notification
        #expect(state.mode == .notification)
        state.mode = .collapsed
        #expect(state.mode == .collapsed)
    }

    @Test("Mode transitions: collapsed -> notification -> expanded -> collapsed")
    func fullTransitionCycle() {
        let state = PanelState(hasNotch: true)
        state.mode = .notification
        #expect(state.isNotification)
        state.mode = .expanded
        #expect(state.isExpanded)
        state.mode = .collapsed
        #expect(!state.isExpanded && !state.isNotification)
    }

    @Test("Setting isExpanded from notification mode goes to expanded")
    func isExpandedFromNotification() {
        let state = PanelState(hasNotch: true)
        state.mode = .notification
        state.isExpanded = true
        #expect(state.mode == .expanded)
    }
}
