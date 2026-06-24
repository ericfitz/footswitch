// Tests/FootswitchCoreTests/TriggerKeyModifierTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerKeyModifierTests: XCTestCase {
    func testBareFormDecodesToNoModifiers() throws {
        let json = #"{"key":"F13","slot":1}"#
        let tk = try JSONDecoder().decode(TriggerKey.self, from: Data(json.utf8))
        XCTAssertEqual(tk.modifiers, [])
    }

    func testModifiersRoundTrip() throws {
        let tk = TriggerKey(key: "F13", slot: 1, modifiers: [.control, .shift])
        let decoded = try JSONDecoder().decode(TriggerKey.self, from: JSONEncoder().encode(tk))
        XCTAssertEqual(decoded, tk)
    }

    func testEncodeOmitsEmptyModifiers() throws {
        let tk = TriggerKey(key: "F13", slot: 1)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tk)) as? [String: Any]
        XCTAssertNil(obj?["modifiers"])
    }

    func testComboAccessor() {
        XCTAssertEqual(TriggerKey(key: "F13", slot: 1, modifiers: [.control]).combo,
                       KeyCombo(modifiers: [.control], key: "F13"))
    }

    func testModifiersForFlagBitsCanonicalOrder() {
        // control=0x40000, option=0x80000, shift=0x20000, command=0x100000
        let bits: UInt64 = 0x40000 | 0x20000   // control + shift
        XCTAssertEqual(Keymap.modifiers(forFlagBits: bits), [.control, .shift])
        XCTAssertEqual(Keymap.modifiers(forFlagBits: 0), [])
    }

    func testTriggerComboResolution() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1, modifiers: [.control])])]
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x245A, productID: 0x8276, slot: 1),
                       KeyCombo(modifiers: [.control], key: "F16"))
        // Unknown device → code default (bare F14 for slot 2).
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x1, productID: 0x2, slot: 2),
                       KeyCombo(modifiers: [], key: "F14"))
    }

    func testAdoptComboStoresModifiers() {
        let dev = SupportedDevice(vendorID: 0x245A, productID: 0x8276, program: .footswitchBLE, name: "FS17Pro")
        let out = Config.adoptingTriggerCombo(in: [], combo: KeyCombo(modifiers: [.option], key: "F19"),
                                              slot: 1, for: dev)
        XCTAssertEqual(out.first?.triggers, [TriggerKey(key: "F19", slot: 1, modifiers: [.option])])
    }

    func testListenerKeysKeepsSameKeyDifferentModifiers() {
        let config = Config(
            devices: [Device(vendorId: "0x1", productId: "0x2", program: "footswitch", name: "A",
                             triggers: [TriggerKey(key: "F13", slot: 1),
                                        TriggerKey(key: "F13", slot: 2, modifiers: [.control])])],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        XCTAssertEqual(config.listenerKeys.count, 2)
    }
}
