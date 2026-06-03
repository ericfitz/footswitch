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
        // Legacy string form migrates to a single slot-1 entry.
        XCTAssertEqual(config.triggerKeys, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.primaryTriggerKey, TriggerKey(key: "F13", slot: 1))
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
        XCTAssertEqual(Config.default.triggerKeys, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(Config.default.primaryTriggerKey, TriggerKey(key: "F13", slot: 1))
    }

    func testDecodesNewTriggerKeysForm() throws {
        let json = """
        {
          "triggerKeys": [ { "key": "F16", "slot": 1 }, { "key": "F17", "slot": 2 } ],
          "dictationShortcut": { "modifiers": ["cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggerKeys,
                       [TriggerKey(key: "F16", slot: 1), TriggerKey(key: "F17", slot: 2)])
        XCTAssertEqual(config.primaryTriggerKey, TriggerKey(key: "F16", slot: 1))
    }

    func testLegacyTriggerKeyStringMigratesToSlotOne() throws {
        // Critical backward-compat: a legacy "triggerKey":"F13" string must migrate
        // to a single slot-1 entry rather than failing to decode.
        let json = """
        {
          "triggerKey": "F13",
          "dictationShortcut": { "modifiers": ["cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggerKeys, [TriggerKey(key: "F13", slot: 1)])
    }

    func testTriggerKeysWinsOverLegacyWhenBothPresent() throws {
        // When both the legacy "triggerKey" string and the new "triggerKeys" array
        // are present, the new form must take precedence (legacy is ignored).
        let json = """
        {
          "triggerKey": "F13",
          "triggerKeys": [ { "key": "F16", "slot": 1 } ],
          "dictationShortcut": { "modifiers": ["cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggerKeys, [TriggerKey(key: "F16", slot: 1)])
    }

    func testTriggerKeysRoundTrips() throws {
        let config = Config(
            triggerKeys: [TriggerKey(key: "F16", slot: 1), TriggerKey(key: "F17", slot: 2)],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250,
            defaultAction: .dictation,
            rules: [])
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.triggerKeys,
                       [TriggerKey(key: "F16", slot: 1), TriggerKey(key: "F17", slot: 2)])
    }

    func testEncodeWritesNewFormOnly() throws {
        let config = Config.default
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["triggerKeys"], "encoder should write triggerKeys")
        XCTAssertNil(object?["triggerKey"], "encoder should not write the legacy triggerKey")
    }

    func testDecodesDefaultsAndMigratesRemovedMute() throws {
        for (raw, expected): (String, DefaultAction) in [
            (#"{"type":"none"}"#, .none),
            (#"{"type":"dictation"}"#, .dictation),
            // The removed device-mute default migrates to a no-op.
            (#"{"type":"muteInput"}"#, .none),
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
