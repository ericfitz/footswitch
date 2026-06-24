// Tests/FootswitchCoreTests/TriggerReconcilerTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerReconcilerTests: XCTestCase {
    private func combo(_ key: String, _ mods: [Modifier] = []) -> KeyCombo {
        KeyCombo(modifiers: mods, key: key)
    }

    func testFromKnownKeyCodeWithModifiers() {
        // F13 = 0x69; control flag = 0x40000.
        XCTAssertEqual(CapturedKey.from(keyCode: 0x69, modifierBits: 0x40000),
                       .named(combo("F13", [.control])))
    }

    func testFromUnknownKeyCode() {
        XCTAssertEqual(CapturedKey.from(keyCode: 0x6E, modifierBits: 0), .unknown(0x6E))
    }

    func testReconcileMatchExactCaseInsensitiveModifierSet() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named(combo("f13", [.shift, .control])),
                                        expected: combo("F13", [.control, .shift])),
            .match(combo: combo("f13", [.shift, .control])))
    }

    func testReconcileMismatchOnModifiers() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named(combo("F13")),
                                        expected: combo("F13", [.control])),
            .mismatch(captured: combo("F13"), expected: combo("F13", [.control])))
    }

    func testReconcileUnknown() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .unknown(0x6E), expected: combo("F16")),
            .unknown(code: 0x6E, expected: combo("F16")))
    }

    func testReconcileNoKey() {
        XCTAssertEqual(TriggerReconciler.reconcile(captured: .none, expected: combo("F16")), .noKey)
    }
}
