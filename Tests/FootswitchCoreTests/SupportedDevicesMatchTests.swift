// Tests/FootswitchCoreTests/SupportedDevicesMatchTests.swift
import XCTest
@testable import FootswitchCore

final class SupportedDevicesMatchTests: XCTestCase {
    func testBuiltInStillMatchesWithEmptyDevices() {
        let m = SupportedDevices.match(vendorID: 0x0c45, productID: 0x7403, devices: [])
        XCTAssertEqual(m?.program, .footswitch)
    }

    func testDeviceEntryExtendsTable() {
        let custom = Device(vendorId: "0xAAAA", productId: "0xBBBB",
                            program: "footswitch", name: "Clone")
        let m = SupportedDevices.match(vendorID: 0xAAAA, productID: 0xBBBB, devices: [custom])
        XCTAssertEqual(m?.name, "Clone")
    }

    func testDeviceEntryOverridesBuiltIn() {
        let override = Device(vendorId: "0x0c45", productId: "0x7403",
                              program: "footswitch", name: "My Override")
        let m = SupportedDevices.match(vendorID: 0x0c45, productID: 0x7403, devices: [override])
        XCTAssertEqual(m?.name, "My Override")
    }

    func testMalformedEntrySkipped() {
        let bad = Device(vendorId: "zz", productId: "zz", program: "nope", name: "")
        let m = SupportedDevices.match(vendorID: 0x0c45, productID: 0x7403, devices: [bad])
        XCTAssertEqual(m?.name, "PCsensor FootSwitch") // falls through to built-in
    }
}
