import AppKit

@MainActor
final class ScreenObserver {
    private var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    private let instanceManager: InstanceManager
    private var syncWorkItem: DispatchWorkItem?

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
        syncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.syncScreens()
        }
        syncWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
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
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
