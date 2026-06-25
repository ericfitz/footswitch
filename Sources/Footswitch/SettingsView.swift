import AppKit
import FootswitchCore

/// The two per-rule action kinds the Settings UI lets the user choose between.
enum ActionKind { case keySequence, shortcut }

// MARK: - Window factory

enum SettingsWindowFactory {
    @MainActor
    static func make(store: ConfigStore,
                     onSave: @escaping (Config) -> Void,
                     beginCapture: @escaping (_ timeoutMs: Int, _ completion: @escaping @Sendable (CapturedKey) -> Void) -> Void,
                     cancelCapture: @escaping () -> Void) -> NSWindow {
        let config = (try? store.load()) ?? .default
        let controller = SettingsViewController(config: config, onSave: onSave,
                                                beginCapture: beginCapture, cancelCapture: cancelCapture)
        let window = NSWindow(contentViewController: controller)
        window.title = L10n.settingsWindowTitle
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 460))
        return window
    }
}

// MARK: - Settings view controller
//
// A native AppKit settings pane: a default-action toggle plus a rules table with
// the standard +/- segmented bar. Every mutation auto-saves via `onSave` — there
// is no Save button. Per-app rules send a key combo or run a Shortcut; dictation
// is the global default action (configured separately).

@MainActor
final class SettingsViewController: NSViewController {
    // Properties are `internal` (not `private`) because the controller's methods
    // live in same-target extensions split across SettingsView*.swift files; Swift
    // `private` is file-scoped, so those would otherwise be inaccessible.
    var rules: [Rule]
    var defaultAction: DefaultAction
    let baseConfig: Config
    let onSave: (Config) -> Void
    var devices: [Device]
    let beginCaptureFn: (_ timeoutMs: Int, _ completion: @escaping @Sendable (CapturedKey) -> Void) -> Void
    let cancelCaptureFn: () -> Void

    let tableView = NSTableView()
    let addRemove = NSSegmentedControl()
    var launchAtLoginCheckbox: NSButton!
    var launchAtLoginHint: NSTextField!
    var dictationCheckbox: NSButton!
    var deviceStatusLabel: NSTextField!
    var infoButton: NSButton!
    var configStatusLabel: NSTextField!
    var programButton: NSButton!
    var testButton: NSButton!
    var activeTestSlot: Int?
    var configRow: NSStackView!
    var deviceSection: NSStackView!

    /// Cached detected pedal count for this Settings window's lifetime, so column
    /// rebuilds / reloadData don't re-probe. Starts at 1 (safe single-slot layout).
    var detectedSlotCount = 1

    /// Slots that were just programmed over Bluetooth and are awaiting a physical
    /// power-cycle. A BLE program writes the stored config slot but the live keymap
    /// only reloads on a power-cycle (#7), so the stored config can read back as
    /// "verified" while the pedal still emits the old key. Only these slots show the
    /// "power-cycle to apply" warning; it is cleared on re-detect (a power-cycle's
    /// disconnect/reconnect), adopt, or a confirming Test (#12).
    var blePowerCyclePendingSlots: Set<Int> = []

    /// Dynamically-created config rows for slots 2..N (slot 1 reuses `configRow`).
    var extraSlotRows: [NSStackView] = []

    /// Installed Shortcuts.app shortcuts, fetched once on first use and cached for
    /// this window's lifetime (NSTableView recycles cells, so a per-cell fetch
    /// would spawn `shortcuts list` repeatedly). `nil` until first fetched.
    private var shortcutCatalogCache: [ShortcutRef]?

    /// Lazily fetches + caches the installed-shortcut catalog.
    func shortcutCatalog() -> [ShortcutRef] {
        if let cache = shortcutCatalogCache { return cache }
        let list = ShortcutCatalog.installed()
        shortcutCatalogCache = list
        return list
    }

    init(config: Config,
         onSave: @escaping (Config) -> Void,
         beginCapture: @escaping (_ timeoutMs: Int, _ completion: @escaping @Sendable (CapturedKey) -> Void) -> Void,
         cancelCapture: @escaping () -> Void) {
        self.baseConfig = config
        self.rules = config.rules
        self.defaultAction = config.defaultAction
        self.devices = config.devices
        self.onSave = onSave
        self.beginCaptureFn = beginCapture
        self.cancelCaptureFn = cancelCapture
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 460))
    }

    /// Observer token for live device-change refreshes (USB/BLE attach, detach,
    /// transport switch). Removed in the nonisolated deinit; `nonisolated(unsafe)`
    /// because the token is only ever assigned on the main actor and read once in
    /// deinit (NotificationCenter.removeObserver is itself thread-safe).
    private nonisolated(unsafe) var deviceChangeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        tableView.reloadData()
        detectSlotsAndRebuild()

        // Re-detect when devices change while this window is open, so the device
        // row / config status / per-slot columns don't go stale (e.g. the user
        // unplugs the pedal or switches the FS17Pro between USB and Bluetooth).
        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: .footswitchDeviceChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // A device change includes a BLE power-cycle's disconnect/reconnect, by
                // which point the live keymap has reloaded — clear pending warnings (#12).
                self?.blePowerCyclePendingSlots.removeAll()
                self?.detectSlotsAndRebuild()
            }
        }
    }

    deinit {
        if let deviceChangeObserver {
            NotificationCenter.default.removeObserver(deviceChangeObserver)
        }
    }

    /// Probes the pedal count off-main (expensive), then on main updates the cache,
    /// rebuilds the shortcut columns, the per-slot config rows, and reloads.
    private func detectSlotsAndRebuild() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let count = FootswitchHIDController.detectedSlotCount()
            DispatchQueue.main.async {
                guard let self, count != self.detectedSlotCount else {
                    self?.refreshDeviceStatus()
                    return
                }
                self.detectedSlotCount = count
                self.rebuildShortcutColumns()
                self.tableView.reloadData()
                self.refreshDeviceStatus()
            }
        }
    }
}
