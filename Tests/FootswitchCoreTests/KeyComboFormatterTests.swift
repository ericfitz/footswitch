import XCTest
@testable import FootswitchCore

final class KeyComboFormatterTests: XCTestCase {
    func testSingleModifier() {
        XCTAssertEqual(KeyComboFormatter.display(KeyCombo(modifiers: [.command], key: "D")), "⌘D")
    }
    func testCanonicalOrderRegardlessOfInput() {
        XCTAssertEqual(KeyComboFormatter.display(KeyCombo(modifiers: [.command, .shift], key: "a")), "⇧⌘A")
        XCTAssertEqual(KeyComboFormatter.display(KeyCombo(modifiers: [.command, .option, .control], key: "d")), "⌃⌥⌘D")
    }
    func testAllFour() {
        XCTAssertEqual(KeyComboFormatter.display(KeyCombo(modifiers: [.shift, .command, .control, .option], key: "x")), "⌃⌥⇧⌘X")
    }
    func testNoModifiers() {
        XCTAssertEqual(KeyComboFormatter.display(KeyCombo(modifiers: [], key: "F13")), "F13")
    }
}
