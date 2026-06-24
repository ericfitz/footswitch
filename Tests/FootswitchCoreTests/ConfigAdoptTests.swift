// Tests/FootswitchCoreTests/ConfigAdoptTests.swift
import XCTest
@testable import FootswitchCore

final class ConfigAdoptTests: XCTestCase {
    private let fs17proBLE = SupportedDevice(vendorID: 0x245A, productID: 0x8276,
                                             program: .footswitchBLE, name: "FS17Pro")

    func testResolveComboEntryThenDefault() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1, modifiers: [.control])])]
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x245A, productID: 0x8276, slot: 1),
                       KeyCombo(modifiers: [.control], key: "F16"))
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x1, productID: 0x2, slot: 2),
                       KeyCombo(modifiers: [], key: "F14"))
    }

    func testAdoptComboUpdatesExistingEntry() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1)])]
        let out = Config.adoptingTriggerCombo(in: devices, combo: KeyCombo(modifiers: [.option], key: "F19"),
                                              slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1, modifiers: [.option])])
    }

    func testAdoptComboSeedsEntryWhenDeviceHasNone() {
        let out = Config.adoptingTriggerCombo(in: [], combo: KeyCombo(modifiers: [.control], key: "F19"),
                                              slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].resolved()?.vendorID, 0x245A)
        XCTAssertEqual(out[0].program, "footswitchBLE")
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1, modifiers: [.control])])
    }

    func testAdoptComboRoundTripsThroughConfigCoding() throws {
        var config = Config.default
        config.devices = Config.adoptingTriggerCombo(in: config.devices,
                                                     combo: KeyCombo(modifiers: [.shift], key: "F19"),
                                                     slot: 1, for: fs17proBLE)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.triggerCombo(forVendorID: 0x245A, productID: 0x8276, slot: 1),
                       KeyCombo(modifiers: [.shift], key: "F19"))
    }
}
