import XCTest
@testable import FootswitchCore

final class ActionCodingTests: XCTestCase {
    func testKeyComboRoundTrips() throws {
        let action = Action.keyCombo(KeyCombo(modifiers: [.command], key: "D"))
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(Action.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testDictationRoundTrips() throws {
        let action = Action.dictation
        let decoded = try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
    }

    func testUnknownActionTypeThrows() throws {
        let json = #"{"type":"shell","command":"echo hi"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Action.self, from: Data(json.utf8)))
    }

    func testKeyComboDecodesFromSpecJSON() throws {
        let json = #"{"type":"keyCombo","modifiers":["cmd"],"key":"D"}"#
        let decoded = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
    }

    // MARK: shortcut action (issue #3)

    func testShortcutRoundTrips() throws {
        let action = Action.shortcut(ShortcutRef(identifier: "ABC-123", name: "My SC"))
        let decoded = try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
    }

    func testShortcutDecodesFromJSON() throws {
        let json = #"{"type":"shortcut","identifier":"UUID-1","name":"My SC"}"#
        let decoded = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .shortcut(ShortcutRef(identifier: "UUID-1", name: "My SC")))
    }

    func testShortcutNameDefaultsToEmptyWhenAbsent() throws {
        let json = #"{"type":"shortcut","identifier":"UUID-1"}"#
        let decoded = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .shortcut(ShortcutRef(identifier: "UUID-1", name: "")))
    }

    func testShortcutMissingIdentifierThrows() throws {
        let json = #"{"type":"shortcut","name":"My SC"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Action.self, from: Data(json.utf8)))
    }
}
