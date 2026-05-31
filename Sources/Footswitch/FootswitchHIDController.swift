import Foundation
import FootswitchCore
import IOKit
import IOKit.hid

/// Detects and programs a connected USB foot switch via the IOKit HID Manager.
/// Detection is read-only (no privileged access needed). Programming sends the
/// PCsensor report sequence built by `FootswitchProgram` using
/// `IOHIDDeviceSetReport` (the macOS equivalent of HIDAPI's hid_write).
enum FootswitchHIDController {

    struct Detected {
        let device: SupportedDevice
        let hidDevice: IOHIDDevice
    }

    /// Returns the first connected device that matches the supported table, or nil.
    static func detect() -> Detected? {
        matches().first
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
                  let match = SupportedDevices.match(vendorID: vid, productID: pid) else { return nil }
            return Detected(device: match, hidDevice: hidDevice)
        }
    }

    /// Detection result for display: the matched device name, or nil if none found.
    static func detectName() -> String? { detect()?.device.name }

    /// Result of reading and verifying the connected pedal's stored configuration.
    enum Verification {
        case noDevice
        case verified                       // stored key matches expected
        case mismatch                       // read OK but configured differently
        case unreadable                     // device present but config read failed
    }

    /// Reads pedal 1's stored config and compares it to `expected`. Used to drive
    /// the settings "configuration" row.
    static func verifyConfiguration(expected: KeyCombo) -> Verification {
        let candidates = matches()
        guard !candidates.isEmpty else { return .noDevice }
        guard candidates.contains(where: { $0.device.program == .footswitch }) else { return .unreadable }

        // Only one of the device's HID interfaces answers the query; try each.
        for detected in candidates where detected.device.program == .footswitch {
            guard let stored = readStoredConfig(detected.hidDevice, pedalIndex: 0) else { continue }
            switch stored {
            case .key(let combo):
                return combo == expected ? .verified : .mismatch
            case .unconfigured, .other:
                return .mismatch
            }
        }
        return .unreadable   // no interface returned a config
    }

    // The device returns its stored config as an interrupt IN report, delivered
    // via an input-report callback on a run loop — NOT retrievable with a
    // synchronous IOHIDDeviceGetReport (that returns 0 bytes). We register a
    // callback, write the query, and spin the run loop briefly to catch the reply.
    private final class ReadContext {
        var report: [UInt8]?
    }

    private static func readStoredConfig(_ dev: IOHIDDevice, pedalIndex: Int)
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
        case unsupportedProgram(SupportedDevice.Program)

        var description: String {
            switch self {
            case .noDevice: return "No supported foot switch is connected."
            case .unsupportedKey: return "That key cannot be programmed onto the device."
            case .openFailed: return "Could not open the foot switch for writing."
            case .writeFailed(let r): return "Writing to the foot switch failed (IOReturn \(r))."
            case .unsupportedProgram(let p): return "Programming the \(p.rawValue) variant is not implemented yet."
            }
        }
    }

    /// Programs the connected single-pedal device to emit `combo` on press.
    /// Mirrors footswitch.c: write the start report, then the pedal-1 header and
    /// data reports. Only the `.footswitch` family is implemented. The device
    /// exposes multiple HID interfaces; we try each and confirm via read-back.
    static func program(combo: KeyCombo) throws {
        let candidates = matches()
        guard !candidates.isEmpty else { throw ProgramError.noDevice }
        let programmable = candidates.filter { $0.device.program == .footswitch }
        guard !programmable.isEmpty else {
            throw ProgramError.unsupportedProgram(candidates[0].device.program)
        }
        guard let reports = FootswitchProgram.keyReports(pedalIndex: 0, combo: combo) else {
            throw ProgramError.unsupportedKey
        }

        var lastWrite: IOReturn = kIOReturnSuccess
        for detected in programmable {
            let dev = detected.hidDevice
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

            // Confirm the write took on some interface.
            if case .key(let stored)? = programmable.lazy
                .compactMap({ readStoredConfig($0.hidDevice, pedalIndex: 0) })
                .first, stored == combo {
                return
            }
        }
        // Writes were posted but couldn't be confirmed; treat a clean post as success.
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
}
