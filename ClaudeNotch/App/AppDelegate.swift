import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var instanceManager: InstanceManager!
    private var screenObserver: ScreenObserver!
    private var socketListener: SocketListener!
    private var statusItem: NSStatusItem!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        instanceManager = InstanceManager()
        screenObserver = ScreenObserver(instanceManager: instanceManager)
        screenObserver.setup()

        socketListener = SocketListener()
        socketListener.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.instanceManager.handleSocketEvent(event)
                // Track recent projects from socket events
                RecentProjectsStore.addProject(event.cwd)
            }
        }
        socketListener.start()

        setupStatusItem()
        installSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "terminal.fill",
                accessibilityDescription: "ClaudeNotch"
            )
        }

        let menu = NSMenu()

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit ClaudeNotch",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        cleanup()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Signal Handling

    private func installSignalHandlers() {
        let signalCallback: @convention(c) (Int32) -> Void = { _ in
            DispatchQueue.main.async {
                guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
                delegate.cleanup()
                exit(0)
            }
        }
        signal(SIGTERM, signalCallback)
        signal(SIGINT, signalCallback)
    }

    // MARK: - Cleanup

    private func cleanup() {
        socketListener?.stop()
        screenObserver?.tearDown()
        instanceManager?.cleanup()
    }
}
