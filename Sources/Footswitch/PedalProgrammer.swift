import Foundation
import FootswitchCore

/// Result of reading and verifying a connected pedal's stored configuration.
/// Supersedes the former USB-only verification enum; the Settings UI is unchanged.
enum PedalVerification {
    case noDevice
    case verified      // stored key matches expected
    case mismatch      // read OK but configured differently
    case unreadable    // device present but config read failed
}

/// Transport-agnostic programming interface. A concrete programmer targets a single
/// connected device over one transport (USB HID or BLE GATT) and drives the shared
/// `FootswitchProgram` / `BLEProgramPayload` report bytes.
protocol PedalProgrammer {
    /// Human-readable model name of the device this programmer targets.
    var deviceName: String { get }
    /// Reads slot `slot`'s (1-based) stored config; nil if it could not be read.
    func readStoredConfig(slot: Int) -> FootswitchProgram.StoredConfig?
    /// Programs slot `slot` (1-based) to emit `combo` on press. Throws on failure.
    func program(combo: KeyCombo, slot: Int) throws
    /// A human-readable, read-only info report (USB identity / model / stored key).
    func info() -> String
}

extension PedalProgrammer {
    /// Default verification for `slot` (1-based): read its stored config, compare.
    func verify(expected: KeyCombo, slot: Int) -> PedalVerification {
        guard let stored = readStoredConfig(slot: slot) else { return .unreadable }
        switch stored {
        case .key(let combo): return combo.matchesTrigger(expected) ? .verified : .mismatch
        case .unconfigured, .other: return .mismatch
        }
    }

    // Slot-1 conveniences so single-pedal callsites stay unchanged.
    func readStoredConfig() -> FootswitchProgram.StoredConfig? { readStoredConfig(slot: 1) }
    func program(combo: KeyCombo) throws { try program(combo: combo, slot: 1) }
    func verify(expected: KeyCombo) -> PedalVerification { verify(expected: expected, slot: 1) }
}
