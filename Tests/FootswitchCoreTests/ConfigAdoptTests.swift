// Tests/FootswitchCoreTests/ConfigAdoptTests.swift
import XCTest
@testable import FootswitchCore

final class ConfigAdoptTests: XCTestCase {
    private let fs17proBLE = SupportedDevice(vendorID: 0x245A, productID: 0x8276,
                                             program: .footswitchBLE, name: "FS17Pro")

    func testResolveEntryThenDefault() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1)])]
        XCTAssertEqual(Config.triggerKey(in: devices, forVendorID: 0x245A, productID: 0x8276, slot: 1), "F16")
        // Unknown device → code default for the slot.
        XCTAssertEqual(Config.triggerKey(in: devices, forVendorID: 0x1111, productID: 0x2222, slot: 2), "F14")
    }

    func testAdoptUpdatesExistingEntry() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1)])]
        let out = Config.adoptingTriggerKey(in: devices, key: "F19", slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1)])
    }

    func testAdoptSeedsEntryWhenConnectedDeviceHasNone() {
        let out = Config.adoptingTriggerKey(in: [], key: "F19", slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].resolved()?.vendorID, 0x245A)
        XCTAssertEqual(out[0].program, "footswitchBLE")
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1)])
    }

    func testAdoptRoundTripsThroughConfigCoding() throws {
        var config = Config.default
        config.devices = Config.adoptingTriggerKey(in: config.devices, key: "F19", slot: 1, for: fs17proBLE)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.triggerKey(forVendorID: 0x245A, productID: 0x8276, slot: 1), "F19")
    }
}
