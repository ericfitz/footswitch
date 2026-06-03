# FS17Pro Bluetooth Foot Switch Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize the PCsensor FS17Pro foot switch (USB id `0x3553:0xC100`, BLE id `0x245A:0x8276`) and program it to emit the trigger key over whichever transport it is connected on — USB (existing IOKit HID path) or Bluetooth LE (new CoreBluetooth GATT path).

**Architecture:** Pure report-building stays in `FootswitchCore` (`FootswitchProgram`); a new `PedalProgrammer` protocol abstracts the transport. `USBPedalProgrammer` wraps the existing IOKit logic; `BLEPedalProgrammer` (new) drives the same report bytes over GATT (service `FFF0`, write char `FFF2`, notify char `FFF1`) using a leading `0x01` report-ID byte and data-report type byte `0x81`. The Settings programming flow selects a programmer by the matched device's `Program` family. The runtime key-listening path is unchanged.

**Tech Stack:** Swift 6, SwiftPM, AppKit, IOKit HID, CoreBluetooth, XCTest. macOS 13+. App is NOT sandboxed (empty `Footswitch.entitlements`), so CoreBluetooth needs only `NSBluetoothAlwaysUsageDescription` in `Info.plist` — no entitlement.

**Spec:** `docs/superpowers/specs/2026-06-02-fs17pro-bluetooth-support-design.md`
**Protocol notes:** `docs/superpowers/specs/2026-06-02-fs17pro-ble-programming-protocol.md`

**Conventions for this codebase:**
- Pure, testable logic lives in `FootswitchCore` (no AppKit/IOKit/CoreBluetooth). Transport/UI code lives in the `Footswitch` app target.
- Tests live in `Tests/FootswitchCoreTests/`. Run with `swift test`. Only `FootswitchCore` is unit-tested; the app target's IOKit/CoreBluetooth code is verified manually on-device.
- Run `swift build` and `swift test` before every commit (per CLAUDE.md). Lint: the project has no separate linter configured beyond the compiler; treat a clean `swift build` (no warnings introduced) as the lint gate.
- Commit after each task.

---

## File Structure

**Created:**
- `Sources/FootswitchCore/BLEProgramPayload.swift` — pure builder/parser for the BLE GATT payloads (`[0x01] + report`, type byte `0x81`). Unit-tested against captured frames.
- `Sources/Footswitch/PedalProgrammer.swift` — the `PedalProgrammer` protocol + `StoredConfig`-returning API shared by both transports.
- `Sources/Footswitch/BLEPedalProgrammer.swift` — CoreBluetooth implementation.
- `Tests/FootswitchCoreTests/BLEProgramPayloadTests.swift` — tests for the BLE payload builder/parser.

**Modified:**
- `Sources/FootswitchCore/FootswitchDevice.swift` — add `.footswitchBLE` Program case + two FS17Pro table entries.
- `Sources/Footswitch/FootswitchHIDController.swift` — refactor existing logic behind `USBPedalProgrammer`; make `detect()` prefer USB-programmable matches; route `verifyConfiguration`/`program`/`deviceInfo` through the selected programmer.
- `Sources/Footswitch/Resources/Info.plist` — add `NSBluetoothAlwaysUsageDescription`.
- `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift` — add FS17Pro table-match tests.
- `docs/supported-devices.md` — add FS17Pro rows.
- `README.md` — remove the "no bluetooth pedals" limitation; add FS17Pro setup.

---

## Task 1: Add FS17Pro device-table entries + `.footswitchBLE` family

**Files:**
- Modify: `Sources/FootswitchCore/FootswitchDevice.swift:8` (the `Program` enum) and `:24-33` (the `all` table)
- Test: `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift`

- [ ] **Step 1: Write the failing test**

Add these two tests to `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift` (inside the `final class FootswitchDeviceTests`):

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FootswitchDeviceTests/testMatchesFS17ProBLE`
Expected: FAIL — compile error "type 'SupportedDevice.Program' has no member 'footswitchBLE'" (and the USB test fails: no match → nil).

- [ ] **Step 3: Add the enum case and table entries**

In `Sources/FootswitchCore/FootswitchDevice.swift`, change the `Program` enum (line 8) from:

```swift
    public enum Program: String, Sendable { case footswitch, scythe, scythe2, footswitch1p }
```

to:

```swift
    public enum Program: String, Sendable { case footswitch, scythe, scythe2, footswitch1p, footswitchBLE }
```

Then in the `all` array, immediately after the existing `0x3553, productID: 0xb001` line (line 29), add the two FS17Pro entries:

```swift
        SupportedDevice(vendorID: 0x3553, productID: 0xc100, program: .footswitch,    name: "PCsensor FS17Pro"),
        SupportedDevice(vendorID: 0x245A, productID: 0x8276, program: .footswitchBLE, name: "PCsensor FS17Pro"),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FootswitchDeviceTests`
Expected: PASS (all existing device tests + the two new ones).

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/FootswitchDevice.swift Tests/FootswitchCoreTests/FootswitchDeviceTests.swift
git commit -m "feat(device): recognize FS17Pro (USB 3553:c100, BLE 245a:8276)"
```

---

## Task 2: BLE payload builder/parser in FootswitchCore

The BLE GATT writes are `[0x01] + <8-byte report>`. The captured frames are:
- header: `01 01 81 08 02 00 00 00 00`  (report `[0x01,0x81,0x08,pedal+1,0,0,0,0]`)
- data:   `01 08 81 00 6b 00 00 00 00`  (report `[0x08, 0x81, mods, usage, 0,0,0,0]` — note **type byte `0x81`**, not `0x01` like USB)
- query:  `01 01 82 08 02 00 00 00 00`  (report `[0x01,0x82,0x08,pedal+1,0,0,0,0]`)

The read-back notification value is `01 08 81 00 6b 00 00 00 00`; strip the leading `0x01` and feed `[0x08,0x81,0x00,0x6b,...]` to the existing `FootswitchProgram.parseKeyResponse`.

**Files:**
- Create: `Sources/FootswitchCore/BLEProgramPayload.swift`
- Test: `Tests/FootswitchCoreTests/BLEProgramPayloadTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/FootswitchCoreTests/BLEProgramPayloadTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BLEProgramPayloadTests`
Expected: FAIL — compile error "cannot find 'BLEProgramPayload' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/FootswitchCore/BLEProgramPayload.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BLEProgramPayloadTests`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/BLEProgramPayload.swift Tests/FootswitchCoreTests/BLEProgramPayloadTests.swift
git commit -m "feat(core): add BLE GATT program payload builder/parser"
```

---

## Task 3: Introduce the `PedalProgrammer` protocol + refactor USB path

This extracts the transport-agnostic interface and makes the existing USB code conform, with **no behavior change** for existing pedals. We keep `FootswitchHIDController` as the detection/entry point but move the per-device program/verify into a `USBPedalProgrammer` value.

**Files:**
- Create: `Sources/Footswitch/PedalProgrammer.swift`
- Modify: `Sources/Footswitch/FootswitchHIDController.swift`

- [ ] **Step 1: Create the protocol + result types**

Create `Sources/Footswitch/PedalProgrammer.swift`:

```swift
import Foundation
import FootswitchCore

/// Result of reading and verifying a connected pedal's stored configuration.
/// Mirrors the prior `FootswitchHIDController.Verification` so the Settings UI is
/// unchanged.
enum PedalVerification {
    case noDevice
    case verified      // stored key matches expected
    case mismatch      // read OK but configured differently
    case unreadable    // device present but config read failed
}

/// Transport-agnostic programming interface. A concrete programmer targets a single
/// connected device over one transport (USB HID or BLE GATT) and drives the shared
/// `FootswitchProgram` / `BLEProgramPayload` report bytes.
protocol PedalProgrammer {
    /// Human-readable model name of the device this programmer targets.
    var deviceName: String { get }
    /// Reads pedal 1's stored config; nil if it could not be read.
    func readStoredConfig() -> FootswitchProgram.StoredConfig?
    /// Programs the device to emit `combo` on press. Throws on failure.
    func program(combo: KeyCombo) throws
    /// A human-readable, read-only info report (USB identity / model / stored key).
    func info() -> String
}

extension PedalProgrammer {
    /// Default verification: read the stored config and compare to `expected`.
    func verify(expected: KeyCombo) -> PedalVerification {
        guard let stored = readStoredConfig() else { return .unreadable }
        switch stored {
        case .key(let combo): return combo == expected ? .verified : .mismatch
        case .unconfigured, .other: return .mismatch
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete (the protocol is unused so far — that's fine).

- [ ] **Step 3: Commit the scaffold**

```bash
git add Sources/Footswitch/PedalProgrammer.swift
git commit -m "feat(app): add PedalProgrammer transport abstraction"
```

---

## Task 4: Wrap the existing USB logic in `USBPedalProgrammer`

Refactor `FootswitchHIDController` so its existing IOKit write/read code is reachable through a `USBPedalProgrammer` conforming to `PedalProgrammer`, and route `verifyConfiguration`/`program`/`deviceInfo` through it. Detection now prefers a USB-programmable match.

**Files:**
- Modify: `Sources/Footswitch/FootswitchHIDController.swift`

> Note: This file has no unit tests (it touches IOKit). Verification is `swift build` plus the on-device manual check in Task 8. Make minimal, mechanical changes.
>
> **Do not run `swift build` until Step 5** — Steps 1–4 are interdependent edits to one file and the intermediate states will not compile. Apply all four, then build.

- [ ] **Step 1: Add a `USBPedalProgrammer` type wrapping one matched device**

In `Sources/Footswitch/FootswitchHIDController.swift`, add this struct (e.g. just below the `Detected` struct). It reuses the file's existing private helpers `readStoredConfig(_:pedalIndex:)`, `setReport(_:_:)`, and the `FootswitchProgram` byte builders — keep those functions where they are:

```swift
/// A `PedalProgrammer` bound to one matched USB HID device interface (or set of
/// interfaces for a multi-interface device). Wraps the existing IOKit logic.
struct USBPedalProgrammer: PedalProgrammer {
    let detected: FootswitchHIDController.Detected
    /// All `.footswitch`-family interfaces of the same device (one carries config).
    let interfaces: [IOHIDDevice]

    var deviceName: String { detected.device.name }

    func readStoredConfig() -> FootswitchProgram.StoredConfig? {
        for dev in interfaces {
            if let stored = FootswitchHIDController.readStoredConfig(dev, pedalIndex: 0) {
                return stored
            }
        }
        return nil
    }

    func program(combo: KeyCombo) throws {
        try FootswitchHIDController.programUSB(interfaces: interfaces, combo: combo)
    }

    func info() -> String {
        FootswitchHIDController.usbInfo(detected: detected, interfaces: interfaces)
    }
}
```

- [ ] **Step 2: Expose the existing helpers to the struct**

The struct above references `FootswitchHIDController.readStoredConfig`, `.programUSB`, and `.usbInfo`. Make the existing private read/program logic callable:

1. Change `private static func readStoredConfig(...)` to `static func readStoredConfig(...)` (drop `private`). Keep its body unchanged.
2. Rename the existing `static func program(combo:)` body into `static func programUSB(interfaces: [IOHIDDevice], combo: KeyCombo) throws`. Replace its current `let candidates = matches(); ... programmable` discovery with the passed-in `interfaces` array (the caller supplies them). The write loop body (start/header/data reports, read-back confirm) is otherwise unchanged. Concretely the new signature and head:

```swift
static func programUSB(interfaces: [IOHIDDevice], combo: KeyCombo) throws {
    guard !interfaces.isEmpty else { throw ProgramError.noDevice }
    guard let reports = FootswitchProgram.keyReports(pedalIndex: 0, combo: combo) else {
        throw ProgramError.unsupportedKey
    }
    var lastWrite: IOReturn = kIOReturnSuccess
    for dev in interfaces {
        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
        do {
            try setReport(dev, FootswitchProgram.start)
            usleep(1_000_000)
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
            .compactMap({ readStoredConfig($0, pedalIndex: 0) }).first, stored == combo {
            return
        }
    }
    if lastWrite == kIOReturnSuccess { return }
    throw ProgramError.writeFailed(lastWrite)
}
```

3. Extract the body of the existing `deviceInfo()` (the USB-identity / model / stored-key text builder) into `static func usbInfo(detected: Detected, interfaces: [IOHIDDevice]) -> String`, taking the device + interfaces instead of re-detecting. Keep the exact lines it prints; where it currently filters `matches().filter({ $0.device.program == .footswitch })` to read the stored config, use the passed-in `interfaces`.

- [ ] **Step 3: Add a programmer factory + USB-preferring detection**

Add a helper that returns the right `PedalProgrammer` for what's connected, preferring USB. Add to `FootswitchHIDController`:

```swift
/// All matched interfaces grouped by (vendorID, productID) for a given program family.
private static func interfaces(forProgram program: SupportedDevice.Program) -> [Detected] {
    matches().filter { $0.device.program == program }
}

/// Returns a programmer for the best-matching connected device, or nil if none.
/// Prefers a USB-programmable `.footswitch` device, then BLE `.footswitchBLE`.
static func programmer() -> PedalProgrammer? {
    let all = matches()
    if let usb = all.first(where: { $0.device.program == .footswitch }) {
        let ifaces = all.filter { $0.device.program == .footswitch }.map { $0.hidDevice }
        return USBPedalProgrammer(detected: usb, interfaces: ifaces)
    }
    if let ble = all.first(where: { $0.device.program == .footswitchBLE }) {
        return BLEPedalProgrammer(deviceName: ble.device.name)   // added in Task 6
    }
    return nil
}
```

> The `BLEPedalProgrammer(deviceName:)` reference will not compile until Task 6. To keep this task's build green, temporarily comment out the BLE branch (the two `if let ble …` lines) with a `// TODO(Task 6): BLE programmer` marker, and uncomment it in Task 6 Step 4.

- [ ] **Step 4: Route the public API through the programmer**

Replace the public `detectName()`, `verifyConfiguration(expected:)`, `deviceInfo()`, and `program(combo:)` so they delegate to `programmer()`:

```swift
static func detectName() -> String? { detect()?.device.name }

static func verifyConfiguration(expected: KeyCombo) -> PedalVerification {
    guard let p = programmer() else { return .noDevice }
    return p.verify(expected: expected)
}

static func deviceInfo() -> String? { programmer()?.info() }

static func program(combo: KeyCombo) throws {
    guard let p = programmer() else { throw ProgramError.noDevice }
    try p.program(combo: combo)
}
```

> The Settings UI calls `FootswitchHIDController.verifyConfiguration(expected:)` and switches on its cases. The old `Verification` enum is replaced by `PedalVerification` (same case names: `noDevice/verified/mismatch/unreadable`), so `SettingsView.swift:198-214` continues to compile unchanged. Delete the now-unused `enum Verification` from this file.

- [ ] **Step 5: Build to verify it compiles (BLE branch still commented)**

Run: `swift build`
Expected: Build complete. If `SettingsView.swift` references `FootswitchHIDController.Verification`, update those references to `PedalVerification` (the case names are identical, so the `switch` arms are unchanged).

- [ ] **Step 6: Run the full test suite (no regressions)**

Run: `swift test`
Expected: PASS — all existing tests still pass (core logic untouched).

- [ ] **Step 7: Commit**

```bash
git add Sources/Footswitch/FootswitchHIDController.swift Sources/Footswitch/SettingsView.swift
git commit -m "refactor(app): route USB programming through USBPedalProgrammer"
```

---

## Task 5: Add `NSBluetoothAlwaysUsageDescription` to Info.plist

CoreBluetooth on a non-sandboxed app needs only this usage-description key to show the one-time TCC prompt; no entitlement is required (entitlements file is intentionally empty).

**Files:**
- Modify: `Sources/Footswitch/Resources/Info.plist`

- [ ] **Step 1: Add the key**

In `Sources/Footswitch/Resources/Info.plist`, inside the top-level `<dict>` (e.g. right after the `LSMinimumSystemVersion` line), add:

```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Footswitch uses Bluetooth to program a connected FS17Pro foot switch to emit your chosen trigger key.</string>
```

- [ ] **Step 2: Validate the plist**

Run: `plutil -lint Sources/Footswitch/Resources/Info.plist`
Expected: `Sources/Footswitch/Resources/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add Sources/Footswitch/Resources/Info.plist
git commit -m "build: add NSBluetoothAlwaysUsageDescription for BLE programming"
```

---

## Task 6: Implement `BLEPedalProgrammer` (CoreBluetooth)

A synchronous-facing programmer that drives CoreBluetooth's async GATT flow on a background queue and blocks the caller (with a timeout) using a semaphore — mirroring how the USB read-back spins a run loop. It must NOT be called on the main thread holding the run loop it needs; the Settings call runs it on a background dispatch and marshals UI updates back (Task 7).

**Files:**
- Create: `Sources/Footswitch/BLEPedalProgrammer.swift`
- Modify: `Sources/Footswitch/FootswitchHIDController.swift` (uncomment the BLE branch)

> No unit test (CoreBluetooth needs hardware). Verified by `swift build` + on-device check in Task 8. The pure payload bytes are already tested (Task 2).

- [ ] **Step 1: Write the CoreBluetooth programmer**

Create `Sources/Footswitch/BLEPedalProgrammer.swift`:

```swift
import Foundation
import CoreBluetooth
import FootswitchCore

/// Programs an FS17Pro over Bluetooth LE via GATT. Drives CoreBluetooth's async
/// API on a private queue and exposes a synchronous-looking `program`/`readStoredConfig`
/// that block (with a timeout) on a semaphore. Call OFF the main thread.
///
/// GATT layout (reverse-engineered): vendor service FFF0, write characteristic
/// FFF2, notify characteristic FFF1. Payloads come from `BLEProgramPayload`.
final class BLEPedalProgrammer: NSObject, PedalProgrammer {
    let deviceName: String

    private let hidServiceUUID = CBUUID(string: "1812")
    private let serviceUUID = CBUUID(string: "FFF0")
    private let writeUUID = CBUUID(string: "FFF2")
    private let notifyUUID = CBUUID(string: "FFF1")
    private let pedalIndex = 1   // capture showed pedal 2 (pedal+1 = 2)
    private let timeout: TimeInterval = 8

    private let queue = DispatchQueue(label: "footswitch.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    // Operation state, guarded by `queue`.
    private var readySemaphore = DispatchSemaphore(value: 0)
    private var notifySemaphore = DispatchSemaphore(value: 0)
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
    /// ready or throws.
    private func ensureReady() throws {
        if writeChar != nil, notifyChar != nil { return }
        setupError = nil
        readySemaphore = DispatchSemaphore(value: 0)
        central = CBCentralManager(delegate: self, queue: queue)   // triggers state update
        if readySemaphore.wait(timeout: .now() + timeout) == .timedOut { throw BLEError.timedOut }
        if let e = setupError { throw e }
        guard writeChar != nil, notifyChar != nil else { throw BLEError.discoverFailed }
    }

    private func writeValue(_ bytes: [UInt8]) throws {
        guard let p = peripheral, let ch = writeChar else { throw BLEError.writeFailed }
        p.writeValue(Data(bytes), for: ch, type: .withResponse)
        // .withResponse confirmation arrives via didWriteValueFor; we serialize via a
        // short queue hop. A small sleep keeps ordering simple and matches device pacing.
        usleep(60_000)
    }

    private func queryReadBack() throws -> FootswitchProgram.StoredConfig? {
        guard let p = peripheral, let ch = writeChar else { throw BLEError.writeFailed }
        notifySemaphore = DispatchSemaphore(value: 0)
        lastNotification = nil
        p.writeValue(Data(BLEProgramPayload.query(pedalIndex: pedalIndex)), for: ch, type: .withResponse)
        if notifySemaphore.wait(timeout: .now() + timeout) == .timedOut { throw BLEError.timedOut }
        guard let value = lastNotification else { return nil }
        return BLEProgramPayload.parseNotification(value)
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
        // Ordering handled by the small sleep in writeValue(); nothing required here.
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete. (If `KeyComboFormatter.display` has a different signature, match the call used in the existing `FootswitchHIDController.deviceInfo()` — grep `KeyComboFormatter.display` to confirm.)

- [ ] **Step 3: Verify the formatter call site matches**

Run: `rg -n 'KeyComboFormatter.display' Sources/`
Expected: the same `KeyComboFormatter.display(<KeyCombo>)` form used in both `FootswitchHIDController` and the new file. Fix the new call if the signature differs.

- [ ] **Step 4: Uncomment the BLE branch in `programmer()`**

In `Sources/Footswitch/FootswitchHIDController.swift`, remove the `// TODO(Task 6)` comments and restore the BLE branch added in Task 4 Step 3:

```swift
    if let ble = all.first(where: { $0.device.program == .footswitchBLE }) {
        return BLEPedalProgrammer(deviceName: ble.device.name)
    }
```

- [ ] **Step 5: Build + full test suite**

Run: `swift build && swift test`
Expected: Build complete; all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Footswitch/BLEPedalProgrammer.swift Sources/Footswitch/FootswitchHIDController.swift
git commit -m "feat(app): program FS17Pro over Bluetooth via CoreBluetooth GATT"
```

---

## Task 7: Run BLE programming off the main thread in Settings

`BLEPedalProgrammer` blocks on semaphores, so the Settings "Program"/verify must not call it on the main thread. Wrap the calls in a background dispatch and marshal UI updates back to main. USB stays synchronous on main (unchanged, fast).

**Files:**
- Modify: `Sources/Footswitch/SettingsView.swift` (around `refreshDeviceStatus` at `:184-215`, `programPedal` at `:247-256`, `showDeviceInfo` at `:228-245`)

> No unit test (AppKit UI). Verified by `swift build` + on-device check (Task 8).

- [ ] **Step 1: Make `refreshDeviceStatus` resolve verification off-main for BLE**

The current `refreshDeviceStatus()` (`SettingsView.swift:184`) calls `verifyConfiguration` synchronously. Detection (`detect()`) is fast and stays on main. For the verify step, dispatch to a background queue and update the labels back on main. Replace the body from the `let expected = …` line through the `switch` with:

```swift
        let expected = KeyCombo(modifiers: [], key: baseConfig.triggerKey)
        // Verification may talk to the device (USB read-back, or BLE GATT which
        // blocks) — do it off the main thread, then update the UI on main.
        configStatusLabel.stringValue = ""   // brief blank while checking
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FootswitchHIDController.verifyConfiguration(expected: expected)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .verified:
                    self.configStatusLabel.attributedStringValue =
                        self.statusLine("✓", L10n.deviceConfigVerified, .systemGreen)
                    self.programButton.isHidden = true
                case .mismatch:
                    self.configStatusLabel.attributedStringValue =
                        self.statusLine("⚠", L10n.deviceConfigMismatch, .systemYellow)
                    self.programButton.isHidden = false
                    self.programButton.isEnabled = true
                case .unreadable:
                    self.configStatusLabel.attributedStringValue =
                        self.statusLine("✗", L10n.deviceConfigUnreadable, .systemRed)
                    self.programButton.isHidden = true
                case .noDevice:
                    self.configRow.isHidden = true
                }
            }
        }
```

Keep the early-return `guard let detected = FootswitchHIDController.detect() else { … }` block and the "✓ detected" line above it exactly as they are.

- [ ] **Step 2: Make `programPedal` run off-main**

Replace the body of `@objc private func programPedal()` (`SettingsView.swift:247`) with:

```swift
    @objc private func programPedal() {
        let combo = KeyCombo(modifiers: [], key: baseConfig.triggerKey)
        let key = baseConfig.triggerKey
        programButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var message: String
            do {
                try FootswitchHIDController.program(combo: combo)
                message = L10n.alertProgrammed(key: key)
            } catch {
                message = L10n.alertProgramFailed(error: "\(error)")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.programButton.isEnabled = true
                self.presentInfo(message)
                self.refreshDeviceStatus()
            }
        }
    }
```

- [ ] **Step 3: Make `showDeviceInfo` fetch info off-main**

`deviceInfo()` may now do BLE I/O. Replace the first line of `@objc private func showDeviceInfo()` (`SettingsView.swift:229`, `let info = …`) so the fetch happens in the background and the alert is presented on main:

```swift
    @objc private func showDeviceInfo() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let info = FootswitchHIDController.deviceInfo() ?? L10n.alertDeviceInfoNone
            DispatchQueue.main.async {
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = L10n.alertDeviceInfoTitle
                let field = NSTextField(labelWithString: info)
                field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                field.sizeToFit()
                alert.accessoryView = field
                alert.informativeText = ""
                alert.addButton(withTitle: L10n.alertOK)
                if let window = self.view.window {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }
    }
```

- [ ] **Step 4: Build + full test suite**

Run: `swift build && swift test`
Expected: Build complete; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Footswitch/SettingsView.swift
git commit -m "fix(app): run device verify/program/info off the main thread"
```

---

## Task 8: On-device verification (both transports)

No code changes unless a defect is found. This is the manual gate the spec requires. Build a real `.app` so Accessibility + Bluetooth permissions attach to a stable identity.

**Files:** none (verification only).

- [ ] **Step 1: Build and package the app**

Run:
```bash
swift build
./scripts/package-app.sh
open build/Footswitch.app
```
Expected: app launches to the menu bar (🦶). Grant Accessibility if prompted.

- [ ] **Step 2: USB transport — two-value write/read-back**

1. Connect the FS17Pro in **USB mode** (blue LED).
2. Set `~/.footswitch/config.json` `"triggerKey"` to `"F17"` (or via Settings if exposed), relaunch.
3. Open **Settings…** → device row shows "✓ PCsensor FS17Pro". Click **Program**. Click the **info (ⓘ)** button → confirm "Emits: F17".
4. Change `triggerKey` to `"F16"`, relaunch, **Program** again, info → confirm "Emits: F16".

Expected: the info read-back changes F17 → F16, proving the write mutates the device (not a coincidental match).

- [ ] **Step 3: BLE transport — two-value write/read-back**

1. Switch the FS17Pro to **Bluetooth mode** (red LED); confirm it's connected in System Settings → Bluetooth. Disconnect any USB PCsensor pedal so detection selects the BLE device.
2. With `triggerKey="F17"`: open Settings → "✓ PCsensor FS17Pro" → **Program**. First run triggers the macOS **Bluetooth permission** prompt — allow it. Info (ⓘ) → "Emits: F17 (Bluetooth)".
3. Set `triggerKey="F16"`, relaunch, **Program**, info → "Emits: F16".

Expected: read-back changes F17 → F16 over BLE.

- [ ] **Step 4: Runtime press test**

With `triggerKey="F16"` and the pedal set to F16 over Bluetooth: focus a text field and press the pedal. Expected: the mapped action fires (e.g. dictation toggles) and **no character is typed**.

- [ ] **Step 5: Record results**

If all pass, note it in the commit for Task 9. If any step fails, switch to the systematic-debugging skill before changing code.

---

## Task 9: Documentation

**Files:**
- Modify: `docs/supported-devices.md`
- Modify: `README.md`

- [ ] **Step 1: Update `docs/supported-devices.md`**

Add two rows to the device table (after the `3553 | b001` row):

```
| 3553     | c100      | footswitch    | PCsensor FS17Pro (USB mode)        |
| 245a     | 8276      | footswitchBLE | PCsensor FS17Pro (Bluetooth mode)  |
```

(If the table has no name column, match the existing columns and add a sentence below noting the FS17Pro presents `3553:c100` over USB and `245a:8276` over BLE — the app programs it over either transport.)

- [ ] **Step 2: Update `README.md` — remove the limitation**

In `README.md`, the "Limitations" section currently reads (around the top): "does not currently support bluetooth pedals". Remove the Bluetooth clause so it reads:

```
The app currently does not support multi-pedal devices such as sheet music
page turners.
```

- [ ] **Step 3: Update `README.md` — add FS17Pro setup**

Add a short subsection under "How it works" or "Configuration":

```markdown
### PCsensor FS17Pro (wireless)

The FS17Pro works over Bluetooth or USB. Pair it over Bluetooth (or connect the
USB-C cable), open **Settings…**, set `triggerKey` to `F16`, and click **Program** —
the app writes the key over whichever transport the pedal is connected on. F16 is
recommended because PCsensor's ElfKey app cannot assign F13–F15; the app programs
F16 directly over USB or Bluetooth. After programming over USB you can switch the
pedal to Bluetooth for daily wireless use.
```

- [ ] **Step 4: Verify build/tests still green (docs-only, but run the gate)**

Run: `swift build && swift test`
Expected: Build complete; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/supported-devices.md README.md
git commit -m "docs: document FS17Pro support (USB + Bluetooth, F16)"
```

---

## Final verification

- [ ] **Run the full gate:** `swift build && swift test` → all green.
- [ ] **Confirm no new localized strings** were added (the spec aimed for zero): `git diff main -- Sources/Footswitch/Resources/Localizations/` should be empty. If a transient string was unavoidable, it must be present in all 30 `.lproj/Localizable.strings` files (run `swift test --filter LocalizationParityTests`).
- [ ] **On-device checks (Task 8) all passed**, ending with the pedal set to **F16** over Bluetooth.
