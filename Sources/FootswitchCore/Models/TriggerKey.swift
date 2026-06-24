import Foundation

/// One trigger: a key (optionally with modifiers) the pedal emits, paired with the
/// logical button/pedal slot it occupies (1 = first button, ...). The listener fires
/// on the combo; the slot tells the programmer which pedal slot to write.
public struct TriggerKey: Codable, Equatable, Sendable {
    public var key: String
    public var slot: Int
    /// Modifiers the pedal emits with `key` (⌃⌥⇧⌘). Empty = a bare key. Stored in
    /// canonical order (control, option, shift, command); see `Keymap`.
    public var modifiers: [Modifier]

    public init(key: String, slot: Int, modifiers: [Modifier] = []) {
        self.key = key
        self.slot = slot
        self.modifiers = modifiers
    }

    /// This trigger as a `KeyCombo` (for matching, programming, and display).
    public var combo: KeyCombo { KeyCombo(modifiers: modifiers, key: key) }

    private enum CodingKeys: String, CodingKey { case key, slot, modifiers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        slot = try c.decode(Int.self, forKey: .slot)
        // Tolerant: the bare-key form (no `modifiers`) decodes to [].
        modifiers = (try? c.decode([Modifier].self, forKey: .modifiers)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(slot, forKey: .slot)
        // Omit when empty so existing bare-key configs stay byte-stable.
        if !modifiers.isEmpty { try c.encode(modifiers, forKey: .modifiers) }
    }
}
