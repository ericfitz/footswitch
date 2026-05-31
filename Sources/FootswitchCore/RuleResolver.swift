import Foundation

public enum RuleResolver {
    /// Resolve what to do for the given frontmost app bundle ID. An exact
    /// bundle-ID match (first wins) contributes its rule's Action; otherwise the
    /// config's DefaultAction applies.
    public static func resolve(bundleID: String?, config: Config) -> ResolvedAction {
        if let bundleID, let rule = config.rules.first(where: { $0.match == bundleID }) {
            switch rule.action {
            case .keyCombo(let combo): return .keyCombo(combo)
            case .dictation:           return .dictation
            }
        }
        switch config.defaultAction {
        case .dictation: return .dictation
        case .muteInput: return .muteInput
        case .none:      return .none
        }
    }
}
