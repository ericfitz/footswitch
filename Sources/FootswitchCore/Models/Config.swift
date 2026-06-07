import Foundation

public struct Config: Codable, Equatable, Sendable {
    /// Trigger keys grouped by transport. The FS17Pro stores its key config
    /// separately for USB vs Bluetooth; the listener watches the union of all
    /// transports' keys, while programming targets only the connected transport.
    public var triggers: Triggers
    public var dictationShortcut: KeyCombo
    public var debounceMs: Int
    public var defaultAction: DefaultAction
    public var rules: [Rule]

    /// User-supplied device-table entries, merged with the built-in
    /// `SupportedDevices.all` at detection time so a same-protocol foot switch can
    /// be added by editing config rather than changing code (GitHub issue #4).
    /// Optional in JSON; defaults to empty. Invalid entries are skipped at use.
    public var customDevices: [CustomDevice]

    /// Every trigger key across all transports (de-duplicated by key) — for the
    /// listener, which fires on any of them.
    public var allTriggerKeys: [TriggerKey] { triggers.allKeys }

    public init(triggers: Triggers, dictationShortcut: KeyCombo,
                debounceMs: Int, defaultAction: DefaultAction, rules: [Rule],
                customDevices: [CustomDevice] = []) {
        self.triggers = triggers
        self.dictationShortcut = dictationShortcut
        self.debounceMs = debounceMs
        self.defaultAction = defaultAction
        self.rules = rules
        self.customDevices = customDevices
    }

    private enum CodingKeys: String, CodingKey {
        case triggerKey, triggerKeys, triggers, dictationShortcut, debounceMs, defaultAction, rules
        case customDevices
    }

    // Decoder accepts THREE shapes for backward compatibility, newest first:
    //  - new:     "triggers": { "usb": [TriggerKey], "bluetooth": [TriggerKey] }
    //  - interim: "triggerKeys": [TriggerKey]   -> same list applied to BOTH transports
    //  - legacy:  "triggerKey": "F13" (string)  -> [{F13,slot1}] applied to BOTH transports
    //  - none:    default F13/slot1 on both transports
    // Applying legacy/interim keys to BOTH transports preserves prior listener
    // behavior (it watched those keys) and gives programming a sane per-transport
    // default. An all-empty `triggers` map (e.g. hand-edited to []/[]) is treated
    // as absent and falls through, so the listener never ends up watching nothing.
    //
    // defaultAction also tolerates a legacy Action-shaped value, migrating to
    // .dictation, as before.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try? c.decode(Triggers.self, forKey: .triggers), !t.allKeys.isEmpty {
            triggers = t
        } else if let keys = try? c.decode([TriggerKey].self, forKey: .triggerKeys), !keys.isEmpty {
            triggers = Triggers(usb: keys, bluetooth: keys)
        } else if let legacy = try? c.decode(String.self, forKey: .triggerKey) {
            let k = [TriggerKey(key: legacy, slot: 1)]
            triggers = Triggers(usb: k, bluetooth: k)
        } else {
            let k = [TriggerKey(key: "F13", slot: 1)]
            triggers = Triggers(usb: k, bluetooth: k)
        }
        dictationShortcut = try c.decode(KeyCombo.self, forKey: .dictationShortcut)
        debounceMs = try c.decode(Int.self, forKey: .debounceMs)
        defaultAction = (try? c.decode(DefaultAction.self, forKey: .defaultAction)) ?? .dictation
        rules = try c.decode([Rule].self, forKey: .rules)
        // Optional + tolerant: a missing or malformed customDevices array decodes
        // to empty rather than failing the whole config load (each entry is
        // re-validated at use via CustomDevice.resolved()).
        customDevices = (try? c.decode([CustomDevice].self, forKey: .customDevices)) ?? []
    }

    // Encode the new `triggers` form only (legacy keys are read-only, for migration).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(triggers, forKey: .triggers)
        try c.encode(dictationShortcut, forKey: .dictationShortcut)
        try c.encode(debounceMs, forKey: .debounceMs)
        try c.encode(defaultAction, forKey: .defaultAction)
        try c.encode(rules, forKey: .rules)
        // Only emit customDevices when present, keeping default configs unchanged.
        if !customDevices.isEmpty {
            try c.encode(customDevices, forKey: .customDevices)
        }
    }

    public static let `default` = Config(
        triggers: Triggers(
            usb: [
                TriggerKey(key: "F13", slot: 1),
                TriggerKey(key: "F14", slot: 2),
                TriggerKey(key: "F15", slot: 3),
            ],
            bluetooth: [TriggerKey(key: "F13", slot: 1)]),
        dictationShortcut: KeyCombo(modifiers: [.control, .option, .command], key: "D"),
        debounceMs: 250,
        defaultAction: .dictation,
        rules: []
    )
}
