import AppKit

@MainActor
final class ScreenObserver {
    private var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    private let instanceManager: InstanceManager
    private var syncTask: Task<Void, Never>?

    init(instanceManager: InstanceManager) {
        self.instanceManager = instanceManager
    }

    func setup() {
        syncScreens()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func tearDown() {
        syncTask?.cancel()
        syncTask = nil

        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        for controller in controllers.values {
            controller.tearDown()
        }
        controllers.removeAll()
    }

    @objc private func screensDidChange(_ notification: Notification) {
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.syncScreens()
        }
    }

    private func syncScreens() {
        let currentScreens = NSScreen.screens
        var currentDisplayIDs: Set<CGDirectDisplayID> = []

        // Create controllers for new screens
        for screen in currentScreens {
            guard let displayID = displayID(for: screen) else { continue }
            currentDisplayIDs.insert(displayID)

            if let existing = controllers[displayID] {
                existing.updateScreen(screen)
            } else {
                let controller = NotchPanelController(screen: screen, instanceManager: instanceManager)
                controllers[displayID] = controller
            }
        }

        // Remove controllers for disconnected screens
        let disconnectedIDs = Set(controllers.keys).subtracting(currentDisplayIDs)
        for displayID in disconnectedIDs {
            controllers[displayID]?.tearDown()
            controllers.removeValue(forKey: displayID)
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        #if DEBUG
        if id == nil {
            print("[ScreenObserver] Failed to get displayID for screen: \(screen.localizedName)")
        }
        #endif
        return id
    }
}
