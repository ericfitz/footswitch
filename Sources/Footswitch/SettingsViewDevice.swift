import AppKit
import FootswitchCore

// MARK: - Settings view: device detection, programming & testing

extension SettingsViewController {
    func refreshDeviceStatus() {
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

    @objc func showDeviceInfo() {
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

    @objc func programPedal() { programSlot(1, button: programButton) }

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

    @objc func testPedal() { startTest(slot: 1) }

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
}
