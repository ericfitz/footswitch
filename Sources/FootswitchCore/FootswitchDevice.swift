import Foundation

/// A foot switch model this app recognizes, identified by USB vendor/product
/// ID. `program` is the protocol family (the original `footswitch` CLI uses
/// different report layouts per family). `.footswitch` (USB HID) and
/// `.footswitchBLE` (Bluetooth GATT) are the programmable families; the others
/// are detected but not yet programmable.
public struct SupportedDevice: Equatable, Sendable {
    public enum Program: String, Sendable { case footswitch, scythe, scythe2, footswitch1p, footswitchBLE }
    public let vendorID: Int
    public let productID: Int
    public let program: Program
    public let name: String

    public init(vendorID: Int, productID: Int, program: Program, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.program = program
        self.name = name
    }
}

public enum SupportedDevices {
    /// The recognized devices. IDs are decimal here; source table is hex.
    public static let all: [SupportedDevice] = [
        SupportedDevice(vendorID: 0x0c45, productID: 0x7403, program: .footswitch,   name: "PCsensor FootSwitch"),
        SupportedDevice(vendorID: 0x0c45, productID: 0x7404, program: .footswitch,   name: "PCsensor FootSwitch"),
        SupportedDevice(vendorID: 0x413d, productID: 0x2107, program: .footswitch,   name: "FootSwitch"),
        SupportedDevice(vendorID: 0x1a86, productID: 0xe026, program: .footswitch,   name: "FootSwitch"),
        SupportedDevice(vendorID: 0x3553, productID: 0xb001, program: .footswitch,   name: "PCsensor FootSwitch"),
        SupportedDevice(vendorID: 0x3553, productID: 0xc100, program: .footswitch,   name: "PCsensor FS17Pro"),
        SupportedDevice(vendorID: 0x245A, productID: 0x8276, program: .footswitchBLE, name: "PCsensor FS17Pro"),
        SupportedDevice(vendorID: 0x0426, productID: 0x3011, program: .scythe,       name: "Scythe FootSwitch"),
        SupportedDevice(vendorID: 0x055a, productID: 0x0998, program: .scythe2,      name: "Scythe FootSwitch II"),
        SupportedDevice(vendorID: 0x5131, productID: 0x2019, program: .footswitch1p, name: "FootSwitch 1P"),
    ]

    public static func match(vendorID: Int, productID: Int) -> SupportedDevice? {
        all.first { $0.vendorID == vendorID && $0.productID == productID }
    }
}

/// Left-side modifier bits used in the device's key report byte (data[2]).
/// Values come from the PCsensor protocol (CTRL=1, SHIFT=2, ALT=4, WIN=8).
public enum DeviceModifier {
    public static func bits(for modifiers: [Modifier]) -> UInt8 {
        var b: UInt8 = 0
        for m in modifiers {
            switch m {
            case .control: b |= 0x01
            case .shift:   b |= 0x02
            case .option:  b |= 0x04   // Option maps to ALT
            case .command: b |= 0x08   // Command maps to WIN/GUI
            }
        }
        return b
    }

    /// Reverse of `bits(for:)`. Treats left and right modifier bits as the same
    /// logical modifier (the device stores l_* in the low nibble, r_* in the high).
    public static func modifiers(fromBits bits: UInt8) -> [Modifier] {
        var result: [Modifier] = []
        if bits & (0x01 | 0x10) != 0 { result.append(.control) }
        if bits & (0x04 | 0x40) != 0 { result.append(.option) }
        if bits & (0x02 | 0x20) != 0 { result.append(.shift) }
        if bits & (0x08 | 0x80) != 0 { result.append(.command) }
        return result
    }
}

/// Maps a key name to its USB HID Usage ID (Keyboard/Keypad page). This is the
/// numbering the foot switch firmware stores — distinct from the macOS virtual
/// key codes in `Keymap`. Returns nil for keys not in the table.
public enum HIDUsage {
    private static let table: [String: UInt8] = [
        "A": 0x04, "B": 0x05, "C": 0x06, "D": 0x07, "E": 0x08, "F": 0x09,
        "G": 0x0a, "H": 0x0b, "I": 0x0c, "J": 0x0d, "K": 0x0e, "L": 0x0f,
        "M": 0x10, "N": 0x11, "O": 0x12, "P": 0x13, "Q": 0x14, "R": 0x15,
        "S": 0x16, "T": 0x17, "U": 0x18, "V": 0x19, "W": 0x1a, "X": 0x1b,
        "Y": 0x1c, "Z": 0x1d,
        "1": 0x1e, "2": 0x1f, "3": 0x20, "4": 0x21, "5": 0x22, "6": 0x23,
        "7": 0x24, "8": 0x25, "9": 0x26, "0": 0x27,
        "RETURN": 0x28, "ENTER": 0x28, "ESCAPE": 0x29, "ESC": 0x29,
        "BACKSPACE": 0x2a, "TAB": 0x2b, "SPACE": 0x2c,
        "F1": 0x3a, "F2": 0x3b, "F3": 0x3c, "F4": 0x3d, "F5": 0x3e, "F6": 0x3f,
        "F7": 0x40, "F8": 0x41, "F9": 0x42, "F10": 0x43, "F11": 0x44, "F12": 0x45,
        "F13": 0x68, "F14": 0x69, "F15": 0x6a, "F16": 0x6b, "F17": 0x6c,
        "F18": 0x6d, "F19": 0x6e, "F20": 0x6f,
    ]

    public static func usage(for name: String) -> UInt8? {
        table[name.uppercased()]
    }

    /// Canonical names for usage codes that have multiple aliases in the table,
    /// so reverse lookup round-trips through `usage(for:)` and reads well.
    private static let canonicalNames: [UInt8: String] = [
        0x28: "Return", 0x29: "Escape", 0x2c: "Space",
    ]

    /// Reverse lookup: HID usage ID -> a key name accepted by `usage(for:)`.
    public static func name(forUsage usage: UInt8) -> String? {
        if let canonical = canonicalNames[usage] { return canonical }
        return table.first(where: { $0.value == usage })?.key
    }
}

/// Builds the 8-byte HID reports that program a single-pedal foot switch to emit
/// the given key combo on press. Pure (returns bytes); the actual USB writes live
/// in the app target. Report layout (PCsensor `footswitch` family):
///   start  = [0x01,0x80,0x08,0,0,0,0,0]
///   header = [0x01,0x81,0x08, pedalIndex+1, 0,0,0,0]
///   data   = [0x08, KEY_TYPE(=1), modifierBits, hidUsage, 0,0,0,0]
public enum FootswitchProgram {
    public static let start: [UInt8] = [0x01, 0x80, 0x08, 0, 0, 0, 0, 0]

    /// Query report to read back a pedal's stored config (PCsensor protocol):
    /// [0x01,0x82,0x08, pedalIndex+1, 0,0,0,0].
    public static func queryReport(pedalIndex: Int) -> [UInt8] {
        [0x01, 0x82, 0x08, UInt8(pedalIndex + 1), 0, 0, 0, 0]
    }

    /// Outcome of reading a pedal's stored configuration.
    public enum StoredConfig: Equatable, Sendable {
        case unconfigured
        case key(KeyCombo)
        case other          // mouse / string / combo — not a plain key
    }

    /// Parses an 8-byte query response. response[1] is the type (0=unconfigured,
    /// 1 or 0x81 = key), response[2] is modifier bits, response[3] is the HID
    /// usage byte. Returns `.other` for non-key configurations.
    public static func parseKeyResponse(_ r: [UInt8]) -> StoredConfig {
        guard r.count >= 4 else { return .other }
        switch r[1] {
        case 0:
            return .unconfigured
        case 1, 0x81:
            let mods = DeviceModifier.modifiers(fromBits: r[2])
            guard let key = HIDUsage.name(forUsage: r[3]) else { return .other }
            return .key(KeyCombo(modifiers: mods, key: key))
        default:
            return .other
        }
    }

    /// Reports to write a key combo to pedal `index` (0-based). Returns the
    /// header followed by the data report, or nil if the key is unknown.
    public static func keyReports(pedalIndex: Int, combo: KeyCombo) -> (header: [UInt8], data: [UInt8])? {
        guard let usage = HIDUsage.usage(for: combo.key) else { return nil }
        let header: [UInt8] = [0x01, 0x81, 0x08, UInt8(pedalIndex + 1), 0, 0, 0, 0]
        let keyType: UInt8 = 1
        let data: [UInt8] = [0x08, keyType, DeviceModifier.bits(for: combo.modifiers), usage, 0, 0, 0, 0]
        return (header, data)
    }
}

/// Logical pedal/button slots. 1-based to match `TriggerKey.slot` ("1 = first
/// button"). Convert to the wire's 0-based `pedalIndex` with `slot - 1`.
public enum Slot {
    public static let maxCount = 3
    public static let validRange = 1...maxCount
    public static func isValid(_ slot: Int) -> Bool { validRange.contains(slot) }
}
