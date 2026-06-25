import AppKit
import FootswitchCore

// MARK: - Settings view: UI construction

extension SettingsViewController {
    /// Assembles the settings pane from per-section builders. Each builder creates
    /// its controls (stashing the ones the controller keeps as properties) and
    /// returns the ordered views; this method only stacks them and pins the layout.
    func buildUI() {
        // Wrapping hints can't bind their width until they share an ancestor with
        // the stack, so collect them and activate after the stack is installed.
        var wrappingHints: [NSTextField] = []

        let deviceViews = makeDeviceSection()
        let generalViews = makeGeneralSection(wrappingHints: &wrappingHints)
        let defaultViews = makeDefaultActionSection()
        let (rulesViews, scroll) = makeRulesSection(wrappingHints: &wrappingHints)

        let stack = NSStackView(views: deviceViews + [makeSpacer(8)]
            + generalViews + [makeSpacer(8)]
            + defaultViews + [makeSpacer(8)]
            + rulesViews)
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
        // Bound each hint's width so a long localized string wraps to a second line
        // instead of stretching the layout.
        for hint in wrappingHints {
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
    }

    /// Device section: row 1 = detection (+ info button), row 2 = config status with
    /// Program/Test. Per-slot rows for multi-pedal devices are added later, on detect.
    private func makeDeviceSection() -> [NSView] {
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
        return [deviceHeader, deviceSection]
    }

    /// General app options: launch at login (OS-owned state, not in Config).
    private func makeGeneralSection(wrappingHints: inout [NSTextField]) -> [NSView] {
        let generalHeader = makeHeader(L10n.settingsHeaderGeneral)
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: L10n.settingsLaunchAtLoginCheckbox,
                                         target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
        launchAtLoginHint = makeWrappingHint(L10n.settingsLaunchAtLoginApprovalHint)
        // Only shown when macOS is waiting on the user to approve the login item.
        launchAtLoginHint.isHidden = !LoginItem.requiresApproval
        wrappingHints.append(launchAtLoginHint)
        return [generalHeader, launchAtLoginCheckbox, launchAtLoginHint]
    }

    /// Default-action section: the single "start dictation when no rule matches" toggle.
    private func makeDefaultActionSection() -> [NSView] {
        let defaultHeader = makeHeader(L10n.settingsHeaderDefault)
        dictationCheckbox = NSButton(checkboxWithTitle: L10n.settingsDictationCheckbox,
                                     target: self, action: #selector(dictationCheckboxChanged))
        dictationCheckbox.state = (defaultAction == .dictation) ? .on : .off
        return [defaultHeader, dictationCheckbox]
    }

    /// Rules section: header, hint, the table in a scroll view, the +/- bar, and the
    /// Shortcut-permission note. Returns the ordered views plus the scroll view so the
    /// caller can pin its size.
    private func makeRulesSection(wrappingHints: inout [NSTextField]) -> (views: [NSView], scroll: NSScrollView) {
        let rulesHeader = makeHeader(L10n.settingsHeaderRules)
        // Wrap (don't widen the window) when the localized hint is long, e.g. German.
        let hint = makeWrappingHint(L10n.settingsRulesHint)
        wrappingHints.append(hint)
        // One-line note that macOS may prompt the first time a Shortcut runs.
        let shortcutHint = makeWrappingHint(L10n.settingsShortcutPermissionHint)
        wrappingHints.append(shortcutHint)

        configureTable()
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        // Safety net (issue #11): if the window is narrowed past the point where the
        // app column can absorb it, scroll horizontally rather than clip the mapping.
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        configureAddRemoveBar()
        return ([rulesHeader, hint, scroll, addRemove, shortcutHint], scroll)
    }

    /// The native +/- segmented control beneath the rules table.
    private func configureAddRemoveBar() {
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
    }

    /// A secondary, two-line wrapping label — the shared style for the inline hints.
    private func makeWrappingHint(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
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
    func rebuildShortcutColumns() {
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
    func fitShortcutColumns() {
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

}
