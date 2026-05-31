import Foundation

/// Decides whether a press should fire, given a minimum interval between fires.
/// Time is passed in as milliseconds so the logic is pure and testable.
public struct Debouncer {
    public let intervalMs: Int
    private var lastFireMs: Int?

    public init(intervalMs: Int) {
        self.intervalMs = intervalMs
    }

    public mutating func shouldFire(atMs now: Int) -> Bool {
        if let last = lastFireMs, now - last <= intervalMs {
            return false
        }
        lastFireMs = now
        return true
    }
}
