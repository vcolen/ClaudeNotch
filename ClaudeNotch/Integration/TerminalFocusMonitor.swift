import AppKit
import Foundation

@MainActor
final class TerminalFocusMonitor {
    private let instanceManager: InstanceManager
    private var pollTask: Task<Void, Never>?
    private var isITermFocused = false

    init(instanceManager: InstanceManager) {
        self.instanceManager = instanceManager
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        // Check if iTerm is already frontmost
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier == "com.googlecode.iterm2" {
            isITermFocused = true
            startPolling()
        }
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopPolling()
    }

    // MARK: - App Activation Observers

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.googlecode.iterm2" else { return }
        isITermFocused = true
        startPolling()
    }

    @objc private func appDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.googlecode.iterm2" else { return }
        isITermFocused = false
        stopPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await self?.checkActiveSession()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkActiveSession() {
        guard isITermFocused else { return }

        let attentionInstances = instanceManager.needsAttentionInstances
        guard !attentionInstances.isEmpty else { return }

        // Get active TTY off the main thread via AppleScript
        guard let activeTTY = ITermIntegration.activeSessionTTY() else { return }

        for instance in attentionInstances {
            let instanceTTY: String?
            if let tty = instance.tty {
                instanceTTY = tty
            } else {
                instanceTTY = ITermIntegration.lookupTTY(forPID: instance.pid)
            }

            if let iTTY = instanceTTY, iTTY == activeTTY {
                instanceManager.clearAttention(for: instance.id)
            }
        }
    }
}
