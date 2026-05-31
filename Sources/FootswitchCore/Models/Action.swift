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

public enum Action: Codable, Equatable, Sendable {
    case keyCombo(KeyCombo)
    case dictation

    private enum CodingKeys: String, CodingKey { case type, modifiers, key }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "keyCombo":
            self = .keyCombo(KeyCombo(
                modifiers: try c.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? [],
                key: try c.decode(String.self, forKey: .key)))
        case "dictation":
            self = .dictation
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
        }
    }
}
