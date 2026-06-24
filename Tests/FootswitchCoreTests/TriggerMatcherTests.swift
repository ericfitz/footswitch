// Tests/FootswitchCoreTests/TriggerMatcherTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerMatcherTests: XCTestCase {
    // F13 = 0x69; control flag = 0x40000.
    func testBareKeyMatchesOnlyWithoutModifiers() {
        let m = TriggerMatcher(triggerKeys: [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
        XCTAssertNil(m.slot(forKeyCode: 0x69, modBits: 0x40000))   // ⌃F13 ≠ {F13}
    }

    func testModifierKeyMatchesExactly() {
        let m = TriggerMatcher(triggerKeys: [TriggerKey(key: "F13", slot: 2, modifiers: [.control])])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0x40000), 2)
        XCTAssertNil(m.slot(forKeyCode: 0x69, modBits: 0))         // bare F13 ≠ {⌃F13}
    }

    func testSameKeyDifferentModifiersCoexist() {
        let m = TriggerMatcher(triggerKeys: [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F13", slot: 2, modifiers: [.control]),
        ])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0x40000), 2)
        XCTAssertEqual(m.keys.count, 2)
    }

    func testUnresolvedKeySkipped_andFallback() {
        // Only an unknown key name → table empty → fall back to bare F13 / slot 1.
        let m = TriggerMatcher(triggerKeys: [TriggerKey(key: "NOPE", slot: 1)])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
    }

    func testFirstWriterWinsPerCombo() {
        let m = TriggerMatcher(triggerKeys: [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F13", slot: 3),   // same combo → ignored
        ])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
    }
}
