import XCTest
@testable import FootswitchCore

final class CustomDeviceTests: XCTestCase {

    // MARK: ID parsing

    func testParsesHexWithPrefix() {
        XCTAssertEqual(CustomDevice.parseID("0x245A"), 0x245A)
        XCTAssertEqual(CustomDevice.parseID("0X8276"), 0x8276)
    }

    func testParsesBareHex() {
        // Bare strings are interpreted as hex (the USB convention).
        XCTAssertEqual(CustomDevice.parseID("c100"), 0xC100)
        XCTAssertEqual(CustomDevice.parseID("100"), 0x100)
    }

    func testParseRejectsGarbageAndOutOfRange() {
        XCTAssertNil(CustomDevice.parseID(""))
        XCTAssertNil(CustomDevice.parseID("0x"))
        XCTAssertNil(CustomDevice.parseID("zzzz"))
        XCTAssertNil(CustomDevice.parseID("0x1FFFF"))   // > 16-bit
        XCTAssertNil(CustomDevice.parseID("-1"))
    }

    // MARK: resolution / validation

    func testResolvesValidEntry() {
        let d = CustomDevice(vendorId: "0x3553", productId: "0xC100",
                             program: "footswitch", name: "My Pedal").resolved()
        XCTAssertEqual(d?.vendorID, 0x3553)
        XCTAssertEqual(d?.productID, 0xC100)
        XCTAssertEqual(d?.program, .footswitch)
        XCTAssertEqual(d?.name, "My Pedal")
    }

    func testResolveRejectsUnknownProgramFamily() {
        XCTAssertNil(CustomDevice(vendorId: "0x1234", productId: "0x5678",
                                  program: "bogusProtocol", name: "X").resolved())
    }

    func testResolveRejectsMalformedIDsAndBlankName() {
        XCTAssertNil(CustomDevice(vendorId: "nope", productId: "0x1",
                                  program: "footswitch", name: "X").resolved())
        XCTAssertNil(CustomDevice(vendorId: "0x1", productId: "0x1",
                                  program: "footswitch", name: "   ").resolved())
    }

    // MARK: merge with the built-in table

    func testCustomMatchAddsNewDevice() {
        let custom = [CustomDevice(vendorId: "0xAAAA", productId: "0xBBBB",
                                   program: "footswitch", name: "Clone Pedal")]
        // Not in the built-in table...
        XCTAssertNil(SupportedDevices.match(vendorID: 0xAAAA, productID: 0xBBBB))
        // ...but matched once custom is supplied.
        let d = SupportedDevices.match(vendorID: 0xAAAA, productID: 0xBBBB, custom: custom)
        XCTAssertEqual(d?.name, "Clone Pedal")
        XCTAssertEqual(d?.program, .footswitch)
    }

    func testCustomEntryOverridesBuiltIn() {
        // Re-map an existing built-in VID/PID to a different name/family.
        let custom = [CustomDevice(vendorId: "0x3553", productId: "0xB001",
                                   program: "footswitchBLE", name: "Overridden")]
        let d = SupportedDevices.match(vendorID: 0x3553, productID: 0xB001, custom: custom)
        XCTAssertEqual(d?.name, "Overridden")
        XCTAssertEqual(d?.program, .footswitchBLE)
    }

    func testInvalidCustomEntryIsSkippedAndFallsBackToBuiltIn() {
        let custom = [CustomDevice(vendorId: "garbage", productId: "0xB001",
                                   program: "footswitch", name: "Bad")]
        // The bad entry is skipped; the built-in 0x3553/0xB001 still resolves.
        let d = SupportedDevices.match(vendorID: 0x3553, productID: 0xB001, custom: custom)
        XCTAssertEqual(d?.name, "PCsensor FootSwitch")
    }

    func testNoMatchReturnsNilWithCustom() {
        XCTAssertNil(SupportedDevices.match(vendorID: 0x9999, productID: 0x9999, custom: []))
    }
}
