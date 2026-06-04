import XCTest
@testable import FootswitchCore

final class RuleCodingTests: XCTestCase {
    func testLegacyActionDecodesIntoSlot1() throws {
        let json = """
        { "match": "com.x.app", "appName": "X",
          "action": { "type": "keyCombo", "modifiers": ["cmd"], "key": "D" } }
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.slots.bySlot,
                       [1: .keyCombo(KeyCombo(modifiers: [.command], key: "D"))])
        XCTAssertNil(rule.slots.action(forSlot: 2))
    }

    func testNewSlotsFormRoundTrips() throws {
        let json = """
        { "match": "com.x.app", "appName": "X",
          "slots": {
            "1": { "type": "keyCombo", "modifiers": ["cmd"], "key": "A" },
            "2": { "type": "dictation" }
          } }
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.slots.action(forSlot: 1),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
        XCTAssertEqual(rule.slots.action(forSlot: 2), .dictation)
        let decoded = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule)
    }

    func testEncodeEmitsSlotsNotAction() throws {
        let rule = Rule(match: "com.x.app", appName: "X",
                        action: .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
        let data = try JSONEncoder().encode(rule)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["slots"], "encoder must write slots")
        XCTAssertNil(object?["action"], "encoder must not write legacy action")
    }

    func testConvenienceInitPutsActionInSlot1() {
        let rule = Rule(match: "m", appName: "n",
                        action: .keyCombo(KeyCombo(modifiers: [], key: "F13")))
        XCTAssertEqual(rule.slots.action(forSlot: 1),
                       .keyCombo(KeyCombo(modifiers: [], key: "F13")))
    }
}
