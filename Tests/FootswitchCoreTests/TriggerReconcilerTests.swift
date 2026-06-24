// Tests/FootswitchCoreTests/TriggerReconcilerTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerReconcilerTests: XCTestCase {
    func testFromKnownKeyCode() {
        XCTAssertEqual(CapturedKey.from(keyCode: 0x69), .named("F13"))
    }

    func testFromUnknownKeyCode() {
        // 0x6E has no entry in Keymap.table.
        XCTAssertEqual(CapturedKey.from(keyCode: 0x6E), .unknown(0x6E))
    }

    func testReconcileMatchIsCaseInsensitive() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named("f13"), expected: "F13"),
            .match(key: "f13"))
    }

    func testReconcileMismatch() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named("F19"), expected: "F16"),
            .mismatch(captured: "F19", expected: "F16"))
    }

    func testReconcileUnknown() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .unknown(0x6E), expected: "F16"),
            .unknown(code: 0x6E, expected: "F16"))
    }

    func testReconcileNoKey() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .none, expected: "F16"),
            .noKey)
    }
}
