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
        // Legacy string form migrates to a single slot-1 entry on BOTH transports.
        XCTAssertEqual(config.triggers.usb, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.triggers.bluetooth, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.triggers.primary(for: .usb), TriggerKey(key: "F13", slot: 1))
        XCTAssertEqual(config.triggers.primary(for: .bluetooth), TriggerKey(key: "F13", slot: 1))
        XCTAssertEqual(config.debounceMs, 250)
        XCTAssertEqual(config.defaultAction, .dictation)
        XCTAssertEqual(config.rules.count, 1)
        XCTAssertEqual(config.rules[0].match, "com.microsoft.VSCode")
        XCTAssertEqual(config.rules[0].slots.action(forSlot: 1),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
    }

    func testRoundTrips() throws {
        let config = Config.default
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testDefaultHasDictationDefaultAndNoRules() {
        XCTAssertEqual(Config.default.defaultAction, .dictation)
        XCTAssertTrue(Config.default.rules.isEmpty)
        XCTAssertEqual(Config.default.triggers.usb, [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F14", slot: 2),
            TriggerKey(key: "F15", slot: 3),
        ])
        XCTAssertEqual(Config.default.triggers.bluetooth, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(Config.default.triggers.primary(for: .usb), TriggerKey(key: "F13", slot: 1))
        XCTAssertEqual(Config.default.triggers.primary(for: .bluetooth), TriggerKey(key: "F13", slot: 1))
        // Union de-dupes F13 (shared) -> F13, F14, F15.
        XCTAssertEqual(Config.default.allTriggerKeys, [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F14", slot: 2),
            TriggerKey(key: "F15", slot: 3),
        ])
    }

    func testDecodesNewTriggersForm() throws {
        // The new per-transport form decodes natively, with distinct usb/bluetooth
        // lists and a de-duplicated union for the listener.
        let json = """
        {
          "triggers": {
            "usb": [ { "key": "F13", "slot": 1 } ],
            "bluetooth": [ { "key": "F16", "slot": 1 } ]
          },
          "dictationShortcut": { "modifiers": ["cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggers.usb, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.triggers.bluetooth, [TriggerKey(key: "F16", slot: 1)])
        XCTAssertEqual(config.triggers.primary(for: .usb), TriggerKey(key: "F13", slot: 1))
        XCTAssertEqual(config.triggers.primary(for: .bluetooth), TriggerKey(key: "F16", slot: 1))
        XCTAssertEqual(config.allTriggerKeys,
                       [TriggerKey(key: "F13", slot: 1), TriggerKey(key: "F16", slot: 1)])
    }

    func testInterimTriggerKeysAppliesToBothTransports() throws {
        // The interim flat-list form applies the same keys to BOTH transports,
        // preserving the prior listener behavior.
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
        let keys = [TriggerKey(key: "F16", slot: 1), TriggerKey(key: "F17", slot: 2)]
        XCTAssertEqual(config.triggers.usb, keys)
        XCTAssertEqual(config.triggers.bluetooth, keys)
        XCTAssertEqual(config.triggers.primary(for: .usb), TriggerKey(key: "F16", slot: 1))
    }

    func testLegacyTriggerKeyStringMigratesToBothTransports() throws {
        // Critical backward-compat: a legacy "triggerKey":"F13" string must migrate
        // to a single slot-1 entry on BOTH transports rather than failing to decode.
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
        XCTAssertEqual(config.triggers.usb, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.triggers.bluetooth, [TriggerKey(key: "F13", slot: 1)])
    }

    func testInterimTriggerKeysWinsOverLegacyWhenBothPresent() throws {
        // When both the legacy "triggerKey" string and the interim "triggerKeys"
        // array are present, the interim form must take precedence (legacy ignored),
        // and lands in both transports.
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
        XCTAssertEqual(config.triggers.usb, [TriggerKey(key: "F16", slot: 1)])
        XCTAssertEqual(config.triggers.bluetooth, [TriggerKey(key: "F16", slot: 1)])
    }

    func testTriggersWinsOverTriggerKeysWhenBothPresent() throws {
        // The new per-transport form takes precedence over the interim flat list.
        let json = """
        {
          "triggers": {
            "usb": [ { "key": "F13", "slot": 1 } ],
            "bluetooth": [ { "key": "F16", "slot": 1 } ]
          },
          "triggerKeys": [ { "key": "F19", "slot": 1 } ],
          "dictationShortcut": { "modifiers": ["cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggers.usb, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.triggers.bluetooth, [TriggerKey(key: "F16", slot: 1)])
    }

    func testEmptyTriggersMapFallsBackToDefault() throws {
        // A fully-empty triggers map (e.g. hand-edited) is treated as absent and
        // falls through to the default, so the listener never watches nothing.
        let json = """
        {
          "triggers": { "usb": [], "bluetooth": [] },
          "dictationShortcut": { "modifiers": ["cmd"], "key": "D" },
          "debounceMs": 250,
          "defaultAction": { "type": "dictation" },
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggers.usb, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(config.triggers.bluetooth, [TriggerKey(key: "F13", slot: 1)])
    }

    func testTriggersRoundTrips() throws {
        let config = Config(
            triggers: Triggers(
                usb: [TriggerKey(key: "F13", slot: 1)],
                bluetooth: [TriggerKey(key: "F16", slot: 1), TriggerKey(key: "F17", slot: 2)]),
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250,
            defaultAction: .dictation,
            rules: [])
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.triggers.usb, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(decoded.triggers.bluetooth,
                       [TriggerKey(key: "F16", slot: 1), TriggerKey(key: "F17", slot: 2)])
    }

    func testEncodeWritesTriggersFormOnly() throws {
        let config = Config.default
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["triggers"], "encoder should write triggers")
        XCTAssertNil(object?["triggerKeys"], "encoder should not write the interim triggerKeys")
        XCTAssertNil(object?["triggerKey"], "encoder should not write the legacy triggerKey")
        // The triggers object should carry both transports.
        let triggers = object?["triggers"] as? [String: Any]
        XCTAssertNotNil(triggers?["usb"])
        XCTAssertNotNil(triggers?["bluetooth"])
    }

    func testAllKeysDeDuplicatesAcrossTransports() {
        // A key present in both transports appears once in the listener's union.
        let triggers = Triggers(
            usb: [TriggerKey(key: "F16", slot: 1)],
            bluetooth: [TriggerKey(key: "F16", slot: 1)])
        XCTAssertEqual(triggers.allKeys, [TriggerKey(key: "F16", slot: 1)])
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
