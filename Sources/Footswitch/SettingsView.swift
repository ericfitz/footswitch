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

// TODO: this controller has outgrown one file — split the rules-table data source
// and the capture views into their own files, then drop these suppressions.
// swiftlint:disable file_length type_body_length
@MainActor
final class SettingsViewController: NSViewController {
    private var rules: [Rule]
    private var defaultAction: DefaultAction
    private let baseConfig: Config
    private let onSave: (Config) -> Void
    private var devices: [Device]
    private let beginCaptureFn: (_ timeoutMs: Int, _ completion: @escaping @Sendable (CapturedKey) -> Void) -> Void
    private let cancelCaptureFn: () -> Void

    private let tableView = NSTableView()
    private let addRemove = NSSegmentedControl()
    private var launchAtLoginCheckbox: NSButton!
    private var launchAtLoginHint: NSTextField!
    private var dictationCheckbox: NSButton!
    private var deviceStatusLabel: NSTextField!
    private var infoButton: NSButton!
    private var configStatusLabel: NSTextField!
    private var programButton: NSButton!
    private var testButton: NSButton!
    private var activeTestSlot: Int?
    private var configRow: NSStackView!
    private var deviceSection: NSStackView!

    /// Cached detected pedal count for this Settings window's lifetime, so column
    /// rebuilds / reloadData don't re-probe. Starts at 1 (safe single-slot layout).
    private var detectedSlotCount = 1

    /// Slots that were just programmed over Bluetooth and are awaiting a physical
    /// power-cycle. A BLE program writes the stored config slot but the live keymap
    /// only reloads on a power-cycle (#7), so the stored config can read back as
    /// "verified" while the pedal still emits the old key. Only these slots show the
    /// "power-cycle to apply" warning; it is cleared on re-detect (a power-cycle's
    /// disconnect/reconnect), adopt, or a confirming Test (#12).
    private var blePowerCyclePendingSlots: Set<Int> = []

    /// Dynamically-created config rows for slots 2..N (slot 1 reuses `configRow`).
    private var extraSlotRows: [NSStackView] = []

    /// Installed Shortcuts.app shortcuts, fetched once on first use and cached for
    /// this window's lifetime (NSTableView recycles cells, so a per-cell fetch
    /// would spawn `shortcuts list` repeatedly). `nil` until first fetched.
    private var shortcutCatalogCache: [ShortcutRef]?

    /// Lazily fetches + caches the installed-shortcut catalog.
    private func shortcutCatalog() -> [ShortcutRef] {
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

    // MARK: UI construction

    // swiftlint:disable:next function_body_length
    private func buildUI() {
        // Foot switch device section: row 1 = detection, row 2 = config verification.
        let deviceHeader = makeHeader(L10n.settingsHeaderDevice)
        deviceStatusLabel = NSTextField(labelWithString: "")
        deviceStatusLabel.font = .systemFont(ofSize: 12)
        infoButton = NSButton(title: "", target: self, action: #selector(showDeviceInfo))
        infoButton.bezelStyle = .helpButton
        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Switch info")
        infoButton.isBordered = false
        infoButton.imagePosition = .imageOnly
        let detectedRow = NSStackView(views: [deviceStatusLabel, infoButton])
        detectedRow.orientation = .horizontal
        detectedRow.spacing = 8

        configStatusLabel = NSTextField(labelWithString: "")
        configStatusLabel.font = .systemFont(ofSize: 12)
        programButton = NSButton(title: L10n.settingsProgramButton,
                                 target: self, action: #selector(programPedal))
        programButton.bezelStyle = .rounded
        testButton = NSButton(title: L10n.settingsTestButton,
                              target: self, action: #selector(testPedal))
        testButton.bezelStyle = .rounded
        configRow = NSStackView(views: [configStatusLabel, programButton, testButton])
        configRow.orientation = .horizontal
        configRow.spacing = 12

        deviceSection = NSStackView(views: [detectedRow, configRow])
        deviceSection.orientation = .vertical
        deviceSection.alignment = .leading
        deviceSection.spacing = 4
        refreshDeviceStatus()

        // General app options: launch at login (OS-owned state, not in Config).
        let generalHeader = makeHeader(L10n.settingsHeaderGeneral)
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: L10n.settingsLaunchAtLoginCheckbox,
                                         target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
        launchAtLoginHint = NSTextField(wrappingLabelWithString: L10n.settingsLaunchAtLoginApprovalHint)
        launchAtLoginHint.font = .systemFont(ofSize: 11)
        launchAtLoginHint.textColor = .secondaryLabelColor
        launchAtLoginHint.maximumNumberOfLines = 2
        launchAtLoginHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Only shown when macOS is waiting on the user to approve the login item.
        launchAtLoginHint.isHidden = !LoginItem.requiresApproval

        let defaultHeader = makeHeader(L10n.settingsHeaderDefault)
        dictationCheckbox = NSButton(checkboxWithTitle: L10n.settingsDictationCheckbox,
                                     target: self, action: #selector(dictationCheckboxChanged))
        dictationCheckbox.state = (defaultAction == .dictation) ? .on : .off

        let rulesHeader = makeHeader(L10n.settingsHeaderRules)
        let hint = NSTextField(wrappingLabelWithString: L10n.settingsRulesHint)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        // Wrap (don't widen the window) when the localized hint is long, e.g. German.
        hint.maximumNumberOfLines = 2
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // One-line note that macOS may prompt the first time a Shortcut runs.
        let shortcutHint = NSTextField(wrappingLabelWithString: L10n.settingsShortcutPermissionHint)
        shortcutHint.font = .systemFont(ofSize: 11)
        shortcutHint.textColor = .secondaryLabelColor
        shortcutHint.maximumNumberOfLines = 2
        shortcutHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Table inside a scroll view.
        configureTable()
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        // Safety net (issue #11): if the window is narrowed past the point where the
        // app column can absorb it, scroll horizontally rather than clip the mapping.
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Native +/- segmented control beneath the table.
        addRemove.segmentStyle = .smallSquare
        addRemove.trackingMode = .momentary
        addRemove.segmentCount = 2
        addRemove.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: "Add app rule"), forSegment: 0)
        addRemove.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove selected rule"), forSegment: 1)
        addRemove.setWidth(28, forSegment: 0)
        addRemove.setWidth(28, forSegment: 1)
        addRemove.target = self
        addRemove.action = #selector(addRemoveClicked)
        addRemove.translatesAutoresizingMaskIntoConstraints = false
        updateRemoveEnabled()

        let stack = NSStackView(views: [deviceHeader, deviceSection, makeSpacer(8),
                                        generalHeader, launchAtLoginCheckbox, launchAtLoginHint, makeSpacer(8),
                                        defaultHeader, dictationCheckbox, makeSpacer(8),
                                        rulesHeader, hint, scroll, addRemove, shortcutHint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            // Bound the hint's width so a long localized string wraps to a second
            // line instead of stretching the layout.
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            launchAtLoginHint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            shortcutHint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
    }

    private func makeHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func makeSpacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func configureTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.allowsMultipleSelection = false
        // Width priority (issue #11): the action/key-mapping column(s) must stay wide
        // enough to show the whole mapping. Make the app-name column the only one that
        // auto-resizes, so when the table is narrowed it is the app column that shrinks
        // — not the mapping column.
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let appCol = NSTableColumn(identifier: .init("app"))
        appCol.title = L10n.settingsColApplication
        appCol.width = 320
        appCol.minWidth = 80   // absorbs narrowing, but never collapses to nothing
        tableView.addTableColumn(appCol)

        rebuildShortcutColumns()
    }

    /// Rebuilds the action column(s): one per detected slot. Identifier encodes
    /// the 1-based slot as "shortcut.<slot>" (kept stable — the cell-vending switch
    /// keys off it). When count==1 the single column uses the generic "Action"
    /// title since a row can hold either a key sequence or a Shortcut.
    private func rebuildShortcutColumns() {
        for col in tableView.tableColumns where col.identifier.rawValue.hasPrefix("shortcut") {
            tableView.removeTableColumn(col)
        }
        if detectedSlotCount <= 1 {
            let col = NSTableColumn(identifier: .init("shortcut.1"))
            col.title = L10n.settingsColAction
            col.width = 240
            col.minWidth = 240   // hold full width for the key mapping (issue #11)
            tableView.addTableColumn(col)
        } else {
            for slot in 1...detectedSlotCount {
                let col = NSTableColumn(identifier: .init("shortcut.\(slot)"))
                col.title = L10n.settingsColPedalShortcut(slot)
                col.width = 200
                col.minWidth = 200   // hold full width for the key mapping (issue #11)
                tableView.addTableColumn(col)
            }
        }
    }

    /// Re-fits each action column to the widest action cell currently in it, so the
    /// kind popup + its kind-specific editor stay fully visible (no clipping, no
    /// excess slack) after a row's action kind changes (issue #14). Never shrinks a
    /// column below its `minWidth` — that floor is the issue-#11 guarantee that the
    /// mapping column keeps the app-name column, not itself, as the one that narrows.
    private func fitShortcutColumns() {
        for col in tableView.tableColumns where col.identifier.rawValue.hasPrefix("shortcut") {
            let colIndex = tableView.column(withIdentifier: col.identifier)
            guard colIndex >= 0 else { continue }
            var widest = col.minWidth
            for row in 0..<tableView.numberOfRows {
                guard let cell = tableView.view(atColumn: colIndex, row: row, makeIfNecessary: true) else { continue }
                widest = max(widest, cell.fittingSize.width)
            }
            col.width = widest
        }
    }

    // MARK: Actions

    private func refreshDeviceStatus() {
        guard let detected = FootswitchHIDController.detect() else {
            deviceStatusLabel.attributedStringValue = statusLine("⊘", L10n.deviceNone, .secondaryLabelColor)
            infoButton.isHidden = true
            configRow.isHidden = true
            clearExtraSlotRows()
            return
        }
        let isUSB = detected.device.program == .footswitch
        let multi = isUSB && detectedSlotCount > 1
        deviceStatusLabel.attributedStringValue = statusLine(
            "✓",
            multi ? L10n.deviceDetectedSlots(name: detected.device.name, count: detectedSlotCount)
                  : L10n.deviceDetected(name: detected.device.name),
            .systemGreen)
        infoButton.isHidden = false
        configRow.isHidden = false

        if multi {
            verifyAndRenderRow(slot: 1, device: detected.device,
                               label: configStatusLabel, button: programButton)
            renderExtraSlotRows(device: detected.device)
        } else {
            clearExtraSlotRows()
            verifyAndRenderRow(slot: 1, device: detected.device,
                               label: configStatusLabel, button: programButton)
        }
    }

    /// Verifies one slot off-main and renders status + program button for its row.
    private func verifyAndRenderRow(slot: Int, device: SupportedDevice,
                                    label: NSTextField, button: NSButton) {
        let transport = device.program.transport
        let expected = keyForSlot(slot, device: device)
        label.attributedStringValue = statusLine("…", "", .secondaryLabelColor)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FootswitchHIDController.verifyConfiguration(expected: expected, slot: slot)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .verified:
                    // Show the BLE "power-cycle to apply" warning only for a slot we
                    // just programmed over Bluetooth (live keymap not yet reloaded);
                    // an otherwise-verified BLE config reads as ✓ verified (#12).
                    if transport == .bluetooth && self.blePowerCyclePendingSlots.contains(slot) {
                        label.attributedStringValue =
                            self.statusLine("⚠", L10n.deviceConfigStoredBluetooth, .systemYellow)
                    } else {
                        label.attributedStringValue =
                            self.statusLine("✓", L10n.deviceConfigVerified, .systemGreen)
                    }
                    button.isHidden = true
                case .mismatch:
                    label.attributedStringValue =
                        self.statusLine("⚠", L10n.deviceConfigMismatch, .systemYellow)
                    button.isHidden = false
                    button.isEnabled = true
                case .unreadable:
                    label.attributedStringValue =
                        self.statusLine("✗", L10n.deviceConfigUnreadable, .systemRed)
                    button.isHidden = true
                case .noDevice:
                    button.isHidden = true
                }
            }
        }
    }

    /// The configured trigger combo for a slot on the connected `device` (its entry's
    /// trigger, else the code default), from the live `devices` so an adopt shows now.
    private func keyForSlot(_ slot: Int, device: SupportedDevice) -> KeyCombo {
        Config.triggerCombo(in: devices, forVendorID: device.vendorID,
                            productID: device.productID, slot: slot)
    }

    private func renderExtraSlotRows(device: SupportedDevice) {
        clearExtraSlotRows()
        guard detectedSlotCount > 1 else { return }
        for slot in 2...detectedSlotCount {
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12)
            let button = NSButton(title: L10n.settingsProgramButton,
                                  target: self, action: #selector(programSlotButton(_:)))
            button.bezelStyle = .rounded
            button.tag = slot
            let test = NSButton(title: L10n.settingsTestButton,
                                target: self, action: #selector(testSlotButton(_:)))
            test.bezelStyle = .rounded
            test.tag = slot
            let prefix = NSTextField(labelWithString: L10n.deviceSlotLabel(slot) + ":")
            prefix.font = .systemFont(ofSize: 12)
            let row = NSStackView(views: [prefix, status, button, test])
            row.orientation = .horizontal
            row.spacing = 8
            deviceSection.addArrangedSubview(row)
            extraSlotRows.append(row)
            verifyAndRenderRow(slot: slot, device: device, label: status, button: button)
        }
    }

    private func clearExtraSlotRows() {
        for row in extraSlotRows {
            deviceSection.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        extraSlotRows.removeAll()
    }

    // A status line with a colored symbol prefix and default-color text.
    private func statusLine(_ symbol: String, _ text: String, _ color: NSColor) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: symbol + "  ",
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
        s.append(NSAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12)]))
        return s
    }

    @objc private func showDeviceInfo() {
        DispatchQueue.global(qos: .userInitiated).async {
            let info = FootswitchHIDController.deviceInfo() ?? L10n.alertDeviceInfoNone
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = L10n.alertDeviceInfoTitle
                let field = NSTextField(labelWithString: info)
                field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                field.sizeToFit()
                alert.accessoryView = field
                alert.informativeText = ""
                alert.addButton(withTitle: L10n.alertOK)
                if let window = self.view.window {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }
    }

    @objc private func programPedal() { programSlot(1, button: programButton) }

    @objc private func programSlotButton(_ sender: NSButton) {
        programSlot(sender.tag, button: sender)
    }

    private func programSlot(_ slot: Int, button: NSButton?) {
        // Program the key for the transport the device is currently connected on —
        // the FS17Pro stores USB and Bluetooth configs independently, so we must
        // write the correct transport's key (not a single global key).
        // Silent no-op if no device: intentional — the Program button is only shown
        // when a programmable device was detected (i.e. on .mismatch).
        guard let detected = FootswitchHIDController.detect() else { return }
        let transport = detected.device.program.transport
        let combo = keyForSlot(slot, device: detected.device)
        button?.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            var programmedBLE = false
            do {
                try FootswitchHIDController.program(combo: combo, slot: slot)
                programmedBLE = (transport == .bluetooth)
                message = transport == .bluetooth
                    ? L10n.alertProgrammedBluetooth(key: KeyComboFormatter.display(combo))
                    : L10n.alertProgrammed(key: KeyComboFormatter.display(combo))
            } catch {
                message = L10n.alertProgramFailed(error: "\(error)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                button?.isEnabled = true
                // A successful BLE program needs a power-cycle before the pedal emits
                // the new key — mark the slot pending so the row warns until cleared (#12).
                if programmedBLE { self.blePowerCyclePendingSlots.insert(slot) }
                self.presentInfo(message)
                self.refreshDeviceStatus()
            }
        }
    }

    @objc private func testPedal() { startTest(slot: 1) }

    @objc private func testSlotButton(_ sender: NSButton) { startTest(slot: sender.tag) }

    /// Arms capture for `slot`, shows a cancelable "press the pedal" sheet, and on
    /// completion presents the reconciliation outcome. Gated on a connected device
    /// (resolved via detect()); no-ops otherwise (matches the Program button).
    private func startTest(slot: Int) {
        guard activeTestSlot == nil,
              let detected = FootswitchHIDController.detect(),
              let window = view.window else { return }
        let device = detected.device
        activeTestSlot = slot

        let armed = NSAlert()
        armed.messageText = L10n.alertTestTitle
        armed.informativeText = L10n.testPrompt(slot: slot)
        armed.addButton(withTitle: L10n.alertCancel)
        armed.beginSheetModal(for: window) { [weak self] _ in
            // Sheet dismissed. If still armed, it was a user Cancel — stop capture.
            guard let self, self.activeTestSlot == slot else { return }
            self.activeTestSlot = nil
            self.cancelCaptureFn()
            self.refreshDeviceStatus()
        }

        beginCaptureFn(15_000) { [weak self] captured in
            // AppDelegate calls this completion on the main thread; assert isolation.
            MainActor.assumeIsolated {
                guard let self, self.activeTestSlot == slot else { return }
                self.activeTestSlot = nil
                // Dismiss the armed sheet before showing the result.
                if let sheet = self.view.window?.attachedSheet {
                    self.view.window?.endSheet(sheet)
                }
                let expected = self.keyForSlot(slot, device: device)
                let outcome = TriggerReconciler.reconcile(captured: captured, expected: expected)
                self.presentTestOutcome(outcome, slot: slot, device: device)

            }
        }
    }

    private func presentTestOutcome(_ outcome: TriggerReconciliation, slot: Int,
                                    device: SupportedDevice) {
        // A Test that confirms the pedal emits the expected key means no power-cycle is
        // pending for that slot — clear it before rendering so the row shows ✓ (#12).
        if case .match = outcome { blePowerCyclePendingSlots.remove(slot) }
        refreshDeviceStatus()   // restore the normal row UI under the outcome sheet
        let alert = NSAlert()
        alert.messageText = L10n.alertTestTitle
        switch outcome {
        case .match(let combo):
            alert.informativeText = L10n.testMatch(key: KeyComboFormatter.display(combo))
            alert.addButton(withTitle: L10n.alertOK)
            runOutcome(alert) { _ in }
        case .mismatch(let captured, let expected):
            alert.informativeText = L10n.testMismatch(
                captured: KeyComboFormatter.display(captured),
                expected: KeyComboFormatter.display(expected))
            alert.addButton(withTitle: L10n.testUseKey(key: KeyComboFormatter.display(captured)))     // first
            alert.addButton(withTitle: L10n.testReprogram(key: KeyComboFormatter.display(expected)))  // second
            alert.addButton(withTitle: L10n.alertCancel)                                              // third
            runOutcome(alert) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    self?.adopt(combo: captured, slot: slot, device: device)
                } else if resp == .alertSecondButtonReturn {
                    self?.reprogram(slot: slot)
                }
            }
        case .unknown(let code, let expected):
            alert.informativeText = L10n.testUnknown(
                code: String(format: "0x%02X", code),
                expected: KeyComboFormatter.display(expected))
            alert.addButton(withTitle: L10n.testReprogram(key: KeyComboFormatter.display(expected)))  // first
            alert.addButton(withTitle: L10n.alertCancel)                                              // second
            runOutcome(alert) { [weak self] resp in
                if resp == .alertFirstButtonReturn { self?.reprogram(slot: slot) }
            }
        case .noKey:
            alert.informativeText = L10n.testNoKey
            alert.addButton(withTitle: L10n.alertOK)
            runOutcome(alert) { _ in }
        }
    }

    private func adopt(combo: KeyCombo, slot: Int, device: SupportedDevice) {
        devices = Config.adoptingTriggerCombo(in: devices, combo: combo, slot: slot, for: device)
        // Config now matches what the pedal emits — there is no pending power-cycle (#12).
        blePowerCyclePendingSlots.remove(slot)
        save()
        refreshDeviceStatus()
    }

    private func reprogram(slot: Int) {
        programSlot(slot, button: slot == 1 ? programButton : nil)
    }

    private func runOutcome(_ alert: NSAlert,
                            handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    private func presentInfo(_ text: String) {
        let alert = NSAlert()
        alert.messageText = L10n.alertFootswitchTitle
        alert.informativeText = text
        alert.addButton(withTitle: L10n.alertOK)
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    @objc private func launchAtLoginChanged() {
        let wantEnabled = (launchAtLoginCheckbox.state == .on)
        do {
            let actual = try LoginItem.setEnabled(wantEnabled)
            // Reconcile the checkbox with what actually took effect (e.g. macOS may
            // defer a registration to user approval, leaving it not-yet-enabled).
            launchAtLoginCheckbox.state = actual ? .on : .off
            launchAtLoginHint.isHidden = !LoginItem.requiresApproval
        } catch {
            // Revert the checkbox to the real state and tell the user why.
            launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
            launchAtLoginHint.isHidden = !LoginItem.requiresApproval
            let alert = NSAlert()
            alert.messageText = L10n.alertLaunchAtLoginTitle
            alert.informativeText = L10n.alertLaunchAtLoginFailed(error: "\(error)")
            alert.addButton(withTitle: L10n.alertOK)
            if let window = view.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }

    @objc private func dictationCheckboxChanged() {
        defaultAction = (dictationCheckbox.state == .on) ? .dictation : .none
        save()
    }

    @objc private func addRemoveClicked() {
        if addRemove.selectedSegment == 0 { addRule() } else { removeSelectedRule() }
    }

    private func addRule() {
        let panel = NSOpenPanel()
        panel.title = L10n.openPanelTitle
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }

        let appName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")

        // If a rule for this app already exists, select it instead of duplicating.
        if let existing = rules.firstIndex(where: { $0.match == bundleID }) {
            tableView.selectRowIndexes([existing], byExtendingSelection: false)
            tableView.scrollRowToVisible(existing)
            updateRemoveEnabled()
            return
        }

        // Pre-fill a known app's suggested shortcut; otherwise start blank.
        let suggested = KnownAppDefaults.suggestedShortcut(forBundleID: bundleID)
        let slots = SlotActions(bySlot: suggested.map { [1: Action.keyCombo($0)] } ?? [:])
        rules.append(Rule(match: bundleID, appName: appName, slots: slots))
        let row = rules.count - 1
        tableView.reloadData()
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        updateRemoveEnabled()
        save()
    }

    private func removeSelectedRule() {
        let row = tableView.selectedRow
        guard rules.indices.contains(row) else { return }
        rules.remove(at: row)
        tableView.reloadData()
        updateRemoveEnabled()
        save()
    }

    private func updateRemoveEnabled() {
        addRemove.setEnabled(tableView.selectedRow >= 0, forSegment: 1)
    }

    // Called by a row's capture view when the user records a new shortcut.
    fileprivate func updateShortcut(row: Int, slot: Int, combo: KeyCombo) {
        guard rules.indices.contains(row) else { return }
        rules[row].slots.bySlot[slot] = .keyCombo(combo)
        save()
    }

    fileprivate func clearShortcut(row: Int, slot: Int) {
        guard rules.indices.contains(row) else { return }
        rules[row].slots.bySlot[slot] = nil
        save()
    }

    /// Switches a (row, slot)'s action between a key sequence and a Shortcut. To
    /// Key sequence seeds a blank combo (user then records); to Shortcut seeds an
    /// empty ref (user then picks). Rebuilds the row so the editor swaps.
    fileprivate func updateActionKind(row: Int, slot: Int, kind: ActionKind) {
        guard rules.indices.contains(row) else { return }
        switch kind {
        case .keySequence:
            rules[row].slots.bySlot[slot] = .keyCombo(KeyCombo(modifiers: [], key: ""))
        case .shortcut:
            rules[row].slots.bySlot[slot] = .shortcut(ShortcutRef(identifier: "", name: ""))
        }
        save()
        tableView.reloadData(forRowIndexes: [row],
                             columnIndexes: IndexSet(0..<tableView.numberOfColumns))
        // The swapped-in editor (key-capture vs. Shortcut popup) has a different
        // content width; re-fit the action column(s) so it isn't clipped or padded
        // with slack (issue #14).
        fitShortcutColumns()
    }

    /// Sets a (row, slot)'s action to a chosen Shortcut.
    fileprivate func updateShortcutRef(row: Int, slot: Int, ref: ShortcutRef) {
        guard rules.indices.contains(row) else { return }
        rules[row].slots.bySlot[slot] = .shortcut(ref)
        save()
    }

    private func save() {
        var config = baseConfig
        config.rules = rules
        config.defaultAction = defaultAction
        config.devices = devices
        onSave(config)
    }
}

// MARK: - Table data source / delegate

extension SettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = rules[row]
        switch tableColumn?.identifier.rawValue {
        case "app":
            let cell = NSTableCellView()
            let icon = NSImageView()
            icon.image = NSWorkspace.shared.icon(forFile: appPath(forBundleID: rule.match) ?? "")
            icon.translatesAutoresizingMaskIntoConstraints = false
            // Friendly app name; fall back to the bundle ID only when no name.
            let name = NSTextField(labelWithString: rule.appName.isEmpty ? rule.match : rule.appName)
            name.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.addSubview(name)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),
                name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                name.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            ])
            return cell

        case let id? where id.hasPrefix("shortcut."):
            let slot = Int(id.dropFirst("shortcut.".count)) ?? 1
            return actionCell(row: row, slot: slot, action: rule.slots.action(forSlot: slot))

        default:
            return nil
        }
    }

    /// Builds the per-(row, slot) action cell: a kind popup (Key sequence / Run a
    /// Shortcut) plus the kind-specific editor.
    private func actionCell(row: Int, slot: Int, action: Action?) -> NSView {
        let kind: ActionKind = { if case .shortcut = action { return .shortcut } else { return .keySequence } }()

        let kindPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        kindPopup.addItem(withTitle: L10n.settingsActionKindKeySequence)
        kindPopup.addItem(withTitle: L10n.settingsActionKindShortcut)
        kindPopup.selectItem(at: kind == .shortcut ? 1 : 0)
        kindPopup.target = self
        kindPopup.action = #selector(actionKindChanged(_:))
        kindPopup.tag = encode(row: row, slot: slot)
        kindPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let editor: NSView
        switch kind {
        case .keySequence:
            let capture = ShortcutCaptureView()
            if case .keyCombo(let combo)? = action, !combo.key.isEmpty { capture.combo = combo }
            capture.onCapture = { [weak self] combo in self?.updateShortcut(row: row, slot: slot, combo: combo) }
            capture.onClear = { [weak self] in self?.clearShortcut(row: row, slot: slot) }
            editor = capture
        case .shortcut:
            editor = shortcutPopup(row: row, slot: slot, action: action)
        }

        let stack = NSStackView(views: [kindPopup, editor])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.distribution = .fill
        editor.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    /// A popup listing installed Shortcuts (from the cached catalog). The current
    /// selection shows `ref.name`; a stored shortcut no longer installed is shown
    /// with a localized "(not installed)" suffix so the user notices.
    private func shortcutPopup(row: Int, slot: Int, action: Action?) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self
        popup.action = #selector(shortcutSelectionChanged(_:))
        popup.tag = encode(row: row, slot: slot)

        let catalog = shortcutCatalog()
        let current: ShortcutRef? = { if case .shortcut(let ref)? = action { return ref } else { return nil } }()

        if catalog.isEmpty {
            popup.addItem(withTitle: L10n.settingsShortcutNone)
            popup.item(at: 0)?.isEnabled = false
            // Preserve a previously-stored (now un-listable) name if present.
            if let current, !current.name.isEmpty {
                popup.addItem(withTitle: L10n.settingsShortcutNotInstalled(name: current.name))
                popup.selectItem(at: popup.numberOfItems - 1)
            }
            return popup
        }

        // Placeholder first when nothing is chosen yet.
        if current == nil || (current?.identifier.isEmpty ?? true) {
            popup.addItem(withTitle: L10n.settingsShortcutChoose)
            popup.item(at: 0)?.isEnabled = false
        }
        for ref in catalog {
            popup.addItem(withTitle: ref.name)
            popup.lastItem?.representedObject = ref
        }
        if let current, !current.identifier.isEmpty {
            if let idx = catalog.firstIndex(where: { $0.identifier == current.identifier }) {
                // +offset for a leading placeholder if one was added (it wasn't here).
                popup.selectItem(withTitle: catalog[idx].name)
            } else {
                // Stored but not in the freshly-listed set: show "(not installed)".
                popup.addItem(withTitle: L10n.settingsShortcutNotInstalled(name: current.name))
                popup.lastItem?.representedObject = current
                popup.selectItem(at: popup.numberOfItems - 1)
            }
        }
        return popup
    }

    /// Packs (row, slot) into an NSControl tag. slot is small (1...3); row is the
    /// high bits. Decoded by `decode(tag:)`.
    private func encode(row: Int, slot: Int) -> Int { row * 16 + slot }
    private func decode(tag: Int) -> (row: Int, slot: Int) { (tag / 16, tag % 16) }

    @objc private func actionKindChanged(_ sender: NSPopUpButton) {
        let (row, slot) = decode(tag: sender.tag)
        let kind: ActionKind = sender.indexOfSelectedItem == 1 ? .shortcut : .keySequence
        updateActionKind(row: row, slot: slot, kind: kind)
    }

    @objc private func shortcutSelectionChanged(_ sender: NSPopUpButton) {
        let (row, slot) = decode(tag: sender.tag)
        guard let ref = sender.selectedItem?.representedObject as? ShortcutRef else { return }
        updateShortcutRef(row: row, slot: slot, ref: ref)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveEnabled()
    }

    private func appPath(forBundleID id: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
    }
}

// MARK: - Live key-capture view
//
// An AppKit control that records a keyboard shortcut. Click to enter recording
// mode, then press a combo. A modifier is required unless the key is a function
// key (F1-F20). The captured key is stored as a Keymap-recognized name so it
// round-trips through ActionDispatcher.

@MainActor
final class ShortcutCaptureView: NSView {
    var combo: KeyCombo? { didSet { render() } }
    var onCapture: ((KeyCombo) -> Void)?
    var onClear: (() -> Void)?

    private var recording = false { didSet { render() } }
    private let label = NSTextField(labelWithString: "")
    // While recording we install a local event monitor. NSTableView and the
    // window's key-equivalent routing would otherwise swallow Command-combos
    // before they reach this view's keyDown — the monitor sees them first.
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // Tear down the event monitor if the cell is recycled or the window closes
    // while still recording (deinit can't touch @MainActor state under Swift 6).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, recording { stopRecording() }
    }

    // A click anywhere in the cell toggles recording. We override hitTest so the
    // click lands on us (not a subview) and handle it in mouseDown.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self else { return ev }
            return self.handle(ev)
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    // Returns nil to swallow the event (consumed by the recorder) or the event to
    // let it pass through normally.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            // Show the modifiers building up live; don't commit yet.
            renderLive(modifiers(from: event.modifierFlags))
            return nil
        }

        // .keyDown
        // Escape cancels without changing the stored combo.
        if event.keyCode == 0x35 { // Escape
            stopRecording()
            render()
            return nil
        }

        // Delete/Backspace clears the shortcut (standard macOS convention).
        if event.type == .keyDown, event.keyCode == 0x33 { // Delete
            combo = nil
            stopRecording()
            render()
            onClear?()
            return nil
        }

        let mods = modifiers(from: event.modifierFlags)
        guard let keyName = Keymap.keyName(forCode: event.keyCode) else {
            flashHint(L10n.captureUnsupportedKey)
            return nil
        }
        let isFunctionKey = keyName.uppercased().hasPrefix("F") && keyName.count >= 2
            && Int(keyName.dropFirst()) != nil

        // Require at least one modifier unless it's a function key.
        guard !mods.isEmpty || isFunctionKey else {
            flashHint(L10n.captureAddModifier)
            return nil
        }

        let captured = KeyCombo(modifiers: mods, key: keyName)
        combo = captured
        stopRecording()
        render()
        onCapture?(captured)
        return nil
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> [Modifier] {
        var result: [Modifier] = []
        if flags.contains(.control) { result.append(.control) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.shift) { result.append(.shift) }
        if flags.contains(.command) { result.append(.command) }
        return result
    }

    private func flashHint(_ text: String) {
        label.stringValue = text
        label.textColor = .systemRed
    }

    // During recording, echo just-the-modifiers (e.g. "⌘⇧") so the user sees
    // capture is live before they press the final key.
    private func renderLive(_ mods: [Modifier]) {
        guard recording else { return }
        let glyphs = mods.isEmpty ? L10n.capturePressShortcut
            : KeyComboFormatter.display(KeyCombo(modifiers: mods, key: "")).trimmingCharacters(in: .whitespaces)
        label.stringValue = glyphs.isEmpty ? L10n.capturePressShortcut : glyphs
        label.textColor = .secondaryLabelColor
        styleBorder()
    }

    private func styleBorder() {
        layer?.borderWidth = recording ? 2 : 1
        layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.cornerRadius = 5
    }

    private func render() {
        styleBorder()
        label.textColor = .labelColor
        if recording {
            label.stringValue = L10n.capturePressShortcut
            label.textColor = .secondaryLabelColor
        } else if let combo, !combo.key.isEmpty {
            label.stringValue = KeyComboFormatter.display(combo)
        } else {
            label.stringValue = L10n.captureClickToSet
            label.textColor = .secondaryLabelColor
        }
    }
}
