import AppKit
import FootswitchCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var lastFireText = L10n.menuNoPresses
    private let openSettings: () -> Void
    private let openAbout: () -> Void

    init(openSettings: @escaping () -> Void, openAbout: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openAbout = openAbout
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "🦶"
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }

    func setLastFire(app: String?, slot: Int, action: ResolvedAction) {
        let appName = app ?? L10n.appUnknown
        lastFireText = L10n.menuLastFireSlot(
            app: appName, slot: L10n.deviceSlotLabel(slot), action: describe(action))
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }

    // Re-check permission each time the menu opens so the warning item clears
    // promptly after the user grants Accessibility (no need to wait for a press).
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }

    private func describe(_ action: ResolvedAction) -> String {
        switch action {
        case .keyCombo(let c): return KeyComboFormatter.display(c)
        case .dictation: return L10n.actionDictation
        case .shortcut(let ref): return ref.name
        case .none: return L10n.actionNone
        }
    }

    private func rebuildMenu(trusted: Bool) {
        let menu = NSMenu()
        if !trusted {
            let warn = NSMenuItem(title: L10n.menuNeedsPermission,
                                  action: #selector(grantPermission), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: lastFireText, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let about = NSMenuItem(title: L10n.menuAbout,
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let settings = NSMenuItem(title: L10n.menuSettings,
                                  action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: L10n.menuQuit,
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Power glyph (⏻) via the SF Symbol so it renders crisply and tracks the
        // menu text color, instead of embedding the raw character in the title.
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func grantPermission() {
        PermissionsManager.requestTrust()
        PermissionsManager.openAccessibilitySettings()
    }

    @objc private func showSettings() { openSettings() }
    @objc private func showAbout() { openAbout() }
}
