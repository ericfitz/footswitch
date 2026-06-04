import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for "launch at login". macOS 13+
/// registers the app itself as a login item (no separate helper bundle needed),
/// surviving relaunch and visible to the user in System Settings → General →
/// Login Items. State is owned by the OS, not by `Config`, so it is read and
/// written directly here rather than persisted in `~/.footswitch/config.json`.
enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    /// `.enabled` ⇒ on; any other status (`.notRegistered`, `.requiresApproval`,
    /// `.notFound`) ⇒ treated as off for the checkbox's purposes.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Returns the resulting
    /// enabled state (re-read from the service) so the caller can reconcile the
    /// checkbox with what actually took effect. Throws if the OS rejects the
    /// (un)registration so the caller can surface it.
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        let service = SMAppService.mainApp
        if enabled {
            // register() is idempotent; calling it while already enabled is fine.
            try service.register()
        } else {
            // Unregistering when not registered throws on some OS versions; guard.
            if service.status == .enabled {
                try service.unregister()
            }
        }
        return service.status == .enabled
    }

    /// True when the user must approve the login item in System Settings before
    /// it takes effect (macOS may defer a fresh registration to user approval).
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
