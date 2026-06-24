// Tests/FootswitchCoreTests/DeviceTests.swift
import XCTest
@testable import FootswitchCore

final class DeviceTests: XCTestCase {
    func testResolvedValidatesIdentity() {
        let d = Device(vendorId: "0x245A", productId: "8276",
                       program: "footswitchBLE", name: "FS17Pro")
        let r = d.resolved()
        XCTAssertEqual(r?.vendorID, 0x245A)
        XCTAssertEqual(r?.productID, 0x8276)
        XCTAssertEqual(r?.program, .footswitchBLE)
    }

    func testResolvedRejectsMalformed() {
        XCTAssertNil(Device(vendorId: "zz", productId: "1", program: "footswitch", name: "x").resolved())
        XCTAssertNil(Device(vendorId: "1", productId: "2", program: "nope", name: "x").resolved())
        XCTAssertNil(Device(vendorId: "1", productId: "2", program: "footswitch", name: "  ").resolved())
    }

    func testProgramTransport() {
        XCTAssertEqual(SupportedDevice.Program.footswitchBLE.transport, .bluetooth)
        XCTAssertEqual(SupportedDevice.Program.footswitch.transport, .usb)
        XCTAssertEqual(SupportedDevice.Program.scythe.transport, .usb)
    }

    func testTriggersOptionalOnDecode() throws {
        let json = #"{"vendorId":"0x1","productId":"0x2","program":"footswitch","name":"X"}"#
        let d = try JSONDecoder().decode(Device.self, from: Data(json.utf8))
        XCTAssertEqual(d.triggers, [])
    }

    func testEncodeOmitsEmptyTriggers() throws {
        let d = Device(vendorId: "0x1", productId: "0x2", program: "footswitch", name: "X")
        let obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(d)) as? [String: Any]
        XCTAssertNil(obj?["triggers"])
    }

    func testAdoptComboReplacesAndAppends() {
        let base = Device(vendorId: "0x1", productId: "0x2", program: "footswitch",
                          name: "X", triggers: [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(base.adopting(combo: KeyCombo(modifiers: [.control], key: "F19"), slot: 1).triggers,
                       [TriggerKey(key: "F19", slot: 1, modifiers: [.control])])
        XCTAssertEqual(base.adopting(combo: KeyCombo(modifiers: [], key: "F14"), slot: 2).triggers,
                       [TriggerKey(key: "F13", slot: 1), TriggerKey(key: "F14", slot: 2)])
    }
}
