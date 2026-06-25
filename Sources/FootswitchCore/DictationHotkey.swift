import Foundation

/// Decodes the macOS Dictation hotkey that the system stores in
/// `com.apple.symbolichotkeys` (entry **164**) into something the app can act on.
///
/// This type is pure value logic — the live preference read lives in the app
/// target (`DictationHotkeyReader`) — so the fiddly keycode/modifier translation
/// stays unit-testable without touching system defaults (#15).
public enum DictationHotkey {
    /// The outcome of interpreting the system's Dictation hotkey entry.
    public enum Resolution: Equatable {
        /// A single key combo we can synthesize as a keystroke.
        case combo(KeyCombo)
        /// The shortcut exists but cannot be sent as a keystroke — e.g. a
        /// "press a modifier key twice" double-press, or a keycode we can't map.
        /// Callers should fall back *and* surface this to the user.
        case unsynthesizable
        /// No usable entry (missing, disabled, or malformed). Callers should fall
        /// back to their configured default silently.
        case absent
    }

    /// Sentinel keycode macOS writes for modifier-only "press twice" shortcuts
    /// (e.g. press Control twice). There is no key to synthesize for these.
    private static let doublePressKeyCode = 0xFFFF

    /// Interprets a symbolichotkeys entry.
    ///
    /// - Parameters:
    ///   - enabled: the entry's `enabled` flag. A disabled shortcut is `.absent`.
    ///   - parameters: the entry's `[asciiChar, keyCode, modifierMask]` triple.
    ///     The modifier mask uses NSEvent/Cocoa bits (shift `1<<17` … command
    ///     `1<<20`) — the same bit layout `Keymap` already understands, so the
    ///     Caps Lock / fn / numeric-pad bits are masked off.
    public static func resolve(enabled: Bool, parameters: [Int]?) -> Resolution {
        guard enabled else { return .absent }
        guard let p = parameters, p.count >= 3 else { return .absent }
        let keyCode = p[1]
        let modifierMask = p[2]

        // Modifier-only double-press (e.g. "press Control twice"), or a keycode
        // outside the virtual-keycode range: not a synthesizable keystroke.
        guard keyCode != doublePressKeyCode, keyCode >= 0, keyCode <= Int(UInt16.max),
              let key = Keymap.keyName(forCode: UInt16(keyCode)) else {
            return .unsynthesizable
        }

        let masked = UInt64(modifierMask < 0 ? 0 : modifierMask) & Keymap.deviceModifierMask
        return .combo(KeyCombo(modifiers: Keymap.modifiers(forFlagBits: masked), key: key))
    }
}
