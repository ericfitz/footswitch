import AppKit
import FootswitchCore

// MARK: - Window factory

enum SettingsWindowFactory {
    @MainActor
    static func make(store: ConfigStore, onSave: @escaping (Config) -> Void) -> NSWindow {
        let config = (try? store.load()) ?? .default
        let controller = SettingsViewController(config: config, onSave: onSave)
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
// is no Save button. Per-app rules are key-combo only in this UI; dictation is
// the global default action (configured separately).

@MainActor
final class SettingsViewController: NSViewController {
    private var rules: [Rule]
    private var defaultAction: DefaultAction
    private let baseConfig: Config
    private let onSave: (Config) -> Void

    private let tableView = NSTableView()
    private let addRemove = NSSegmentedControl()
    private var launchAtLoginCheckbox: NSButton!
    private var launchAtLoginHint: NSTextField!
    private var dictationCheckbox: NSButton!
    private var deviceStatusLabel: NSTextField!
    private var infoButton: NSButton!
    private var configStatusLabel: NSTextField!
    private var programButton: NSButton!
    private var configRow: NSStackView!
    private var deviceSection: NSStackView!

    /// Cached detected pedal count for this Settings window's lifetime, so column
    /// rebuilds / reloadData don't re-probe. Starts at 1 (safe single-slot layout).
    private var detectedSlotCount = 1

    /// Dynamically-created config rows for slots 2..N (slot 1 reuses `configRow`).
    private var extraSlotRows: [NSStackView] = []

    init(config: Config, onSave: @escaping (Config) -> Void) {
        self.baseConfig = config
        self.rules = config.rules
        self.defaultAction = config.defaultAction
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 460))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        tableView.reloadData()
        detectSlotsAndRebuild()
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
        configRow = NSStackView(views: [configStatusLabel, programButton])
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

        // Table inside a scroll view.
        configureTable()
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
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
                                        rulesHeader, hint, scroll, addRemove])
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

        let appCol = NSTableColumn(identifier: .init("app"))
        appCol.title = L10n.settingsColApplication
        appCol.width = 320
        tableView.addTableColumn(appCol)

        rebuildShortcutColumns()
    }

    /// Rebuilds the shortcut column(s): one per detected slot. Identifier encodes
    /// the 1-based slot as "shortcut.<slot>". When count==1 the single column keeps
    /// the legacy "Shortcut" title for an unchanged single-pedal look.
    private func rebuildShortcutColumns() {
        for col in tableView.tableColumns where col.identifier.rawValue.hasPrefix("shortcut") {
            tableView.removeTableColumn(col)
        }
        if detectedSlotCount <= 1 {
            let col = NSTableColumn(identifier: .init("shortcut.1"))
            col.title = L10n.settingsColShortcut
            col.width = 180
            tableView.addTableColumn(col)
        } else {
            for slot in 1...detectedSlotCount {
                let col = NSTableColumn(identifier: .init("shortcut.\(slot)"))
                col.title = L10n.settingsColPedalShortcut(slot)
                col.width = 140
                tableView.addTableColumn(col)
            }
        }
    }

    // MARK: Actions

    /// The transport of the currently-detected device, or nil if none. `.footswitch`
    /// family means USB; `.footswitchBLE` means Bluetooth.
    private func currentTransport() -> Transport? {
        switch FootswitchHIDController.detect()?.device.program {
        case .footswitch: return .usb
        case .footswitchBLE: return .bluetooth
        default: return nil
        }
    }

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

        let transport: Transport = detected.device.program == .footswitchBLE ? .bluetooth : .usb
        if multi {
            verifyAndRenderRow(slot: 1, transport: transport,
                               label: configStatusLabel, button: programButton)
            renderExtraSlotRows(transport: transport)
        } else {
            clearExtraSlotRows()
            verifyAndRenderRow(slot: 1, transport: transport,
                               label: configStatusLabel, button: programButton)
        }
    }

    /// Verifies one slot off-main and renders status + program button for its row.
    private func verifyAndRenderRow(slot: Int, transport: Transport,
                                    label: NSTextField, button: NSButton) {
        let expected = KeyCombo(modifiers: [], key: keyForSlot(slot, transport: transport))
        label.attributedStringValue = statusLine("…", "", .secondaryLabelColor)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FootswitchHIDController.verifyConfiguration(expected: expected, slot: slot)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .verified:
                    if transport == .bluetooth {
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

    /// The configured trigger key for a slot on a transport (fallback to primary).
    private func keyForSlot(_ slot: Int, transport: Transport) -> String {
        baseConfig.triggers.keys(for: transport).first { $0.slot == slot }?.key
            ?? baseConfig.triggers.primary(for: transport).key
    }

    private func renderExtraSlotRows(transport: Transport) {
        clearExtraSlotRows()
        guard detectedSlotCount > 1 else { return }
        for slot in 2...detectedSlotCount {
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12)
            let button = NSButton(title: L10n.settingsProgramButton,
                                  target: self, action: #selector(programSlotButton(_:)))
            button.bezelStyle = .rounded
            button.tag = slot
            let prefix = NSTextField(labelWithString: L10n.deviceSlotLabel(slot) + ":")
            prefix.font = .systemFont(ofSize: 12)
            let row = NSStackView(views: [prefix, status, button])
            row.orientation = .horizontal
            row.spacing = 8
            deviceSection.addArrangedSubview(row)
            extraSlotRows.append(row)
            verifyAndRenderRow(slot: slot, transport: transport, label: status, button: button)
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

    private func programSlot(_ slot: Int, button: NSButton) {
        // Program the key for the transport the device is currently connected on —
        // the FS17Pro stores USB and Bluetooth configs independently, so we must
        // write the correct transport's key (not a single global key).
        // Silent no-op if no device: intentional — the Program button is only shown
        // when a programmable device was detected (i.e. on .mismatch).
        guard let transport = currentTransport() else { return }
        let key = keyForSlot(slot, transport: transport)
        let combo = KeyCombo(modifiers: [], key: key)
        button.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                try FootswitchHIDController.program(combo: combo, slot: slot)
                message = transport == .bluetooth
                    ? L10n.alertProgrammedBluetooth(key: key)
                    : L10n.alertProgrammed(key: key)
            } catch {
                message = L10n.alertProgramFailed(error: "\(error)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                button.isEnabled = true
                self.presentInfo(message)
                self.refreshDeviceStatus()
            }
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

    private func save() {
        var config = baseConfig
        config.rules = rules
        config.defaultAction = defaultAction
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
            let capture = ShortcutCaptureView()
            if case .keyCombo(let combo)? = rule.slots.action(forSlot: slot), !combo.key.isEmpty {
                capture.combo = combo
            }
            capture.onCapture = { [weak self] combo in
                self?.updateShortcut(row: row, slot: slot, combo: combo)
            }
            capture.onClear = { [weak self] in
                self?.clearShortcut(row: row, slot: slot)
            }
            return capture

        default:
            return nil
        }
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
