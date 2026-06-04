import XCTest
@testable import FootswitchCore

final class BLEProgramPayloadTests: XCTestCase {
    // Captured from ElfKey-over-BLE programming the FS17Pro to F16 (pedal 2).
    // See docs/superpowers/specs/2026-06-02-fs17pro-ble-programming-protocol.md

    func testHeaderPayloadMatchesCapture() {
        // pedalIndex 1 -> pedal+1 = 2
        XCTAssertEqual(BLEProgramPayload.header(pedalIndex: 1),
                       [0x01, 0x01, 0x81, 0x08, 0x02, 0, 0, 0, 0])
    }

    func testHeaderPayloadPedalIndexZero() {
        // pedalIndex 0 -> pedal+1 = 1 (byte 4)
        XCTAssertEqual(BLEProgramPayload.header(pedalIndex: 0),
                       [0x01, 0x01, 0x81, 0x08, 0x01, 0, 0, 0, 0])
    }

    func testDataPayloadMatchesCapture() {
        // F16 usage 0x6b, no modifiers, type byte 0x81
        let combo = KeyCombo(modifiers: [], key: "F16")
        XCTAssertEqual(BLEProgramPayload.data(combo: combo),
                       [0x01, 0x08, 0x81, 0x00, 0x6b, 0, 0, 0, 0])
    }

    func testDataPayloadWithModifiers() {
        // command (0x08) + A (0x04), type byte 0x81
        let combo = KeyCombo(modifiers: [.command], key: "A")
        XCTAssertEqual(BLEProgramPayload.data(combo: combo),
                       [0x01, 0x08, 0x81, 0x08, 0x04, 0, 0, 0, 0])
    }

    func testQueryPayloadMatchesCapture() {
        XCTAssertEqual(BLEProgramPayload.query(pedalIndex: 1),
                       [0x01, 0x01, 0x82, 0x08, 0x02, 0, 0, 0, 0])
    }

    func testDataPayloadNilForUnknownKey() {
        XCTAssertNil(BLEProgramPayload.data(combo: KeyCombo(modifiers: [], key: "Nope")))
    }

    func testParseNotificationStripsReportIDAndDecodes() {
        // Notification value from capture: 01 08 81 00 6b ...
        let notif: [UInt8] = [0x01, 0x08, 0x81, 0x00, 0x6b, 0, 0, 0, 0]
        XCTAssertEqual(BLEProgramPayload.parseNotification(notif),
                       .key(KeyCombo(modifiers: [], key: "F16")))
    }

    func testParseNotificationTooShortIsNil() {
        XCTAssertNil(BLEProgramPayload.parseNotification([0x01]))
    }
}
