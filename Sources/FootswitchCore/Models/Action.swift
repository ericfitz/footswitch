import Foundation

public enum Modifier: String, Codable, Sendable, CaseIterable {
    case command, option, control, shift

    // Accept spec shorthand ("cmd","opt","ctrl") on decode.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "cmd", "command": self = .command
        case "opt", "option", "alt": self = .option
        case "ctrl", "control": self = .control
        case "shift": self = .shift
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown modifier \(raw)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .command: try c.encode("cmd")
        case .option: try c.encode("opt")
        case .control: try c.encode("ctrl")
        case .shift: try c.encode("shift")
        }
    }
}

public struct KeyCombo: Codable, Equatable, Sendable {
    public var modifiers: [Modifier]
    public var key: String   // e.g. "D", "F13", "Return"

    public init(modifiers: [Modifier], key: String) {
        self.modifiers = modifiers
        self.key = key
    }
}

public extension KeyCombo {
    /// True when this combo and `other` denote the same trigger: same key name
    /// (case-insensitive) and the same modifier SET (order-independent). Used by
    /// trigger reconciliation and device-config verification so a non-canonical
    /// modifier order never causes a false mismatch.
    func matchesTrigger(_ other: KeyCombo) -> Bool {
        key.compare(other.key, options: .caseInsensitive) == .orderedSame
            && Set(modifiers) == Set(other.modifiers)
    }
}

/// References a Shortcuts.app shortcut by its stable identifier (UUID), plus a
/// display name captured at selection time. `identifier` is what `shortcuts run`
/// is given; `name` is what the table and the "Last:" menu line show. If
/// `identifier` is empty (e.g. a hand-edited config), invocation falls back to
/// running by `name`.
public struct ShortcutRef: Codable, Equatable, Sendable {
    public var identifier: String
    public var name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

public enum Action: Codable, Equatable, Sendable {
    case keyCombo(KeyCombo)
    case dictation
    case shortcut(ShortcutRef)

    private enum CodingKeys: String, CodingKey { case type, modifiers, key, identifier, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "keyCombo":
            self = .keyCombo(KeyCombo(
                modifiers: try c.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? [],
                key: try c.decode(String.self, forKey: .key)))
        case "dictation":
            self = .dictation
        case "shortcut":
            self = .shortcut(ShortcutRef(
                identifier: try c.decode(String.self, forKey: .identifier),
                name: try c.decodeIfPresent(String.self, forKey: .name) ?? ""))
        case let other:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown action type \(other)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyCombo(let combo):
            try c.encode("keyCombo", forKey: .type)
            try c.encode(combo.modifiers, forKey: .modifiers)
            try c.encode(combo.key, forKey: .key)
        case .dictation:
            try c.encode("dictation", forKey: .type)
        case .shortcut(let ref):
            try c.encode("shortcut", forKey: .type)
            try c.encode(ref.identifier, forKey: .identifier)
            try c.encode(ref.name, forKey: .name)
        }
    }
}
