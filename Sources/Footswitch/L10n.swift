import Foundation

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

    // Action descriptions
    static var actionDictation: String { t("action.dictation", "Action: starts dictation.") }
    static var actionNone: String { t("action.none", "Action: pedal does nothing.") }
    static var appUnknown: String { t("app.unknown", "Unknown frontmost app name.") }

    // Settings
    static var settingsWindowTitle: String { t("settings.windowTitle", "Settings window title.") }
    static var settingsHeaderDevice: String { t("settings.header.device", "Settings header: device.") }
    static var settingsHeaderDefault: String { t("settings.header.default", "Settings header: default action.") }
    static var settingsHeaderRules: String { t("settings.header.rules", "Settings header: app rules.") }
    static var settingsDictationCheckbox: String { t("settings.dictationCheckbox", "Settings checkbox: dictation fallback.") }
    static var settingsRulesHint: String { t("settings.rulesHint", "Settings hint below rules table.") }
    static var settingsProgramButton: String { t("settings.programButton", "Button: program the pedal.") }
    static var settingsColApplication: String { t("settings.col.application", "Rules column header: application.") }
    static var settingsColShortcut: String { t("settings.col.shortcut", "Rules column header: shortcut.") }

    // Device status
    static var deviceNone: String { t("device.none", "Device status: none detected.") }
    /// %@ = device name.
    static func deviceDetected(name: String) -> String {
        String(format: t("device.detected", "Device status: detected. %@ name."), name)
    }
    static var deviceConfigVerified: String { t("device.config.verified", "Config status: verified.") }
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
    /// %@ = error detail.
    static func alertProgramFailed(error: String) -> String {
        String(format: t("alert.programFailed", "Alert: programming failed. %@ error."), error)
    }
    static var alertOK: String { t("alert.ok", "Generic OK button.") }

    // Open panel
    static var openPanelTitle: String { t("openPanel.title", "Open panel title for choosing an app.") }

    // Shortcut capture
    static var captureClickToSet: String { t("capture.clickToSet", "Capture: before a shortcut is set.") }
    static var capturePressShortcut: String { t("capture.pressShortcut", "Capture: while recording.") }
    static var captureUnsupportedKey: String { t("capture.unsupportedKey", "Capture: unsupported key.") }
    static var captureAddModifier: String { t("capture.addModifier", "Capture: modifier required.") }

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
