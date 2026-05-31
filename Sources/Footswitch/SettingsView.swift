import AppKit
import FootswitchCore

// MARK: - Window factory

enum SettingsWindowFactory {
    @MainActor
    static func make(store: ConfigStore, onSave: @escaping (Config) -> Void) -> NSWindow {
        let config = (try? store.load()) ?? .default
        let controller = SettingsViewController(config: config, onSave: onSave)
        let window = NSWindow(contentViewController: controller)
        window.title = "Footswitch Settings"
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
    private var dictationRadio: NSButton!
    private var muteRadio: NSButton!
    private var noneRadio: NSButton!
    private var deviceStatusLabel: NSTextField!
    private var configStatusLabel: NSTextField!
    private var programButton: NSButton!
    private var configRow: NSStackView!
    private var deviceSection: NSStackView!

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
    }

    // MARK: UI construction

    private func buildUI() {
        // Foot switch device section: row 1 = detection, row 2 = config verification.
        let deviceHeader = makeHeader("Foot switch")
        deviceStatusLabel = NSTextField(labelWithString: "")
        deviceStatusLabel.font = .systemFont(ofSize: 12)

        configStatusLabel = NSTextField(labelWithString: "")
        configStatusLabel.font = .systemFont(ofSize: 12)
        programButton = NSButton(title: "Program pedal",
                                 target: self, action: #selector(programPedal))
        programButton.bezelStyle = .rounded
        configRow = NSStackView(views: [configStatusLabel, programButton])
        configRow.orientation = .horizontal
        configRow.spacing = 12

        deviceSection = NSStackView(views: [deviceStatusLabel, configRow])
        deviceSection.orientation = .vertical
        deviceSection.alignment = .leading
        deviceSection.spacing = 4
        refreshDeviceStatus()

        let defaultHeader = makeHeader("Default action when no app rule matches")

        // Radio buttons sharing one action+superview auto-group into one selector.
        dictationRadio = NSButton(radioButtonWithTitle: "Start dictation",
                                  target: self, action: #selector(defaultRadioChanged))
        muteRadio = NSButton(radioButtonWithTitle: "Mute sound input",
                             target: self, action: #selector(defaultRadioChanged))
        noneRadio = NSButton(radioButtonWithTitle: "No action",
                             target: self, action: #selector(defaultRadioChanged))
        syncRadioState()
        let radioStack = NSStackView(views: [dictationRadio, muteRadio, noneRadio])
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 4

        let rulesHeader = makeHeader("App rules")
        let hint = NSTextField(labelWithString:
            "Press the pedal in an app below to send its shortcut. Other apps use the default action above.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

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
                                        defaultHeader, radioStack, makeSpacer(8),
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
        appCol.title = "Application"
        appCol.width = 320
        tableView.addTableColumn(appCol)

        let keyCol = NSTableColumn(identifier: .init("shortcut"))
        keyCol.title = "Shortcut"
        keyCol.width = 180
        tableView.addTableColumn(keyCol)
    }

    // MARK: Actions

    private func refreshDeviceStatus() {
        guard let detected = FootswitchHIDController.detect() else {
            // No device: row 1 says so, row 2 hidden entirely.
            deviceStatusLabel.attributedStringValue = statusLine("⊘", "No supported foot switch detected", .secondaryLabelColor)
            configRow.isHidden = true
            return
        }
        deviceStatusLabel.attributedStringValue =
            statusLine("✓", "Detected pedal: \(detected.device.name)", .systemGreen)
        configRow.isHidden = false

        let expected = KeyCombo(modifiers: [], key: baseConfig.triggerKey)
        switch FootswitchHIDController.verifyConfiguration(expected: expected) {
        case .verified:
            configStatusLabel.attributedStringValue =
                statusLine("✓", "Verified configuration", .systemGreen)
            programButton.isHidden = true
        case .mismatch:
            configStatusLabel.attributedStringValue =
                statusLine("⚠", "Configuration must be updated", .systemYellow)
            programButton.isHidden = false
            programButton.isEnabled = true
        case .unreadable:
            configStatusLabel.attributedStringValue =
                statusLine("✗", "Unable to read configuration", .systemRed)
            programButton.isHidden = true
        case .noDevice:
            configRow.isHidden = true
        }
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

    @objc private func programPedal() {
        let combo = KeyCombo(modifiers: [], key: baseConfig.triggerKey)
        do {
            try FootswitchHIDController.program(combo: combo)
            presentInfo("Programmed the foot switch to send \(baseConfig.triggerKey).")
        } catch {
            presentInfo("Could not program the foot switch.\n\n\(error)")
        }
        refreshDeviceStatus()
    }

    private func presentInfo(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Foot switch"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    @objc private func defaultRadioChanged() {
        if muteRadio.state == .on { defaultAction = .muteInput }
        else if noneRadio.state == .on { defaultAction = .none }
        else { defaultAction = .dictation }
        save()
    }

    private func syncRadioState() {
        dictationRadio.state = (defaultAction == .dictation) ? .on : .off
        muteRadio.state = (defaultAction == .muteInput) ? .on : .off
        noneRadio.state = (defaultAction == .none) ? .on : .off
    }

    @objc private func addRemoveClicked() {
        if addRemove.selectedSegment == 0 { addRule() } else { removeSelectedRule() }
    }

    private func addRule() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
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
        let action: Action = suggested.map { .keyCombo($0) }
            ?? .keyCombo(KeyCombo(modifiers: [], key: ""))

        rules.append(Rule(match: bundleID, appName: appName, action: action))
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
    fileprivate func updateShortcut(row: Int, combo: KeyCombo) {
        guard rules.indices.contains(row) else { return }
        rules[row].action = .keyCombo(combo)
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
            let name = NSTextField(labelWithString: rule.appName.isEmpty ? rule.match : rule.appName)
            let sub = NSTextField(labelWithString: rule.match)
            sub.font = .systemFont(ofSize: 10)
            sub.textColor = .secondaryLabelColor
            let text = NSStackView(views: [name, sub])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 0
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.addSubview(text)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            ])
            return cell

        case "shortcut":
            let capture = ShortcutCaptureView()
            if case .keyCombo(let combo) = rule.action, !combo.key.isEmpty {
                capture.combo = combo
            }
            capture.onCapture = { [weak self] combo in
                self?.updateShortcut(row: row, combo: combo)
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

        let mods = modifiers(from: event.modifierFlags)
        guard let keyName = Keymap.keyName(forCode: event.keyCode) else {
            flashHint("Unsupported key")
            return nil
        }
        let isFunctionKey = keyName.uppercased().hasPrefix("F") && keyName.count >= 2
            && Int(keyName.dropFirst()) != nil

        // Require at least one modifier unless it's a function key.
        guard !mods.isEmpty || isFunctionKey else {
            flashHint("Add a modifier (⌘⌥⌃⇧)")
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
        let glyphs = mods.isEmpty ? "Press shortcut…"
            : KeyComboFormatter.display(KeyCombo(modifiers: mods, key: "")).trimmingCharacters(in: .whitespaces)
        label.stringValue = glyphs.isEmpty ? "Press shortcut…" : glyphs
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
            label.stringValue = "Press shortcut…"
            label.textColor = .secondaryLabelColor
        } else if let combo, !combo.key.isEmpty {
            label.stringValue = KeyComboFormatter.display(combo)
        } else {
            label.stringValue = "Click to set"
            label.textColor = .secondaryLabelColor
        }
    }
}
