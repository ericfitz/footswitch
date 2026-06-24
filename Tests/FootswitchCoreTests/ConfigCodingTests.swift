// Tests/FootswitchCoreTests/ConfigCodingTests.swift
import XCTest
@testable import FootswitchCore

final class ConfigCodingTests: XCTestCase {
    // MARK: New shape

    func testNewDevicesShapeRoundTrips() throws {
        let config = Config(
            devices: [Device(vendorId: "0x245A", productId: "0x8276",
                             program: "footswitchBLE", name: "FS17Pro",
                             triggers: [TriggerKey(key: "F16", slot: 1)])],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testDefaultRoundTripsWithEmptyDevices() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(Config.default))
        XCTAssertEqual(decoded, Config.default)
        XCTAssertEqual(decoded.devices, [])
    }

    func testEncoderWritesDevicesNotLegacyKeys() throws {
        let obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(Config.default)) as? [String: Any]
        XCTAssertNotNil(obj?["devices"])
        XCTAssertNil(obj?["triggers"])
        XCTAssertNil(obj?["triggerKeys"])
        XCTAssertNil(obj?["customDevices"])
    }

    // MARK: Resolution

    func testResolutionEntryVsDefault() {
        let config = Config(
            devices: [Device(vendorId: "0x245A", productId: "0x8276",
                             program: "footswitchBLE", name: "FS17Pro",
                             triggers: [TriggerKey(key: "F16", slot: 1)])],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        XCTAssertEqual(config.triggerKey(forVendorID: 0x245A, productID: 0x8276, slot: 1), "F16")
        // Unknown device → code default.
        XCTAssertEqual(config.triggerKey(forVendorID: 0x1111, productID: 0x2222, slot: 2), "F14")
    }

    func testListenerKeysUnionAndFallback() {
        let config = Config(
            devices: [
                Device(vendorId: "0x1", productId: "0x2", program: "footswitch",
                       name: "A", triggers: [TriggerKey(key: "F13", slot: 1)]),
                Device(vendorId: "0x3", productId: "0x4", program: "footswitchBLE",
                       name: "B", triggers: [TriggerKey(key: "F13", slot: 1),
                                             TriggerKey(key: "F16", slot: 2)]),
            ],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        XCTAssertEqual(config.listenerKeys,
                       [TriggerKey(key: "F13", slot: 1), TriggerKey(key: "F16", slot: 2)])
        XCTAssertEqual(Config.default.listenerKeys, Config.defaultTriggerKeys)
    }

    // MARK: Legacy migration (lossless)

    func testMigratesLegacyTriggersIntoSeededDevices() throws {
        let json = """
        {
          "triggers": {
            "usb": [ {"key":"F13","slot":1}, {"key":"F14","slot":2}, {"key":"F15","slot":3} ],
            "bluetooth": [ {"key":"F16","slot":1} ]
          },
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs": 250, "defaultAction": { "type":"dictation" }, "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.devices.count, 10) // all built-ins seeded
        // FS17Pro BLE gets the bluetooth keys.
        XCTAssertEqual(config.triggerKeys(forVendorID: 0x245A, productID: 0x8276),
                       [TriggerKey(key: "F16", slot: 1)])
        // A USB built-in gets the usb keys.
        XCTAssertEqual(config.triggerKeys(forVendorID: 0x0c45, productID: 0x7403),
                       [TriggerKey(key: "F13", slot: 1),
                        TriggerKey(key: "F14", slot: 2),
                        TriggerKey(key: "F15", slot: 3)])
    }

    func testMigratesInterimTriggerKeysToAllDevices() throws {
        let json = """
        { "triggerKeys": [ {"key":"F19","slot":1} ],
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        // Interim flat list applied to both transports → every device gets F19.
        XCTAssertEqual(config.triggerKey(forVendorID: 0x245A, productID: 0x8276, slot: 1), "F19")
        XCTAssertEqual(config.triggerKey(forVendorID: 0x0c45, productID: 0x7403, slot: 1), "F19")
    }

    func testMigratesLegacyStringTriggerKey() throws {
        let json = """
        { "triggerKey":"F13",
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggerKey(forVendorID: 0x0c45, productID: 0x7403, slot: 1), "F13")
    }

    func testMigrationCustomDeviceOverridesBuiltIn() throws {
        let json = """
        { "triggerKey":"F13",
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [],
          "customDevices": [
            { "vendorId":"0x0c45", "productId":"0x7403", "program":"footswitch", "name":"My Clone" }
          ] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        // Custom entry replaces the built-in on the same VID/PID (no duplicate).
        XCTAssertEqual(config.devices.count, 10)
        XCTAssertEqual(config.device(forVendorID: 0x0c45, productID: 0x7403)?.name, "My Clone")
    }

    func testMigrationIsByteStableOnReencode() throws {
        let json = """
        { "triggers": { "usb":[{"key":"F13","slot":1}], "bluetooth":[{"key":"F16","slot":1}] },
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [] }
        """
        let first = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let second = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(first, second)
    }

    // MARK: defaultAction migration (unchanged behavior)

    func testLegacyKeyComboDefaultMigratesToDictation() throws {
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
