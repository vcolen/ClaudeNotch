import AppKit
import Foundation

@MainActor
final class TerminalFocusMonitor {
    private static let iTermBundleId = "com.googlecode.iterm2"

    private let instanceManager: InstanceManager
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?
    private var isITermFocused = false
    private var isStarted = false

    init(instanceManager: InstanceManager) {
        self.instanceManager = instanceManager
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollTask?.cancel()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

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
           frontApp.bundleIdentifier == Self.iTermBundleId {
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
              app.bundleIdentifier == Self.iTermBundleId else { return }
        isITermFocused = true
        startPolling()
    }

    @objc private func appDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.iTermBundleId else { return }
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

    private func checkActiveSession() async {
        guard isITermFocused, ITermIntegration.isITermRunning() else {
            if isITermFocused {
                isITermFocused = false
                stopPolling()
            }
            return
        }

        let attentionInstances = instanceManager.needsAttentionInstances
        guard !attentionInstances.isEmpty else { return }

        let instanceData = attentionInstances.map { (id: $0.id, tty: $0.tty, pid: $0.pid) }

        // Query iTerm for the TTY of its currently active session off the main thread
        let matchedIds = await Task.detached {
            guard let activeTTY = ITermIntegration.activeSessionTTY() else { return [String]() }
            var matched: [String] = []
            for inst in instanceData {
                let instanceTTY = inst.tty ?? ITermIntegration.lookupTTY(forPID: inst.pid)
                if let iTTY = instanceTTY, iTTY == activeTTY {
                    matched.append(inst.id)
                }
            }
            return matched
        }.value

        for id in matchedIds {
            instanceManager.clearAttention(for: id)
        }
    }
}
