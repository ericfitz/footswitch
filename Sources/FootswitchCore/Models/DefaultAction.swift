import Foundation

/// What the pedal does when the frontmost app has no matching rule. Presented as
/// a single "Start dictation when no app rule matches" checkbox in settings
/// (checked = .dictation, unchecked = .none).
public enum DefaultAction: Codable, Equatable, Sendable {
    case dictation
    case none           // do nothing

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "dictation": self = .dictation
        case "none":      self = .none
        // Migrate the removed device-mute default (it never worked for apps like
        // FaceTime/Zoom that keep their own mute) to a no-op. Per-app key-combo
        // rules are the supported way to mute those apps.
        case "muteInput": self = .none
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown default action type \(type)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dictation: try c.encode("dictation", forKey: .type)
        case .none:      try c.encode("none", forKey: .type)
        }
    }
}

/// The concrete thing to do for a given press, after rule resolution. A matched
/// app rule contributes a key combo or dictation; an unmatched press contributes
/// the configured DefaultAction.
public enum ResolvedAction: Equatable, Sendable {
    case keyCombo(KeyCombo)
    case dictation
    case none
}
