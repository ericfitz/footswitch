import AppKit
import FootswitchCore
import IOKit.hid

extension Notification.Name {
    /// Posted (debounced) when the set of connected foot switch devices changes —
    /// USB attach/detach and BLE connect/disconnect both surface through the IOKit
    /// HID device-change observer (a BLE HID keyboard is an IOHID device too). An
    /// open Settings window listens for this to refresh its device status.
    static let footswitchDeviceChanged = Notification.Name("footswitch.deviceChanged")
}

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
    private var isCapturing = false
    private var pendingRebuildAfterCapture = false
    private var captureTimeoutWork: DispatchWorkItem?
    /// True when dictation is reachable but the system's Dictation shortcut can't
    /// be synthesized (a double-press). Set by `effectiveDictationShortcut()`,
    /// surfaced as a menu-bar warning. (#15)
    private var dictationUnsupported = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = (try? store.load()) ?? .default
        // Make any user-supplied device-table entries visible to detection (#4/#9).
        FootswitchHIDController.registeredDevices = config.devices

        dispatcher = ActionDispatcher(
            poster: LiveEventPoster(),
            dictationShortcut: effectiveDictationShortcut(),
            shortcutRunner: ShortcutRunner())

        menuBar = MenuBarController(
            openSettings: { [weak self] in self?.showSettings() },
            openAbout: { [weak self] in self?.showAbout() })
        menuBar.setDictationUnsupported(dictationUnsupported)

        if !PermissionsManager.isTrusted() {
            PermissionsManager.requestTrust()
        }

        // Install a provisional single-slot (primary key) listener synchronously so
        // presses are caught immediately — backgrounded slot detection (~1.5s worst
        // case) would otherwise leave a startup gap where presses pass through. The
        // backgrounded probe then rebuilds with the full clamped key set.
        installListener(triggerKeys: Array(config.listenerKeys.prefix(1)))
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
        let allKeys = config.listenerKeys
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let slotCount = FootswitchHIDController.detectedSlotCount()
            let clamped = allKeys.filter { $0.slot <= slotCount }
            let keys = clamped.isEmpty ? Array(allKeys.prefix(1)) : clamped
            DispatchQueue.main.async { self?.installListener(triggerKeys: keys) }
        }
    }

    /// Installs a fresh event-tap listener for `triggerKeys`, tearing down the
    /// previous one first (or the old tap keeps swallowing its keys — a leak on
    /// hot-plug / save / the provisional→detected handoff). Main-thread only.
    private func installListener(triggerKeys: [TriggerKey]) {
        listener?.stop()
        listener = PedalListener(
            triggerKeys: triggerKeys,
            debounceMs: config.debounceMs,
            onFire: { [weak self] slot in
                MainActor.assumeIsolated { self?.handlePress(slot: slot) }
            })
        _ = listener.start()
    }

    private func handlePress(slot: Int) {
        let bundleID = FrontmostApp.bundleID()
        let action = RuleResolver.resolve(bundleID: bundleID, slot: slot, config: config)
        dispatcher.dispatch(action)
        menuBar.setLastFire(app: FrontmostApp.name(), slot: slot, action: action)
    }

    /// Arms the live listener to capture the next keydown for the Settings "Test"
    /// flow, with a timeout. `completion` runs on the main thread with the resolved
    /// `CapturedKey` (or `.none` on timeout). Listener rebuilds requested during
    /// capture are deferred so the capturing listener isn't swapped out mid-test.
    private func beginCapture(timeoutMs: Int, completion: @escaping @Sendable (CapturedKey) -> Void) {
        captureTimeoutWork?.cancel()
        isCapturing = true
        listener.beginCapture { [weak self] keyCode, modBits in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.isCapturing else { return }
                self.finishCapture()
                completion(CapturedKey.from(keyCode: keyCode, modifierBits: modBits))
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturing else { return }
            self.finishCapture()
            completion(.none)
        }
        captureTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: work)
    }

    /// Cancels an in-flight capture without invoking the completion (the UI that
    /// asked to cancel already knows). Safe to call when not capturing.
    private func cancelCapture() {
        guard isCapturing else { return }
        finishCapture()
    }

    private func finishCapture() {
        isCapturing = false
        captureTimeoutWork?.cancel()
        captureTimeoutWork = nil
        listener?.endCapture()
        if pendingRebuildAfterCapture {
            pendingRebuildAfterCapture = false
            buildListener()
        }
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
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCapturing {
                // Don't swap out the capturing listener or clear the test UI mid-test;
                // run the rebuild when capture finishes.
                self.pendingRebuildAfterCapture = true
                return
            }
            self.buildListener()
            NotificationCenter.default.post(name: .footswitchDeviceChanged, object: nil)
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowFactory.make(
                store: store,
                onSave: { [weak self] newConfig in self?.reload(newConfig) },
                beginCapture: { [weak self] (timeoutMs: Int, completion: @escaping @Sendable (CapturedKey) -> Void) in
                    self?.beginCapture(timeoutMs: timeoutMs, completion: completion)
                },
                cancelCapture: { [weak self] in self?.cancelCapture() })
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
        FootswitchHIDController.registeredDevices = newConfig.devices
        dispatcher = ActionDispatcher(
            poster: LiveEventPoster(),
            dictationShortcut: effectiveDictationShortcut(),
            shortcutRunner: ShortcutRunner())
        menuBar.setDictationUnsupported(dictationUnsupported)
        // Trigger keys / debounce changes take effect immediately by rebuilding
        // the listener (clamped to the detected slot count).
        buildListener()
    }

    /// The Dictation key combo the dispatcher should send for a `.dictation` action.
    ///
    /// An explicit (non-default) `dictationShortcut` in config wins — that's the
    /// user's manual override. Otherwise we adopt the user's *real* macOS Dictation
    /// hotkey so the default action "just works" without hand-syncing config to
    /// System Settings (#15). A double-press / unsynthesizable system shortcut
    /// can't be sent as a keystroke: fall back to the configured combo and, when
    /// dictation is actually reachable, flag a menu-bar warning so the failure is
    /// visible rather than silent.
    private func effectiveDictationShortcut() -> KeyCombo {
        dictationUnsupported = false

        // A hand-set override in config.json takes precedence over auto-detection.
        if config.dictationShortcut != Config.default.dictationShortcut {
            return config.dictationShortcut
        }

        switch DictationHotkeyReader.systemResolution() {
        case .combo(let combo):
            return combo
        case .unsynthesizable:
            dictationUnsupported = dictationReachable
            return config.dictationShortcut
        case .absent:
            return config.dictationShortcut
        }
    }

    /// Whether any press can resolve to dictation (so an unsynthesizable system
    /// shortcut is worth warning about): the default action, or any per-app rule.
    private var dictationReachable: Bool {
        if config.defaultAction == .dictation { return true }
        return config.rules.contains { $0.slots.bySlot.values.contains(.dictation) }
    }
}
