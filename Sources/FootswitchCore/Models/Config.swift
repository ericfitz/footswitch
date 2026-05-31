import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var triggerKey: String
    public var dictationShortcut: KeyCombo
    public var debounceMs: Int
    public var defaultAction: DefaultAction
    public var rules: [Rule]

    public init(triggerKey: String, dictationShortcut: KeyCombo,
                debounceMs: Int, defaultAction: DefaultAction, rules: [Rule]) {
        self.triggerKey = triggerKey
        self.dictationShortcut = dictationShortcut
        self.debounceMs = debounceMs
        self.defaultAction = defaultAction
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case triggerKey, dictationShortcut, debounceMs, defaultAction, rules
    }

    // Custom decode so a pre-existing config whose defaultAction was an Action
    // (e.g. {"type":"keyCombo",...}) doesn't fail to load — anything that isn't a
    // valid DefaultAction migrates to .dictation. The {"type":"dictation"} form
    // decodes natively as DefaultAction.dictation, so the common case is lossless.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        triggerKey = try c.decode(String.self, forKey: .triggerKey)
        dictationShortcut = try c.decode(KeyCombo.self, forKey: .dictationShortcut)
        debounceMs = try c.decode(Int.self, forKey: .debounceMs)
        defaultAction = (try? c.decode(DefaultAction.self, forKey: .defaultAction)) ?? .dictation
        rules = try c.decode([Rule].self, forKey: .rules)
    }

    public static let `default` = Config(
        triggerKey: "F13",
        dictationShortcut: KeyCombo(modifiers: [.control, .option, .command], key: "D"),
        debounceMs: 250,
        defaultAction: .dictation,
        rules: []
    )
}
