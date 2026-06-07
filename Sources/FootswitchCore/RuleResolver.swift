import Foundation

public enum RuleResolver {
    /// Resolve what to do for `bundleID` when pedal `slot` (1-based) fires. An
    /// exact bundle-ID match (first wins) that has a per-slot action contributes
    /// it; otherwise the config's global DefaultAction applies. The default is
    /// global (not per-slot) by design.
    public static func resolve(bundleID: String?, slot: Int, config: Config) -> ResolvedAction {
        if let bundleID,
           let rule = config.rules.first(where: { $0.match == bundleID }),
           let action = rule.slots.action(forSlot: slot) {
            switch action {
            case .keyCombo(let combo): return .keyCombo(combo)
            case .dictation:           return .dictation
            case .shortcut(let ref):   return .shortcut(ref)
            }
        }
        switch config.defaultAction {
        case .dictation: return .dictation
        case .none:      return .none
        }
    }

    /// Back-compat wrapper: resolves for the primary pedal (slot 1).
    public static func resolve(bundleID: String?, config: Config) -> ResolvedAction {
        resolve(bundleID: bundleID, slot: 1, config: config)
    }
}
