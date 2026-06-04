import Foundation

public struct Rule: Codable, Equatable, Sendable {
    public var match: String          // frontmost app bundle ID
    public var appName: String        // display only
    public var slots: SlotActions     // per-slot (1-based) actions

    public init(match: String, appName: String, slots: SlotActions) {
        self.match = match
        self.appName = appName
        self.slots = slots
    }

    /// Convenience: a single action becomes slot 1's action (the primary pedal).
    /// Lets existing single-pedal callers keep working unchanged.
    public init(match: String, appName: String, action: Action) {
        self.init(match: match, appName: appName, slots: SlotActions(bySlot: [1: action]))
    }

    private enum CodingKeys: String, CodingKey { case match, appName, slots, action }

    // Decodes TWO shapes, newest first:
    //  - new:    "slots": { "1": Action, "2": Action, ... }
    //  - legacy: "action": Action   -> becomes slot 1's action
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = try c.decode(String.self, forKey: .match)
        appName = try c.decode(String.self, forKey: .appName)
        if let s = try? c.decode(SlotActions.self, forKey: .slots) {
            slots = s
        } else if let legacy = try? c.decode(Action.self, forKey: .action) {
            slots = SlotActions(bySlot: [1: legacy])
        } else {
            slots = SlotActions(bySlot: [:])
        }
    }

    // Encode the new `slots` form only (legacy `action` is read-only, for migration).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(match, forKey: .match)
        try c.encode(appName, forKey: .appName)
        try c.encode(slots, forKey: .slots)
    }
}
