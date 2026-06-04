import XCTest
@testable import FootswitchCore

final class FootswitchDeviceTests: XCTestCase {
    func testMatchesKnownDevice() {
        let d = SupportedDevices.match(vendorID: 0x3553, productID: 0xb001)
        XCTAssertEqual(d?.program, .footswitch)
        XCTAssertEqual(d?.vendorID, 0x3553)
    }

    func testScytheVariantsHaveCorrectProgram() {
        XCTAssertEqual(SupportedDevices.match(vendorID: 0x0426, productID: 0x3011)?.program, .scythe)
        XCTAssertEqual(SupportedDevices.match(vendorID: 0x055a, productID: 0x0998)?.program, .scythe2)
        XCTAssertEqual(SupportedDevices.match(vendorID: 0x5131, productID: 0x2019)?.program, .footswitch1p)
    }

    func testUnknownDeviceDoesNotMatch() {
        XCTAssertNil(SupportedDevices.match(vendorID: 0x1234, productID: 0x5678))
    }

    func testModifierBits() {
        XCTAssertEqual(DeviceModifier.bits(for: []), 0)
        XCTAssertEqual(DeviceModifier.bits(for: [.control]), 0x01)
        XCTAssertEqual(DeviceModifier.bits(for: [.shift]), 0x02)
        XCTAssertEqual(DeviceModifier.bits(for: [.option]), 0x04)
        XCTAssertEqual(DeviceModifier.bits(for: [.command]), 0x08)
        XCTAssertEqual(DeviceModifier.bits(for: [.control, .option, .command]), 0x01 | 0x04 | 0x08)
    }

    func testHIDUsageCodes() {
        XCTAssertEqual(HIDUsage.usage(for: "A"), 0x04)
        XCTAssertEqual(HIDUsage.usage(for: "d"), 0x07)   // case-insensitive
        XCTAssertEqual(HIDUsage.usage(for: "F13"), 0x68) // note: NOT 0x69 (that's macOS keycode)
        XCTAssertEqual(HIDUsage.usage(for: "Return"), 0x28)
        XCTAssertNil(HIDUsage.usage(for: "NotAKey"))
    }

    func testKeyReportsForF13() {
        let reports = FootswitchProgram.keyReports(pedalIndex: 0, combo: KeyCombo(modifiers: [], key: "F13"))
        XCTAssertEqual(reports?.header, [0x01, 0x81, 0x08, 0x01, 0, 0, 0, 0])
        // data: [0x08, KEY_TYPE=1, mods=0, usage(F13)=0x68, 0,0,0,0]
        XCTAssertEqual(reports?.data, [0x08, 0x01, 0x00, 0x68, 0, 0, 0, 0])
    }

    func testKeyReportsWithModifiers() {
        let reports = FootswitchProgram.keyReports(
            pedalIndex: 0, combo: KeyCombo(modifiers: [.command, .shift], key: "A"))
        // mods = WIN(0x08) | SHIFT(0x02) = 0x0a ; usage(A)=0x04
        XCTAssertEqual(reports?.data, [0x08, 0x01, 0x0a, 0x04, 0, 0, 0, 0])
    }

    func testKeyReportsNilForUnknownKey() {
        XCTAssertNil(FootswitchProgram.keyReports(pedalIndex: 0, combo: KeyCombo(modifiers: [], key: "Nope")))
    }

    func testStartReport() {
        XCTAssertEqual(FootswitchProgram.start, [0x01, 0x80, 0x08, 0, 0, 0, 0, 0])
    }

    func testQueryReport() {
        XCTAssertEqual(FootswitchProgram.queryReport(pedalIndex: 0), [0x01, 0x82, 0x08, 0x01, 0, 0, 0, 0])
    }

    func testHIDUsageReverseLookupRoundTrips() {
        XCTAssertEqual(HIDUsage.name(forUsage: 0x68), "F13")
        XCTAssertEqual(HIDUsage.usage(for: HIDUsage.name(forUsage: 0x68)!), 0x68)
        XCTAssertEqual(HIDUsage.name(forUsage: 0x04), "A")
        XCTAssertEqual(HIDUsage.name(forUsage: 0x28), "Return") // canonical over ENTER
        XCTAssertNil(HIDUsage.name(forUsage: 0xFE))
    }

    func testModifiersFromBits() {
        XCTAssertEqual(DeviceModifier.modifiers(fromBits: 0), [])
        XCTAssertEqual(DeviceModifier.modifiers(fromBits: 0x08), [.command])  // WIN
        XCTAssertEqual(DeviceModifier.modifiers(fromBits: 0x80), [.command])  // R_WIN -> command
        XCTAssertEqual(DeviceModifier.modifiers(fromBits: 0x01 | 0x04 | 0x08),
                       [.control, .option, .command])
    }

    func testParseUnconfiguredResponse() {
        let r: [UInt8] = [0x08, 0x00, 0x00, 0x00, 0, 0, 0, 0]
        XCTAssertEqual(FootswitchProgram.parseKeyResponse(r), .unconfigured)
    }

    func testParseKeyResponseF13() {
        // type=1, mods=0, usage(F13)=0x68
        let r: [UInt8] = [0x08, 0x01, 0x00, 0x68, 0, 0, 0, 0]
        XCTAssertEqual(FootswitchProgram.parseKeyResponse(r), .key(KeyCombo(modifiers: [], key: "F13")))
    }

    func testParseKeyResponseWithType0x81() {
        let r: [UInt8] = [0x08, 0x81, 0x08, 0x04, 0, 0, 0, 0] // command + A
        XCTAssertEqual(FootswitchProgram.parseKeyResponse(r), .key(KeyCombo(modifiers: [.command], key: "A")))
    }

    func testParseMouseResponseIsOther() {
        let r: [UInt8] = [0x08, 0x02, 0x00, 0x00, 0x01, 0, 0, 0] // type 2 = mouse
        XCTAssertEqual(FootswitchProgram.parseKeyResponse(r), .other)
    }

    func testMatchesFS17ProUSB() {
        let d = SupportedDevices.match(vendorID: 0x3553, productID: 0xc100)
        XCTAssertEqual(d?.program, .footswitch)
        XCTAssertEqual(d?.name, "PCsensor FS17Pro")
    }

    func testMatchesFS17ProBLE() {
        let d = SupportedDevices.match(vendorID: 0x245A, productID: 0x8276)
        XCTAssertEqual(d?.program, .footswitchBLE)
        XCTAssertEqual(d?.name, "PCsensor FS17Pro")
    }

    func testSlotNamespace() {
        XCTAssertEqual(Slot.maxCount, 3)
        XCTAssertEqual(Array(Slot.validRange), [1, 2, 3])
        XCTAssertTrue(Slot.isValid(1))
        XCTAssertTrue(Slot.isValid(3))
        XCTAssertFalse(Slot.isValid(0))
        XCTAssertFalse(Slot.isValid(4))
    }

    func testKeyReportsEncodePedalIndexInByte3() {
        // slot i (1-based) -> pedalIndex i-1 -> device byte i.
        for slot in Slot.validRange {
            let reports = FootswitchProgram.keyReports(
                pedalIndex: slot - 1, combo: KeyCombo(modifiers: [], key: "F13"))
            XCTAssertEqual(reports?.header[3], UInt8(slot))
            XCTAssertEqual(FootswitchProgram.queryReport(pedalIndex: slot - 1)[3], UInt8(slot))
        }
    }
}
