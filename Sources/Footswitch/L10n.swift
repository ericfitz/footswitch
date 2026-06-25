import Foundation

// Each accessor is a deliberate one-liner pairing a key with its inline translator
// note; wrapping them would hurt readability more than the line length does.
// swiftlint:disable line_length

/// Central catalog of every user-facing string. Each property/function is the one
/// place a key is defined; the `comment:` is the authoritative translator note,
/// mirrored as a /* */ header in every Localizable.strings file. Values resolve
/// from Bundle.main (Contents/Resources/<lang>.lproj), populated by the packaging
/// scripts. Unpackaged `swift run` falls back to the key (no .lproj present).
enum L10n {
    private static func t(_ key: String, _ comment: String) -> String {
        NSLocalizedString(key, comment: comment)
    }

    // Menu
    static var menuAbout: String { t("menu.about", "Menu item: open the About window.") }
    static var menuSettings: String { t("menu.settings", "Menu item: open the Settings window.") }
    static var menuQuit: String { t("menu.quit", "Menu item: quit the application entirely.") }
    static var menuNeedsPermission: String { t("menu.needsPermission", "Menu warning when Accessibility permission is missing.") }
    static var menuNoPresses: String { t("menu.noPresses", "Menu line before any pedal press.") }
    /// %1$@ = app name, %2$@ = action description.
    static func menuLastFire(app: String, action: String) -> String {
        String(format: t("menu.lastFire", "Menu line for the most recent press. %1$@ app, %2$@ action."), app, action)
    }

    /// %1$@ = app name, %2$@ = pedal label (e.g. "Pedal 2"), %3$@ = action.
    static func menuLastFireSlot(app: String, slot: String, action: String) -> String {
        String(format: t("menu.lastFireSlot",
            "Menu line for the most recent press identifying the pedal. %1$@ app, %2$@ pedal, %3$@ action."),
            app, slot, action)
    }

    /// %@ = pedal number, e.g. "Pedal 2". Reused for menu + settings rows/columns.
    static func deviceSlotLabel(_ number: Int) -> String {
        String(format: t("device.slotLabel", "Label for one pedal slot. %@ is the pedal number."), "\(number)")
    }

    // Action descriptions
    static var actionDictation: String { t("action.dictation", "Action: starts dictation.") }
    static var actionNone: String { t("action.none", "Action: pedal does nothing.") }
    static var appUnknown: String { t("app.unknown", "Unknown frontmost app name.") }

    // Settings
    static var settingsWindowTitle: String { t("settings.windowTitle", "Settings window title.") }
    static var settingsHeaderDevice: String { t("settings.header.device", "Settings header: device.") }
    static var settingsHeaderDefault: String { t("settings.header.default", "Settings header: default action.") }
    static var settingsHeaderRules: String { t("settings.header.rules", "Settings header: app rules.") }
    static var settingsHeaderGeneral: String { t("settings.header.general", "Settings header: general app options.") }
    static var settingsLaunchAtLoginCheckbox: String { t("settings.launchAtLoginCheckbox", "Settings checkbox: launch the app automatically at login.") }
    static var settingsLaunchAtLoginApprovalHint: String { t("settings.launchAtLoginApprovalHint", "Settings hint: macOS requires the user to approve the login item in System Settings.") }
    static var settingsDictationCheckbox: String { t("settings.dictationCheckbox", "Settings checkbox: dictation fallback.") }
    static var settingsRulesHint: String { t("settings.rulesHint", "Settings hint below rules table.") }
    static var settingsProgramButton: String { t("settings.programButton", "Button: program the pedal.") }
    static var settingsColApplication: String { t("settings.col.application", "Rules column header: application.") }
    static var settingsColAction: String { t("settings.col.action", "Rules column header: action (key sequence or Shortcut).") }

    // Per-rule action kind + Shortcuts.app picker
    static var settingsActionKindKeySequence: String { t("settings.actionKind.keySequence", "Action-kind popup item: send a key sequence.") }
    static var settingsActionKindShortcut: String { t("settings.actionKind.shortcut", "Action-kind popup item: run a Shortcuts.app shortcut.") }
    static var settingsShortcutChoose: String { t("settings.shortcut.choose", "Placeholder in the Shortcut picker before one is chosen.") }
    static var settingsShortcutNone: String { t("settings.shortcut.none", "Disabled item shown when no Shortcuts are installed.") }
    /// %@ = stored shortcut name.
    static func settingsShortcutNotInstalled(name: String) -> String {
        String(format: t("settings.shortcut.notInstalled", "Shortcut picker item for a stored shortcut no longer installed. %@ = stored name."), name)
    }
    static var settingsShortcutPermissionHint: String { t("settings.shortcut.permissionHint", "Hint under the rules table: macOS may prompt the first time a Shortcut runs.") }

    /// %@ = pedal number. Rules-table shortcut column header for one pedal.
    static func settingsColPedalShortcut(_ number: Int) -> String {
        String(format: t("settings.col.pedalShortcut",
            "Rules column header for one pedal's shortcut. %@ is the pedal number."), "\(number)")
    }

    // Device status
    static var deviceNone: String { t("device.none", "Device status: none detected.") }
    /// %@ = device name.
    static func deviceDetected(name: String) -> String {
        String(format: t("device.detected", "Device status: detected. %@ name."), name)
    }
    /// %1$@ = device name, %2$@ = pedal count. Shown when >1 pedal detected.
    static func deviceDetectedSlots(name: String, count: Int) -> String {
        String(format: t("device.detectedSlots",
            "Device status with pedal count. %1$@ name, %2$@ count."), name, "\(count)")
    }
    static var deviceConfigVerified: String { t("device.config.verified", "Config status: verified.") }
    static var deviceConfigStoredBluetooth: String { t("device.config.storedBluetooth", "Config status: stored over Bluetooth; power-cycle to apply.") }
    static var deviceConfigMismatch: String { t("device.config.mismatch", "Config status: must update.") }
    static var deviceConfigUnreadable: String { t("device.config.unreadable", "Config status: unreadable.") }

    // Alerts
    static var alertDeviceInfoTitle: String { t("alert.deviceInfo.title", "Device-info alert title.") }
    static var alertDeviceInfoNone: String { t("alert.deviceInfo.none", "Device-info alert: no device.") }
    static var alertFootswitchTitle: String { t("alert.footswitch.title", "Generic foot switch alert title.") }
    /// %@ = key name.
    static func alertProgrammed(key: String) -> String {
        String(format: t("alert.programmed", "Alert: programmed. %@ key."), key)
    }
    /// %@ = key name. Shown after programming over Bluetooth: the key is stored but
    /// the FS17Pro only applies it after a physical power-cycle.
    static func alertProgrammedBluetooth(key: String) -> String {
        String(format: t("alert.programmed.bluetooth", "Alert: programmed over Bluetooth; power-cycle to apply. %@ key."), key)
    }
    /// %@ = error detail.
    static func alertProgramFailed(error: String) -> String {
        String(format: t("alert.programFailed", "Alert: programming failed. %@ error."), error)
    }
    static var alertOK: String { t("alert.ok", "Generic OK button.") }
    static var alertLaunchAtLoginTitle: String { t("alert.launchAtLogin.title", "Alert title when toggling launch-at-login fails.") }
    /// %@ = error detail.
    static func alertLaunchAtLoginFailed(error: String) -> String {
        String(format: t("alert.launchAtLogin.failed", "Alert: launch-at-login change failed. %@ error."), error)
    }

    // Open panel
    static var openPanelTitle: String { t("openPanel.title", "Open panel title for choosing an app.") }

    // Shortcut capture
    static var captureClickToSet: String { t("capture.clickToSet", "Capture: before a shortcut is set.") }
    static var capturePressShortcut: String { t("capture.pressShortcut", "Capture: while recording.") }
    static var captureUnsupportedKey: String { t("capture.unsupportedKey", "Capture: unsupported key.") }
    static var captureAddModifier: String { t("capture.addModifier", "Capture: modifier required.") }

    // Pedal test (issue #6)
    static var settingsTestButton: String { t("settings.testButton", "Button: test what key the pedal emits.") }
    static var alertTestTitle: String { t("alert.test.title", "Test-pedal alert title.") }
    /// %@ = pedal number.
    static func testPrompt(slot: Int) -> String {
        String(format: t("test.prompt", "Armed prompt while waiting for a pedal press. %@ = pedal number."), "\(slot)")
    }
    /// %@ = key name.
    static func testMatch(key: String) -> String {
        String(format: t("test.match", "Result: emitted key matches config. %@ = key."), key)
    }
    /// %1$@ = emitted key, %2$@ = expected key.
    static func testMismatch(captured: String, expected: String) -> String {
        String(format: t("test.mismatch", "Result: emitted key differs. %1$@ emitted, %2$@ expected."), captured, expected)
    }
    /// %1$@ = raw key code, %2$@ = expected key.
    static func testUnknown(code: String, expected: String) -> String {
        String(format: t("test.unknown", "Result: emitted an unrecognized key. %1$@ code, %2$@ expected."), code, expected)
    }
    static var testNoKey: String { t("test.noKey", "Result: nothing captured (timeout/cancel).") }
    /// %@ = key to adopt.
    static func testUseKey(key: String) -> String {
        String(format: t("test.useKey", "Button: adopt the emitted key into config. %@ = key."), key)
    }
    /// %@ = expected key to program.
    static func testReprogram(key: String) -> String {
        String(format: t("test.reprogram", "Button: reprogram device to the configured key. %@ = key."), key)
    }
    static var alertCancel: String { t("alert.cancel", "Generic Cancel button.") }

    // About
    static var aboutWindowTitle: String { t("about.windowTitle", "About window title.") }
    static var aboutDescription: String { t("about.description", "About window description.") }
    /// %1$@ = short version, %2$@ = commit hash.
    static func aboutVersion(version: String, commit: String) -> String {
        String(format: t("about.version", "About version line. %1$@ version, %2$@ commit."), version, commit)
    }
    static var aboutCopyright: String { t("about.copyright", "About copyright line.") }
    static var aboutViewOnGitHub: String { t("about.viewOnGitHub", "About link: GitHub repo.") }
    static var aboutReportProblem: String { t("about.reportProblem", "About link: report a problem.") }
    static var aboutLicense: String { t("about.license", "About link: license.") }
}
