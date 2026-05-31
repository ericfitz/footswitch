import Foundation

/// Renders a `KeyCombo` as a macOS-style modifier-glyph string for display in UI.
///
/// Modifiers are always emitted in the canonical Apple order: ⌃⌥⇧⌘,
/// regardless of the order stored in `combo.modifiers`. The key is uppercased.
///
/// Examples:
/// - `KeyCombo(modifiers: [.command], key: "D")` → `"⌘D"`
/// - `KeyCombo(modifiers: [.command, .shift], key: "a")` → `"⇧⌘A"`
/// - `KeyCombo(modifiers: [], key: "F13")` → `"F13"`
public enum KeyComboFormatter {
    private static let canonicalOrder: [(Modifier, String)] = [
        (.control, "⌃"),
        (.option,  "⌥"),
        (.shift,   "⇧"),
        (.command, "⌘"),
    ]

    public static func display(_ combo: KeyCombo) -> String {
        let glyphs = canonicalOrder
            .filter { combo.modifiers.contains($0.0) }
            .map { $0.1 }
            .joined()
        return glyphs + combo.key.uppercased()
    }
}
