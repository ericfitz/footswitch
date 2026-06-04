import Foundation

/// Builds the GATT write payloads that program an FS17Pro over Bluetooth LE, and
/// parses its read-back notification. The wire format is the PCsensor `footswitch`
/// report sequence (same as USB) with a leading `0x01` report-ID byte and a
/// data-report type byte of `0x81`. Pure (returns bytes); the CoreBluetooth writes
/// live in the app target (`BLEPedalProgrammer`).
///
/// Captured layout (see protocol notes):
///   header = [0x01, 0x01,0x81,0x08, pedal+1, 0,0,0,0]
///   data   = [0x01, 0x08,0x81, modifierBits, hidUsage, 0,0,0,0]
///   query  = [0x01, 0x01,0x82,0x08, pedal+1, 0,0,0,0]
public enum BLEProgramPayload {
    /// Leading report-ID byte present on every BLE payload.
    private static let reportID: UInt8 = 0x01
    /// Data-report key type byte used over BLE (high bit set, unlike USB's 0x01).
    private static let keyType: UInt8 = 0x81

    public static func header(pedalIndex: Int) -> [UInt8] {
        // byte[2] 0x81 here is the header/"set pedal" command opcode (query uses 0x82) —
        // distinct from the data report's keyType byte, despite the shared value.
        [reportID, 0x01, 0x81, 0x08, UInt8(pedalIndex + 1), 0, 0, 0, 0]
    }

    public static func query(pedalIndex: Int) -> [UInt8] {
        [reportID, 0x01, 0x82, 0x08, UInt8(pedalIndex + 1), 0, 0, 0, 0]
    }

    /// Returns the data payload for `combo`, or nil if the key is unknown.
    public static func data(combo: KeyCombo) -> [UInt8]? {
        guard let usage = HIDUsage.usage(for: combo.key) else { return nil }
        return [reportID, 0x08, keyType, DeviceModifier.bits(for: combo.modifiers), usage, 0, 0, 0, 0]
    }

    /// Parses a read-back notification value: strips the leading report-ID byte and
    /// delegates to `FootswitchProgram.parseKeyResponse`. Returns nil if too short.
    public static func parseNotification(_ value: [UInt8]) -> FootswitchProgram.StoredConfig? {
        guard value.count >= 2 else { return nil }
        return FootswitchProgram.parseKeyResponse(Array(value.dropFirst()))
    }
}
