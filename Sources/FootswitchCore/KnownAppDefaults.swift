import Foundation

/// A static lookup of well-known app bundle IDs to suggested mute/unmute `KeyCombo` shortcuts.
///
/// The table value is `KeyCombo?` — a key present with `nil` means "recognized app but the
/// shortcut must be captured by the user" (e.g. apps that vary by version or have no standard
/// default). A key absent entirely means the app is unknown to this table.
///
/// Note: Google Meet runs as a Progressive Web App whose bundle ID is machine-specific
/// (e.g. `com.google.Chrome.app.<hash>`), so only generic Chrome is seeded here. Users add
/// the Meet PWA via the app picker, which captures the correct bundle ID at that time.
public enum KnownAppDefaults {
    // swiftlint:disable:next discouraged_optional_collection
    private static let table: [String: KeyCombo?] = [
        // Apps with a well-known default shortcut
        "us.zoom.xos":            KeyCombo(modifiers: [.command, .shift], key: "A"),
        "com.microsoft.teams2":   KeyCombo(modifiers: [.command, .shift], key: "M"),
        "com.microsoft.teams":    KeyCombo(modifiers: [.command, .shift], key: "M"),
        "com.google.Chrome":      KeyCombo(modifiers: [.command],         key: "D"),

        // Known apps — user must capture their own shortcut
        "com.apple.FaceTime":     nil,
        "com.microsoft.VSCode":   nil,
        "com.apple.dt.Xcode":     nil,
        "com.apple.Terminal":     nil,
        "com.googlecode.iterm2":  nil,
    ]

    /// Returns the suggested `KeyCombo` for the given bundle ID, or `nil` if the app is
    /// unknown OR is known but has no seeded shortcut (the user must capture it).
    public static func suggestedShortcut(forBundleID id: String) -> KeyCombo? {
        return table[id] ?? nil
    }

    /// Returns `true` if the bundle ID is recognized in the seed table, regardless of whether
    /// a shortcut is seeded. Use this to distinguish "known app, no shortcut" from "unknown app".
    public static func isKnown(bundleID id: String) -> Bool {
        return table.keys.contains(id)
    }
}
