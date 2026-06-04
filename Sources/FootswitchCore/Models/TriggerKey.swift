import Foundation

/// One trigger: a key the pedal emits, paired with the logical button/pedal slot
/// it occupies (1 = first button, 2 = second, ...). The listener fires on the key;
/// the slot tells the programmer which pedal slot to write. Slot is transport-
/// neutral — each programmer maps it to its own wire pedal-index (USB: slot-1,
/// BLE: slot).
public struct TriggerKey: Codable, Equatable, Sendable {
    public var key: String
    public var slot: Int

    public init(key: String, slot: Int) {
        self.key = key
        self.slot = slot
    }
}
