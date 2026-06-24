// Sources/FootswitchCore/TriggerMatcher.swift

/// Pure, IO-free trigger-match table for the pedal listener: maps a (virtual key
/// code + masked modifier bits) to a slot, with EXACT modifier matching. Built from
/// the config's trigger keys; the event-tap glue (`PedalListener`) feeds it the
/// keycode and the masked modifier bits (#10).
public struct TriggerMatcher: Equatable, Sendable {
    /// One resolved trigger: a virtual key code + the modifier flag bits that must be
    /// present EXACTLY for it to fire.
    public struct Key: Hashable, Sendable {
        public let keyCode: UInt16
        public let modBits: UInt64
        public init(keyCode: UInt16, modBits: UInt64) {
            self.keyCode = keyCode
            self.modBits = modBits
        }
    }

    private let table: [Key: Int]

    /// Builds the table from `triggerKeys`: each name → `Keymap.keyCode`, each
    /// modifier set → `Keymap.flagBits`; unresolved names are skipped. First-writer-
    /// wins per `(keyCode, modBits)`. Empty result falls back to bare F13 / slot 1.
    public init(triggerKeys: [TriggerKey]) {
        var map: [Key: Int] = [:]
        for tk in triggerKeys {
            guard let code = Keymap.keyCode(for: tk.key) else { continue }
            let key = Key(keyCode: code, modBits: Keymap.flagBits(for: tk.modifiers))
            if map[key] == nil { map[key] = tk.slot }
        }
        if map.isEmpty { map[Key(keyCode: 0x69, modBits: 0)] = 1 }   // F13 / slot 1
        self.table = map
    }

    /// All distinct match keys (for the listener's per-key debouncers).
    public var keys: [Key] { Array(table.keys) }

    /// The slot to fire for `(keyCode, modBits)`, or nil if it is not a trigger.
    /// `modBits` MUST already be masked to `Keymap.deviceModifierMask`.
    public func slot(forKeyCode keyCode: UInt16, modBits: UInt64) -> Int? {
        table[Key(keyCode: keyCode, modBits: modBits)]
    }
}
