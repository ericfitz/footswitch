import AppKit
import FootswitchCore
import IOKit.hid

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var listener: PedalListener!
    private var dispatcher: ActionDispatcher!
    private var config = Config.default
    private let store = ConfigStore()
    private var settingsWindow: NSWindow?
    private var aboutWindowController: AboutWindowController?
    private var hidMonitorManager: IOHIDManager?
    private var rebuildWorkItem: DispatchWorkItem?

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

        buildListener()

        // Live hot-plug: when USB HID devices change, re-detect the pedal count
        // and rebuild the listener so a freshly-plugged multi-pedal unit starts
        // catching its extra pedals without a relaunch.
        startDeviceChangeObserver()
    }

    /// (Re)builds the event-tap listener from the current config's trigger keys,
    /// clamped to the number of pedals the connected USB device actually reports,
    /// so single-pedal users never have F14/F15 swallowed. Detection is expensive
    /// (~1.5s worst case) so it runs off-main; the listener is (re)installed back
    /// on the main thread.
    private func buildListener() {
        let allKeys = config.allTriggerKeys
        let debounceMs = config.debounceMs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let slotCount = FootswitchHIDController.detectedSlotCount()
            let clamped = allKeys.filter { $0.slot <= slotCount }
            let keys = clamped.isEmpty ? Array(allKeys.prefix(1)) : clamped
            DispatchQueue.main.async {
                guard let self else { return }
                // Tear down the previous tap before replacing it, or the old
                // listener keeps swallowing its keys (leak on hot-plug / save).
                self.listener?.stop()
                self.listener = PedalListener(
                    triggerKeys: keys,
                    debounceMs: debounceMs,
                    onFire: { [weak self] slot in
                        MainActor.assumeIsolated { self?.handlePress(slot: slot) }
                    })
                _ = self.listener.start()
            }
        }
    }

    private func handlePress(slot: Int) {
        let bundleID = FrontmostApp.bundleID()
        let action = RuleResolver.resolve(bundleID: bundleID, slot: slot, config: config)
        dispatcher.dispatch(action)
        menuBar.setLastFire(app: FrontmostApp.name(), slot: slot, action: action)
    }

    /// Observes USB HID attach/detach and rebuilds the listener (debounced 600ms
    /// so a burst of interface (un)registrations from one physical (un)plug only
    /// triggers one re-detect).
    private func startDeviceChangeObserver() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.scheduleListenerRebuild() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, cb, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, cb, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidMonitorManager = manager
    }

    private func scheduleListenerRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.buildListener() }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
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
        // Trigger keys / debounce changes take effect immediately by rebuilding
        // the listener (clamped to the detected slot count).
        buildListener()
    }
}
