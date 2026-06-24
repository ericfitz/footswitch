import Foundation
import FootswitchCore
import IOKit
import IOKit.hid

/// Detects and programs a connected USB foot switch via the IOKit HID Manager.
/// Detection is read-only (no privileged access needed). Programming sends the
/// PCsensor report sequence built by `FootswitchProgram` using
/// `IOHIDDeviceSetReport` (the macOS equivalent of HIDAPI's hid_write).
enum FootswitchHIDController {

    /// User/config device-table entries merged with the built-in table during
    /// detection (issues #4/#9). Set by AppDelegate on launch/reload from
    /// `Config.devices`. Kept process-wide so the static detection API needn't
    /// thread a Config through every call.
    nonisolated(unsafe) static var registeredDevices: [Device] = []

    struct Detected {
        let device: SupportedDevice
        let hidDevice: IOHIDDevice
    }

    /// A `PedalProgrammer` bound to one matched USB HID device and its sibling
    /// interfaces (one carries the config endpoint). Wraps the existing IOKit logic.
    struct USBPedalProgrammer: PedalProgrammer {
        let detected: FootswitchHIDController.Detected
        /// All `.footswitch`-family interfaces of the same device (one answers config).
        let interfaces: [IOHIDDevice]

        var deviceName: String { detected.device.name }

        func readStoredConfig(slot: Int) -> FootswitchProgram.StoredConfig? {
            for dev in interfaces {
                if let stored = FootswitchHIDController.readStoredConfig(dev, pedalIndex: slot - 1) {
                    return stored
                }
            }
            return nil
        }

        func program(combo: KeyCombo, slot: Int) throws {
            try FootswitchHIDController.programUSB(interfaces: interfaces, combo: combo, slot: slot)
        }

        func info() -> String {
            FootswitchHIDController.usbInfo(detected: detected, interfaces: interfaces)
        }
    }

    /// Returns a programmer for the best-matching connected device, or nil if none.
    /// Derives the selected device from `orderedMatches().first`, the same value
    /// `detect()` returns, so the label and the action always target one device.
    static func programmer() -> PedalProgrammer? {
        let ordered = orderedMatches()
        guard let first = ordered.first else { return nil }
        switch first.device.program {
        case .footswitch:
            // Gather every `.footswitch`-family interface of the device (one carries
            // the config endpoint); selection itself is keyed off `first`.
            let ifaces = ordered.filter { $0.device.program == .footswitch }.map { $0.hidDevice }
            return USBPedalProgrammer(detected: first, interfaces: ifaces)
        case .footswitchBLE:
            return BLEPedalProgrammer(deviceName: first.device.name)
        default:
            return nil
        }
    }

    /// Returns the first connected device that matches the supported table, or nil.
    /// Uses `orderedMatches()` so the result is deterministic and agrees with the
    /// device `programmer()` targets.
    static func detect() -> Detected? {
        orderedMatches().first
    }

    /// `matches()` results in a deterministic, preference-ordered list:
    /// USB-programmable `.footswitch` first, then `.footswitchBLE`, then others.
    /// Makes `detect()` (the label) and `programmer()` (the action) agree on which
    /// device they refer to, regardless of HID Set iteration order.
    private static func orderedMatches() -> [Detected] {
        func rank(_ p: SupportedDevice.Program) -> Int {
            switch p {
            case .footswitch: return 0
            case .footswitchBLE: return 1
            default: return 2
            }
        }
        return matches().sorted { a, b in
            let (ra, rb) = (rank(a.device.program), rank(b.device.program))
            if ra != rb { return ra < rb }
            if a.device.vendorID != b.device.vendorID { return a.device.vendorID < b.device.vendorID }
            return a.device.productID < b.device.productID
        }
    }

    /// All connected HID interfaces matching the supported table. These devices
    /// expose several HID interfaces; only one carries the config endpoint, so
    /// read/program operations try each in turn.
    private static func matches() -> [Detected] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil) // match all; we filter by VID/PID
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap { hidDevice in
            guard let vid = intProperty(hidDevice, kIOHIDVendorIDKey),
                  let pid = intProperty(hidDevice, kIOHIDProductIDKey),
                  let match = SupportedDevices.match(vendorID: vid, productID: pid,
                                                     devices: registeredDevices) else { return nil }
            return Detected(device: match, hidDevice: hidDevice)
        }
    }

    /// Reads slot `slot` (1-based) and compares it to `expected`.
    static func verifyConfiguration(expected: KeyCombo, slot: Int = 1) -> PedalVerification {
        guard let p = programmer() else { return .noDevice }
        return p.verify(expected: expected, slot: slot)
    }

    /// Probes how many pedals the connected USB device can report a config for.
    /// A slot is "present" if its query returns a parseable StoredConfig. Count =
    /// highest present slot, clamped to 1...Slot.maxCount. BLE / no device -> 1.
    /// EXPENSIVE: each slot read spins the run loop up to ~500ms (~1.5s for three).
    /// MUST be called off the main thread.
    static func detectedSlotCount() -> Int {
        guard let first = orderedMatches().first, first.device.program == .footswitch else {
            return 1
        }
        let interfaces = orderedMatches()
            .filter { $0.device.program == .footswitch }.map { $0.hidDevice }
        var highest = 1
        for slot in Slot.validRange {
            let present = interfaces.contains { dev in
                readStoredConfig(dev, pedalIndex: slot - 1) != nil
            }
            if present { highest = slot }
        }
        return min(max(highest, 1), Slot.maxCount)
    }

    /// A human-readable, read-only report of the connected device: USB identity,
    /// the matched model/protocol, and the pedal's currently-programmed key.
    /// Returns nil if no supported device is connected.
    static func deviceInfo() -> String? { programmer()?.info() }

    /// Builds the USB device-info report. Identity comes from `detected.hidDevice`;
    /// the stored configuration is read from `interfaces`.
    static func usbInfo(detected: Detected, interfaces: [IOHIDDevice]) -> String {
        let dev = detected.hidDevice
        var lines: [String] = []

        func hex(_ n: Int?) -> String { n.map { String(format: "0x%04X", $0) } ?? "—" }

        lines.append("USB device")
        lines.append("  Vendor:      \(stringProperty(dev, kIOHIDManufacturerKey) ?? "—") (\(hex(intProperty(dev, kIOHIDVendorIDKey))))")
        lines.append("  Product:     \(stringProperty(dev, kIOHIDProductKey) ?? "—") (\(hex(intProperty(dev, kIOHIDProductIDKey))))")
        if let serial = stringProperty(dev, kIOHIDSerialNumberKey), !serial.isEmpty {
            lines.append("  Serial:      \(serial)")
        }
        if let loc = intProperty(dev, kIOHIDLocationIDKey) {
            lines.append("  Location ID: \(String(format: "0x%08X", loc))")
        }
        if let ver = intProperty(dev, kIOHIDVersionNumberKey) {
            lines.append("  Version:     \(ver)")
        }

        lines.append("")
        lines.append("Recognized model")
        lines.append("  \(detected.device.name)")
        lines.append("  Protocol: \(detected.device.program.rawValue)")

        lines.append("")
        lines.append("Programmed configuration")
        if detected.device.program == .footswitch,
           let stored = interfaces
               .lazy.compactMap({ readStoredConfig($0, pedalIndex: 0) }).first {
            switch stored {
            case .key(let combo):
                lines.append("  Emits: \(KeyComboFormatter.display(combo))")
            case .unconfigured:
                lines.append("  Unconfigured")
            case .other:
                lines.append("  Non-key configuration (mouse / string)")
            }
        } else {
            lines.append("  Could not read configuration")
        }

        return lines.joined(separator: "\n")
    }

    // The device returns its stored config as an interrupt IN report, delivered
    // via an input-report callback on a run loop — NOT retrievable with a
    // synchronous IOHIDDeviceGetReport (that returns 0 bytes). We register a
    // callback, write the query, and spin the run loop briefly to catch the reply.
    private final class ReadContext {
        var report: [UInt8]?
    }

    fileprivate static func readStoredConfig(_ dev: IOHIDDevice, pedalIndex: Int)
        -> FootswitchProgram.StoredConfig? {
        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let ctx = ReadContext()
        let bufLen = 16
        let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufLen)
        defer { inputBuffer.deallocate() }

        let callback: IOHIDReportCallback = { context, _, _, _, _, reportPtr, reportLen in
            guard let context else { return }
            let c = Unmanaged<ReadContext>.fromOpaque(context).takeUnretainedValue()
            if c.report == nil, reportLen >= 4 {
                c.report = Array(UnsafeBufferPointer(start: reportPtr, count: min(Int(reportLen), 8)))
            }
        }

        IOHIDDeviceRegisterInputReportCallback(
            dev, inputBuffer, bufLen, callback, Unmanaged.passUnretained(ctx).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, bufLen, nil, nil)
        }

        let query = FootswitchProgram.queryReport(pedalIndex: pedalIndex)
        do { try setReport(dev, query) } catch { return nil }

        // Spin the run loop up to ~500ms waiting for the input report.
        let deadline = Date().addingTimeInterval(0.5)
        while ctx.report == nil, Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        guard let report = ctx.report else { return nil }
        return FootswitchProgram.parseKeyResponse(report)
    }

    enum ProgramError: Error, CustomStringConvertible {
        case noDevice
        case unsupportedKey
        case openFailed
        case writeFailed(IOReturn)

        var description: String {
            switch self {
            case .noDevice: return "No supported foot switch is connected."
            case .unsupportedKey: return "That key cannot be programmed onto the device."
            case .openFailed: return "Could not open the foot switch for writing."
            case .writeFailed(let r): return "Writing to the foot switch failed (IOReturn \(r))."
            }
        }
    }

    /// Programs slot `slot` (1-based) of the connected device to emit `combo`.
    static func program(combo: KeyCombo, slot: Int = 1) throws {
        guard let p = programmer() else { throw ProgramError.noDevice }
        try p.program(combo: combo, slot: slot)
    }

    /// Programs the passed-in USB HID `interfaces` to emit `combo` on press.
    /// Mirrors footswitch.c: write the start report, then the pedal-1 header and
    /// data reports. The device exposes multiple HID interfaces; we try each and
    /// confirm via read-back.
    static func programUSB(interfaces: [IOHIDDevice], combo: KeyCombo, slot: Int = 1) throws {
        guard !interfaces.isEmpty else { throw ProgramError.noDevice }
        guard let reports = FootswitchProgram.keyReports(pedalIndex: slot - 1, combo: combo) else {
            throw ProgramError.unsupportedKey
        }
        var lastWrite: IOReturn = kIOReturnSuccess
        for dev in interfaces {
            guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
            do {
                try setReport(dev, FootswitchProgram.start)
                usleep(1_000_000) // 1s settle, matching the reference implementation
                try setReport(dev, reports.header)
                usleep(30_000)
                try setReport(dev, reports.data)
                usleep(30_000)
            } catch let ProgramError.writeFailed(r) {
                lastWrite = r
                IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
                continue
            }
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            if case .key(let stored)? = interfaces.lazy
                .compactMap({ readStoredConfig($0, pedalIndex: slot - 1) }).first, stored == combo {
                return
            }
        }
        if lastWrite == kIOReturnSuccess { return }
        throw ProgramError.writeFailed(lastWrite)
    }

    // MARK: - helpers

    private static func setReport(_ dev: IOHIDDevice, _ bytes: [UInt8]) throws {
        // The reports are 8-byte output reports with report ID in byte 0 (0x01).
        let reportID = CFIndex(bytes[0])
        let result = bytes.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, reportID, buf.baseAddress!, buf.count)
        }
        guard result == kIOReturnSuccess else { throw ProgramError.writeFailed(result) }
    }

    private static func intProperty(_ dev: IOHIDDevice, _ key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(dev, key as CFString) as? Int else { return nil }
        return value
    }

    private static func stringProperty(_ dev: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(dev, key as CFString) as? String
    }
}
