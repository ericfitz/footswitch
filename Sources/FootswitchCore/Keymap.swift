import Foundation

/// Maps key names to macOS virtual key codes, and modifiers to CGEventFlags bits.
/// Bits match Apple's CGEventFlags (maskShift=0x20000, maskControl=0x40000,
/// maskAlternate=0x80000, maskCommand=0x100000). Kept as raw UInt64 so this
/// type has no AppKit/CoreGraphics dependency and stays unit-testable.
public enum Keymap {
    private static let table: [String: UInt16] = [
        // Letters (ANSI virtual key codes)
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
        "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
        "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "O": 0x1F,
        "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28,
        "N": 0x2D, "M": 0x2E,
        // Digits
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16,
        "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        // Named keys
        "RETURN": 0x24, "ENTER": 0x24, "TAB": 0x30, "SPACE": 0x31,
        "ESCAPE": 0x35, "ESC": 0x35, "DELETE": 0x33, "BACKSPACE": 0x33,
        // Function keys
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60,
        "F6": 0x61, "F7": 0x62, "F8": 0x64, "F9": 0x65, "F10": 0x6D,
        "F11": 0x67, "F12": 0x6F, "F13": 0x69, "F14": 0x6B, "F15": 0x71,
        "F16": 0x6A, "F17": 0x40, "F18": 0x4F, "F19": 0x50, "F20": 0x5A,
    ]

    public static func keyCode(for name: String) -> UInt16? {
        table[name.uppercased()]
    }

    /// Canonical names preferred when a virtual key code maps to several aliases
    /// (e.g. 0x24 is both RETURN and ENTER). Used by reverse lookup so the result
    /// round-trips cleanly through `keyCode(for:)` and reads well in the UI.
    private static let canonicalNames: [UInt16: String] = [
        0x24: "Return", 0x30: "Tab", 0x31: "Space",
        0x35: "Escape", 0x33: "Delete",
    ]

    /// Reverse lookup: virtual key code -> a key name accepted by `keyCode(for:)`.
    /// Prefers a canonical name for codes with multiple aliases; otherwise returns
    /// the (single) matching table entry. Returns nil for codes not in the table.
    public static func keyName(forCode code: UInt16) -> String? {
        if let canonical = canonicalNames[code] {
            return canonical
        }
        return table.first(where: { $0.value == code })?.key
    }

    public static func flagBits(for modifiers: [Modifier]) -> UInt64 {
        var bits: UInt64 = 0
        for m in modifiers {
            switch m {
            case .shift:   bits |= 0x20000
            case .control: bits |= 0x40000
            case .option:  bits |= 0x80000
            case .command: bits |= 0x100000
            }
        }
        return bits
    }

    /// The four modifier flag bits a foot switch can emit (⌃⌥⇧⌘). Mask a raw
    /// CGEventFlags value with this to drop Caps Lock / fn / numeric-pad bits that
    /// must not affect trigger matching.
    public static let deviceModifierMask: UInt64 = 0x20000 | 0x40000 | 0x80000 | 0x100000

    /// Reverse of `flagBits(for:)`: the `Modifier`s encoded in a CGEventFlags bit
    /// field, in canonical order (control, option, shift, command) so the result
    /// compares equal to config / device-read-back modifier arrays.
    public static func modifiers(forFlagBits bits: UInt64) -> [Modifier] {
        var mods: [Modifier] = []
        if bits & 0x40000  != 0 { mods.append(.control) }
        if bits & 0x80000  != 0 { mods.append(.option) }
        if bits & 0x20000  != 0 { mods.append(.shift) }
        if bits & 0x100000 != 0 { mods.append(.command) }
        return mods
    }
}
