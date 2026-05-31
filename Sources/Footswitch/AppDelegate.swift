import AppKit
import FootswitchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var listener: PedalListener!
    private var dispatcher: ActionDispatcher!
    private var config = Config.default
    private let store = ConfigStore()
    private var settingsWindow: NSWindow?
    private var aboutWindowController: AboutWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = (try? store.load()) ?? .default

        dispatcher = ActionDispatcher(
            poster: LiveEventPoster(),
            dictationShortcut: config.dictationShortcut)

        menuBar = MenuBarController(
            openSettings: { [weak self] in self?.showSettings() },
            openAbout: { [weak self] in self?.showAbout() })

        if !PermissionsManager.isTrusted() {
            PermissionsManager.requestTrust()
        }

        listener = PedalListener(
            triggerKey: config.triggerKey,
            debounceMs: config.debounceMs,
            onFire: { [weak self] in
                MainActor.assumeIsolated { self?.handlePress() }
            })
        _ = listener.start()
    }

    private func handlePress() {
        let bundleID = FrontmostApp.bundleID()
        let action = RuleResolver.resolve(bundleID: bundleID, config: config)
        dispatcher.dispatch(action)
        menuBar.setLastFire(app: FrontmostApp.name(), action: action)
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowFactory.make(
                store: store,
                onSave: { [weak self] newConfig in self?.reload(newConfig) })
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reload(_ newConfig: Config) {
        config = newConfig
        try? store.save(newConfig)
        dispatcher = ActionDispatcher(
            poster: LiveEventPoster(),
            dictationShortcut: config.dictationShortcut)
        // triggerKey/debounce changes take effect on next launch (documented).
    }
}
