import Foundation
import CoreBluetooth
import FootswitchCore

/// Programs an FS17Pro over Bluetooth LE via GATT. Drives CoreBluetooth's async
/// API on a private queue and exposes a synchronous-looking `program`/`readStoredConfig`
/// that block (with a timeout) on a semaphore.
///
/// Threading invariant: must NOT be called on the internal `queue` (the delegate
/// queue) — doing so would deadlock the blocking semaphore waits, and is asserted
/// against. Calling on the main thread is currently safe (queue != main), but Task 7
/// moves the call off-main anyway.
///
/// GATT layout (reverse-engineered): vendor service FFF0, write characteristic
/// FFF2, notify characteristic FFF1. Payloads come from `BLEProgramPayload`.
final class BLEPedalProgrammer: NSObject, PedalProgrammer {
    let deviceName: String

    private let hidServiceUUID = CBUUID(string: "1812")
    private let serviceUUID = CBUUID(string: "FFF0")
    private let writeUUID = CBUUID(string: "FFF2")
    private let notifyUUID = CBUUID(string: "FFF1")
    // BLE addresses this device's single pedal as pedal index 1: the capture showed
    // the firmware refers to it as "pedal 2" (= pedalIndex + 1 in the payload). This
    // is deliberately distinct from the USB path, which uses pedalIndex 0.
    private let pedalIndex = 1
    private let timeout: TimeInterval = 8

    private let queue = DispatchQueue(label: "footswitch.ble")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    // Operation state, guarded by `queue`.
    private var readySemaphore = DispatchSemaphore(value: 0)
    private var notifySemaphore = DispatchSemaphore(value: 0)
    private var writeSemaphore = DispatchSemaphore(value: 0)
    private var lastNotification: [UInt8]?
    private var setupError: Error?

    enum BLEError: Error, CustomStringConvertible {
        case poweredOff, notFound, discoverFailed, timedOut, writeFailed
        var description: String {
            switch self {
            case .poweredOff:     return "Bluetooth is powered off."
            case .notFound:       return "FS17Pro not found over Bluetooth (is it connected?)."
            case .discoverFailed: return "Could not find the FS17Pro configuration service."
            case .timedOut:       return "Timed out talking to the FS17Pro over Bluetooth."
            case .writeFailed:    return "Writing to the FS17Pro over Bluetooth failed."
            }
        }
    }

    init(deviceName: String) {
        self.deviceName = deviceName
        super.init()
    }

    // MARK: PedalProgrammer

    func readStoredConfig() -> FootswitchProgram.StoredConfig? {
        do {
            try ensureReady()
            return try queryReadBack()
        } catch { return nil }
    }

    func program(combo: KeyCombo) throws {
        guard let data = BLEProgramPayload.data(combo: combo) else { throw BLEError.writeFailed }
        try ensureReady()
        try writeValue(BLEProgramPayload.header(pedalIndex: pedalIndex))
        try writeValue(data)
        // read back to confirm
        if case .key(let stored)? = try? queryReadBack(), stored == combo { return }
        // Some firmware needs a moment; one retry of the query.
        if case .key(let stored)? = try? queryReadBack(), stored == combo { return }
        queue.sync { teardownLocked() }
        throw BLEError.writeFailed
    }

    func info() -> String {
        var lines = ["Bluetooth device", "  Product:  \(deviceName)", "  Protocol: footswitch (Bluetooth)"]
        if case .key(let combo)? = readStoredConfig() {
            lines.append("  Emits:    \(KeyComboFormatter.display(combo))")
        } else {
            lines.append("  Could not read configuration")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: GATT plumbing

    /// Connects + discovers service/chars + subscribes notify, once. Blocks until
    /// ready or throws. On any failure it tears down the central/connection so the
    /// next call starts from a clean slate.
    private func ensureReady() throws {
        dispatchPrecondition(condition: .notOnQueue(queue))
        if queue.sync(execute: { writeChar != nil && notifyChar != nil }) { return }
        // Reset shared state on `queue` so it's ordered against the delegate callbacks,
        // then kick off central creation (which itself delivers callbacks on `queue`).
        queue.sync {
            setupError = nil
            readySemaphore = DispatchSemaphore(value: 0)
            central = CBCentralManager(delegate: self, queue: queue)   // triggers state update
        }
        if readySemaphore.wait(timeout: .now() + timeout) == .timedOut {
            queue.sync { teardownLocked() }
            throw BLEError.timedOut
        }
        if let e = (queue.sync { setupError }) {
            queue.sync { teardownLocked() }
            throw e
        }
        guard (queue.sync { writeChar != nil && notifyChar != nil }) else {
            queue.sync { teardownLocked() }
            throw BLEError.discoverFailed
        }
    }

    private func writeValue(_ bytes: [UInt8]) throws {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let (p, ch): (CBPeripheral, CBCharacteristic) = try queue.sync {
            guard let p = peripheral, let ch = writeChar else { throw BLEError.writeFailed }
            writeSemaphore = DispatchSemaphore(value: 0)
            return (p, ch)
        }
        p.writeValue(Data(bytes), for: ch, type: .withResponse)
        // Wait for the .withResponse ack (didWriteValueFor) so the header is fully
        // acked before the next write — real ordering, not a guessed delay.
        if writeSemaphore.wait(timeout: .now() + timeout) == .timedOut { throw BLEError.timedOut }
    }

    private func queryReadBack() throws -> FootswitchProgram.StoredConfig? {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let (p, ch): (CBPeripheral, CBCharacteristic) = try queue.sync {
            guard let p = peripheral, let ch = writeChar else { throw BLEError.writeFailed }
            notifySemaphore = DispatchSemaphore(value: 0)
            lastNotification = nil
            return (p, ch)
        }
        p.writeValue(Data(BLEProgramPayload.query(pedalIndex: pedalIndex)), for: ch, type: .withResponse)
        if notifySemaphore.wait(timeout: .now() + timeout) == .timedOut { throw BLEError.timedOut }
        guard let value = (queue.sync { lastNotification }) else { return nil }
        return BLEProgramPayload.parseNotification(value)
    }

    /// Cancels any live connection and drops the central + cached characteristics.
    /// Must run on `queue` (call via `queue.sync`); all teardown state writes happen
    /// there so they're ordered against delegate callbacks.
    private func teardownLocked() {
        if let c = central, let p = peripheral {
            c.cancelPeripheralConnection(p)
        }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        central = nil
    }
}

extension BLEPedalProgrammer: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else {
            setupError = BLEError.poweredOff; readySemaphore.signal(); return
        }
        let connected = c.retrieveConnectedPeripherals(withServices: [hidServiceUUID])
        guard let p = connected.first(where: { ($0.name ?? "").lowercased().contains("fs17") })
                ?? connected.first else {
            setupError = BLEError.notFound; readySemaphore.signal(); return
        }
        peripheral = p
        p.delegate = self
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        setupError = error ?? BLEError.notFound; readySemaphore.signal()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == serviceUUID }) else {
            setupError = BLEError.discoverFailed; readySemaphore.signal(); return
        }
        p.discoverCharacteristics([writeUUID, notifyUUID], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == writeUUID { writeChar = ch }
            if ch.uuid == notifyUUID { notifyChar = ch; p.setNotifyValue(true, for: ch) }
        }
        // Ready once both are found and notifications are (being) enabled.
        if writeChar != nil, notifyChar != nil { readySemaphore.signal() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == notifyUUID, let d = ch.value else { return }
        lastNotification = [UInt8](d)
        notifySemaphore.signal()
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        // Only writeChar is written with response, so signal unconditionally to release
        // the writeValue() wait. (error is surfaced via the read-back mismatch path.)
        writeSemaphore.signal()
    }
}
