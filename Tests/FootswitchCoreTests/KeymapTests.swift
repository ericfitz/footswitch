import XCTest
@testable import FootswitchCore

final class KeymapTests: XCTestCase {
    func testLetterKeyCode() {
        XCTAssertEqual(Keymap.keyCode(for: "D"), 0x02)   // ANSI 'D'
        XCTAssertEqual(Keymap.keyCode(for: "d"), 0x02)   // case-insensitive
    }

    func testFunctionKeyCode() {
        XCTAssertEqual(Keymap.keyCode(for: "F13"), 0x69)
        XCTAssertEqual(Keymap.keyCode(for: "f13"), 0x69)
    }

    func testReturnKeyCode() {
        XCTAssertEqual(Keymap.keyCode(for: "Return"), 0x24)
    }

    func testUnknownKeyIsNil() {
        XCTAssertNil(Keymap.keyCode(for: "NotAKey"))
    }

    func testReverseLookupLetterAndFunctionKey() {
        XCTAssertEqual(Keymap.keyName(forCode: 0x02), "D")
        XCTAssertEqual(Keymap.keyName(forCode: 0x69), "F13")
    }

    func testReverseLookupCanonicalForAliasedCode() {
        // 0x24 is both RETURN and ENTER in the table; reverse must pick a canonical
        // name that round-trips through keyCode(for:).
        let name = Keymap.keyName(forCode: 0x24)
        XCTAssertEqual(name, "Return")
        XCTAssertEqual(Keymap.keyCode(for: name!), 0x24)
    }

    func testReverseLookupRoundTripsForLetters() {
        for code in [UInt16(0x00), 0x02, 0x0E, 0x2E] {
            let name = Keymap.keyName(forCode: code)
            XCTAssertNotNil(name)
            XCTAssertEqual(Keymap.keyCode(for: name!), code)
        }
    }

    func testReverseLookupUnknownCodeIsNil() {
        XCTAssertNil(Keymap.keyName(forCode: 0xFF))
    }

    func testModifierFlagBits() {
        XCTAssertEqual(Keymap.flagBits(for: [.command]), 0x100000)         // maskCommand
        XCTAssertEqual(Keymap.flagBits(for: [.shift]), 0x20000)            // maskShift
        let comboBits = Keymap.flagBits(for: [.control, .option, .command])
        XCTAssertEqual(comboBits, 0x040000 | 0x080000 | 0x100000)
    }
}
