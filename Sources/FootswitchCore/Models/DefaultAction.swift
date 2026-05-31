import Foundation

/// What the pedal does when the frontmost app has no matching rule. This is the
/// three-way choice presented as a radio group in settings.
public enum DefaultAction: Codable, Equatable, Sendable {
    case dictation
    case muteInput      // hardware mute/unmute of the default input device
    case none           // do nothing

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "dictation": self = .dictation
        case "muteInput": self = .muteInput
        case "none":      self = .none
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown default action type \(type)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dictation: try c.encode("dictation", forKey: .type)
        case .muteInput: try c.encode("muteInput", forKey: .type)
        case .none:      try c.encode("none", forKey: .type)
        }
    }
}

/// The concrete thing to do for a given press, after rule resolution. A matched
/// app rule contributes a key combo or dictation; an unmatched press contributes
/// the configured DefaultAction (which may additionally be mute or no-op).
public enum ResolvedAction: Equatable, Sendable {
    case keyCombo(KeyCombo)
    case dictation
    case muteInput
    case none
}
