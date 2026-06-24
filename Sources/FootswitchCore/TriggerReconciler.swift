// Sources/FootswitchCore/TriggerReconciler.swift
import Foundation

/// The combo a pedal actually emitted during a Settings "Test", resolved against
/// the app's key table. `named` carries a `KeyCombo` (key + modifiers) that
/// round-trips through programming + the listener; `unknown` carries a raw virtual
/// key code with no name (shown but not adoptable); `none` = nothing captured.
public enum CapturedKey: Equatable, Sendable {
    case named(KeyCombo)
    case unknown(UInt16)
    case none

    /// Resolves a raw virtual key code + masked modifier bits into a `CapturedKey`.
    public static func from(keyCode: UInt16, modifierBits: UInt64) -> CapturedKey {
        guard let name = Keymap.keyName(forCode: keyCode) else { return .unknown(keyCode) }
        return .named(KeyCombo(modifiers: Keymap.modifiers(forFlagBits: modifierBits), key: name))
    }
}

/// The outcome of comparing a captured combo to the configured (expected) trigger
/// combo. `match` is a green confirmation; `mismatch` offers adopt-or-reprogram;
/// `unknown` offers reprogram only; `noKey` is a timeout/cancel no-op.
public enum TriggerReconciliation: Equatable, Sendable {
    case match(combo: KeyCombo)
    case mismatch(captured: KeyCombo, expected: KeyCombo)
    case unknown(code: UInt16, expected: KeyCombo)
    case noKey
}

public enum TriggerReconciler {
    /// Compares a captured combo to the `expected` configured combo: key name is
    /// case-insensitive; modifiers compare as a set (order-independent).
    public static func reconcile(captured: CapturedKey, expected: KeyCombo) -> TriggerReconciliation {
        switch captured {
        case .none:
            return .noKey
        case .unknown(let code):
            return .unknown(code: code, expected: expected)
        case .named(let combo):
            if combo.matchesTrigger(expected) {
                return .match(combo: combo)
            }
            return .mismatch(captured: combo, expected: expected)
        }
    }
}
