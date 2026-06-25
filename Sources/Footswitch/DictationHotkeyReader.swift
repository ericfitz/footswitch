import Foundation
import FootswitchCore

/// Reads the user's current macOS Dictation hotkey from the
/// `com.apple.symbolichotkeys` preference domain (entry **164**) and decodes it
/// via `DictationHotkey`. This lives in the app target rather than FootswitchCore
/// because it touches live system preferences; the keycode/modifier translation
/// it delegates to is unit-tested in the core (#15).
enum DictationHotkeyReader {
    /// symbolichotkeys dictionary key for the Dictation toggle hotkey.
    private static let dictationEntry = "164"

    /// Resolves the system's Dictation hotkey. Uses `CFPreferencesCopyAppValue`
    /// (rather than `UserDefaults`) so we read through `cfprefsd` and see the
    /// value even though the domain isn't ours.
    static func systemResolution() -> DictationHotkey.Resolution {
        guard let raw = CFPreferencesCopyAppValue(
                "AppleSymbolicHotKeys" as CFString,
                "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = raw[dictationEntry] as? [String: Any] else {
            return .absent
        }

        let enabled: Bool = {
            if let b = entry["enabled"] as? Bool { return b }
            if let n = entry["enabled"] as? Int { return n != 0 }
            return false
        }()

        let parameters = ((entry["value"] as? [String: Any])?["parameters"] as? [NSNumber])?
            .map { $0.intValue }

        return DictationHotkey.resolve(enabled: enabled, parameters: parameters)
    }
}
