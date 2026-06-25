import AppKit
import FootswitchCore

// MARK: - Settings view: rule editing & general options

extension SettingsViewController {
    @objc func launchAtLoginChanged() {
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

    @objc func dictationCheckboxChanged() {
        defaultAction = (dictationCheckbox.state == .on) ? .dictation : .none
        save()
    }

    @objc func addRemoveClicked() {
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

    func updateRemoveEnabled() {
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

    func save() {
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
