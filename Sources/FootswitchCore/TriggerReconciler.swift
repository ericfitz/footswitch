// Sources/FootswitchCore/TriggerReconciler.swift
import Foundation

/// The key a pedal actually emitted during a Settings "Test", resolved against the
/// app's key table. `named` carries a Keymap-recognized name (round-trips through
/// programming + the listener); `unknown` carries a raw virtual key code we have no
/// name for (can be shown but not adopted); `none` means nothing was captured
/// (timeout or cancel).
public enum CapturedKey: Equatable, Sendable {
    case named(String)
    case unknown(UInt16)
    case none

    /// Resolves a raw macOS virtual key code into a `CapturedKey` via `Keymap`.
    public static func from(keyCode: UInt16) -> CapturedKey {
        if let name = Keymap.keyName(forCode: keyCode) { return .named(name) }
        return .unknown(keyCode)
    }
}

/// The outcome of comparing a captured key to the configured (expected) trigger key.
/// Drives the Settings UI: `match` is a green confirmation; `mismatch` offers
/// adopt-or-reprogram; `unknown` offers reprogram only (no name to adopt); `noKey`
/// is a timeout/cancel no-op.
public enum TriggerReconciliation: Equatable, Sendable {
    case match(key: String)
    case mismatch(captured: String, expected: String)
    case unknown(code: UInt16, expected: String)
    case noKey
}

public enum TriggerReconciler {
    /// Compares a captured key to the `expected` configured key name
    /// (case-insensitive, matching how `Keymap` resolves names).
    public static func reconcile(captured: CapturedKey, expected: String) -> TriggerReconciliation {
        switch captured {
        case .none:
            return .noKey
        case .unknown(let code):
            return .unknown(code: code, expected: expected)
        case .named(let name):
            if name.compare(expected, options: .caseInsensitive) == .orderedSame {
                return .match(key: name)
            }
            return .mismatch(captured: name, expected: expected)
        }
    }
}
