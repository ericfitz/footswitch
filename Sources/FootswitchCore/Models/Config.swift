import Foundation

public struct Config: Codable, Equatable, Sendable {
    /// Keys that trigger the pedal action, each paired with its logical slot. The
    /// listener fires on any of these keys; `slot` tells the programmer which pedal
    /// slot to write. A list (not one key) because the FS17Pro emits different keys
    /// per transport and multi-button pedals send 1-3 distinct keys.
    public var triggerKeys: [TriggerKey]
    public var dictationShortcut: KeyCombo
    public var debounceMs: Int
    public var defaultAction: DefaultAction
    public var rules: [Rule]

    /// The primary trigger (first entry), used when programming the device and for
    /// the Settings config-verify display. Falls back to F13 / slot 1 if empty.
    public var primaryTriggerKey: TriggerKey { triggerKeys.first ?? TriggerKey(key: "F13", slot: 1) }

    public init(triggerKeys: [TriggerKey], dictationShortcut: KeyCombo,
                debounceMs: Int, defaultAction: DefaultAction, rules: [Rule]) {
        self.triggerKeys = triggerKeys
        self.dictationShortcut = dictationShortcut
        self.debounceMs = debounceMs
        self.defaultAction = defaultAction
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case triggerKey, triggerKeys, dictationShortcut, debounceMs, defaultAction, rules
    }

    // Decoder accepts BOTH shapes for backward compatibility:
    //  - new: "triggerKeys": [{"key":"F16","slot":1}, ...]
    //  - legacy: "triggerKey": "F13"  -> migrates to [TriggerKey(key:"F13", slot:1)]
    // triggerKeys wins if both present; defaults to [F13/slot1] if neither/empty.
    //
    // A custom decode is also needed so a pre-existing config whose defaultAction
    // was an Action (e.g. {"type":"keyCombo",...}) doesn't fail to load — anything
    // that isn't a valid DefaultAction migrates to .dictation.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let keys = try? c.decode([TriggerKey].self, forKey: .triggerKeys), !keys.isEmpty {
            triggerKeys = keys
        } else if let legacy = try? c.decode(String.self, forKey: .triggerKey) {
            triggerKeys = [TriggerKey(key: legacy, slot: 1)]
        } else {
            triggerKeys = [TriggerKey(key: "F13", slot: 1)]
        }
        dictationShortcut = try c.decode(KeyCombo.self, forKey: .dictationShortcut)
        debounceMs = try c.decode(Int.self, forKey: .debounceMs)
        defaultAction = (try? c.decode(DefaultAction.self, forKey: .defaultAction)) ?? .dictation
        rules = try c.decode([Rule].self, forKey: .rules)
    }

    // Encode the new `triggerKeys` form only (the legacy `triggerKey` is read-only,
    // for migrating old files).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(triggerKeys, forKey: .triggerKeys)
        try c.encode(dictationShortcut, forKey: .dictationShortcut)
        try c.encode(debounceMs, forKey: .debounceMs)
        try c.encode(defaultAction, forKey: .defaultAction)
        try c.encode(rules, forKey: .rules)
    }

    public static let `default` = Config(
        triggerKeys: [TriggerKey(key: "F13", slot: 1)],
        dictationShortcut: KeyCombo(modifiers: [.control, .option, .command], key: "D"),
        debounceMs: 250,
        defaultAction: .dictation,
        rules: []
    )
}
