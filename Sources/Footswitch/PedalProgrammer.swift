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
    /// Reads pedal 1's stored config; nil if it could not be read.
    func readStoredConfig() -> FootswitchProgram.StoredConfig?
    /// Programs the device to emit `combo` on press. Throws on failure.
    func program(combo: KeyCombo) throws
    /// A human-readable, read-only info report (USB identity / model / stored key).
    func info() -> String
}

extension PedalProgrammer {
    /// Default verification: read the stored config and compare to `expected`.
    func verify(expected: KeyCombo) -> PedalVerification {
        guard let stored = readStoredConfig() else { return .unreadable }
        switch stored {
        case .key(let combo): return combo == expected ? .verified : .mismatch
        case .unconfigured, .other: return .mismatch
        }
    }
}
