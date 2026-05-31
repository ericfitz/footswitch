import XCTest
@testable import FootswitchCore

final class ConfigCodingTests: XCTestCase {
    func testDecodesSpecExample() throws {
        let json = """
        {
          "triggerKey": "F13",
          "dictationShortcut": { "modifiers": ["ctrl","opt","cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": [
            { "match": "com.microsoft.VSCode", "appName": "Visual Studio Code",
              "action": { "type": "keyCombo", "modifiers": ["cmd"], "key": "D" } }
          ]
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggerKey, "F13")
        XCTAssertEqual(config.debounceMs, 250)
        XCTAssertEqual(config.defaultAction, .dictation)
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertEqual(config.rules[0].match, "com.microsoft.VSCode")
        XCTAssertEqual(config.rules[0].action, .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
    }

    func testRoundTrips() throws {
        let config = Config.default
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testDefaultHasDictationDefaultAndNoRules() {
        XCTAssertEqual(Config.default.defaultAction, .dictation)
        XCTAssertTrue(Config.default.rules.isEmpty)
        XCTAssertEqual(Config.default.triggerKey, "F13")
    }

    func testDecodesMuteAndNoneDefaults() throws {
        for (raw, expected): (String, DefaultAction) in [
            (#"{"type":"muteInput"}"#, .muteInput),
            (#"{"type":"none"}"#, .none),
            (#"{"type":"dictation"}"#, .dictation),
        ] {
            let json = """
            { "triggerKey":"F13",
              "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
              "debounceMs":250, "defaultAction": \(raw), "rules": [] }
            """
            let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
            XCTAssertEqual(config.defaultAction, expected)
        }
    }

    func testLegacyKeyComboDefaultMigratesToDictation() throws {
        // Older configs could carry an Action as defaultAction; a keyCombo there
        // is not a valid DefaultAction and must migrate to .dictation, not fail.
        let json = """
        { "triggerKey":"F13",
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250,
          "defaultAction": { "type":"keyCombo", "modifiers":["cmd"], "key":"D" },
          "rules": [] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.defaultAction, .dictation)
    }
}
