import Foundation

/// Per-slot actions for one app rule. Sparse: only configured slots appear.
/// Slot keys are 1-based, matching `TriggerKey.slot`. Encodes as a JSON object
/// keyed by the stringified slot index → `Action`.
public struct SlotActions: Codable, Equatable, Sendable {
    public var bySlot: [Int: Action]

    public init(bySlot: [Int: Action]) {
        self.bySlot = bySlot
    }

    /// The action configured for `slot` (1-based), or nil if none.
    public func action(forSlot slot: Int) -> Action? { bySlot[slot] }

    private struct SlotKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = Int(stringValue) }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SlotKey.self)
        var result: [Int: Action] = [:]
        for key in c.allKeys {
            guard let slot = Int(key.stringValue) else { continue }
            result[slot] = try c.decode(Action.self, forKey: key)
        }
        bySlot = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SlotKey.self)
        // Deterministic key order for stable round-trips.
        for slot in bySlot.keys.sorted() {
            try c.encode(bySlot[slot], forKey: SlotKey(intValue: slot)!)
        }
    }
}
