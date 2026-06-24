import XCTest
@testable import FootswitchCore

final class KeyComboMatchTests: XCTestCase {
    func testSameKeyDifferentModifierOrderMatches() {
        XCTAssertTrue(KeyCombo(modifiers: [.shift, .control], key: "F13")
            .matchesTrigger(KeyCombo(modifiers: [.control, .shift], key: "F13")))
    }
    func testCaseInsensitiveKey() {
        XCTAssertTrue(KeyCombo(modifiers: [], key: "f13")
            .matchesTrigger(KeyCombo(modifiers: [], key: "F13")))
    }
    func testDifferentModifierSetDoesNotMatch() {
        XCTAssertFalse(KeyCombo(modifiers: [.control], key: "F13")
            .matchesTrigger(KeyCombo(modifiers: [], key: "F13")))
    }
    func testDifferentKeyDoesNotMatch() {
        XCTAssertFalse(KeyCombo(modifiers: [], key: "F13")
            .matchesTrigger(KeyCombo(modifiers: [], key: "F14")))
    }
}
