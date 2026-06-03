# FS17Pro Bluetooth Foot Switch Support — Design

Date: 2026-06-03
Status: Reviewed (autonomous)

> **Supersedes** the two 2026-06-02 documents:
> `docs/superpowers/specs/2026-06-02-fs17pro-bluetooth-support-design.md` and
> `docs/superpowers/specs/2026-06-02-fs17pro-ble-programming-protocol.md`.
> This is the single, self-contained design of record. The raw BLE
> reverse-engineering dump is **not** reproduced here; the protocol notes doc is
> retained for raw frame detail and is referenced where its findings drive a
> decision.

## Goal

Add support for Bluetooth foot switches in general, and the PCsensor **FS17Pro**
specifically (GitHub issue #1). Concretely:

1. **Recognize** the FS17Pro in both of its connection modes — USB-wired and
   Bluetooth LE.
2. **Program** it to emit the app's trigger key over whichever transport it is
   currently connected on: USB (existing IOKit HID path) or Bluetooth LE (new
   CoreBluetooth GATT path). Both reuse the same `FootswitchProgram` report bytes.
3. **Generalize** the listen / program / identify model behind a small transport
   abstraction so HID (USB) and BLE pedals share one call site, leaving room for
   future BLE pedals without re-plumbing the UI.
4. **Document** taking an FS17Pro from out-of-the-box to working, wired or
   wireless, and drop the README's "does not currently support bluetooth pedals"
   limitation.

The runtime press path is explicitly unchanged (see Context); this work is about
**detection and programming**, not about how a press is handled.

## Context (real codebase facts)

- SwiftPM macOS menu-bar app, Swift 6, AppKit + a little SwiftUI, `LSUIElement`
  (no Dock icon). Two targets: `FootswitchCore` (platform-agnostic models/logic,
  unit-tested via `swift test`) and `Footswitch` (AppKit/IO: menu bar, settings,
  HID, event posting). The `.app` is hand-assembled by `scripts/package-app.sh`;
  `.lproj`, `Info.plist`, and `AppIcon.icns` are copied in directly and
  **excluded** from SwiftPM resource processing (see `Package.swift`).

- **The press path is trigger-key based, not device-based.**
  `Sources/Footswitch/PedalListener.swift` installs a `CGEventTap`, matches the
  keycode resolved from `config.triggerKey` via `Keymap`, debounces, swallows it,
  and fires the resolved action. It never inspects which hardware produced the
  key. So once a pedal is programmed to emit the trigger key, BLE vs USB is
  invisible to runtime — no listener change is needed, and none is proposed.

- **Detection and programming live in
  `Sources/Footswitch/FootswitchHIDController.swift`** as an `enum` with `static`
  methods (no instances today): `detect()`, `detectName()`, `verifyConfiguration(expected:)`,
  `deviceInfo()`, and `program(combo:)`. It enumerates IOKit HID devices via
  `IOHIDManagerCopyDevices` with **no transport filter** — so it already sees both
  USB and Bluetooth-LE HID interfaces — and matches them against
  `SupportedDevices.all` in `Sources/FootswitchCore/FootswitchDevice.swift` by
  VID/PID. `detect()` returns `matches().first`, where `matches()` walks an
  unordered `Set<IOHIDDevice>` (order is undefined).

- **Only the `.footswitch` `Program` family is programmable today.** Protocol:
  8-byte output reports with report ID `0x01` (`FootswitchProgram.start`,
  `keyReports`, `queryReport`); the config read-back is **not** retrievable via a
  synchronous `IOHIDDeviceGetReport` — it arrives on an interrupt-IN report, so
  `readStoredConfig` registers an input-report callback and spins the run loop
  ~500 ms (`CFRunLoopRunInMode`) to catch the reply, then decodes via
  `FootswitchProgram.parseKeyResponse`. `program(combo:)` writes start → header →
  data with `usleep` settles, then confirms by read-back across each candidate
  interface.

- The pure, platform-agnostic report logic — `FootswitchProgram`, `HIDUsage`,
  `DeviceModifier`, `SupportedDevices` — is all in `FootswitchCore` and unit-tested
  (`Tests/FootswitchCoreTests/FootswitchDeviceTests.swift`).

- **Settings UI** (`Sources/Footswitch/SettingsView.swift`): `refreshDeviceStatus()`
  calls `FootswitchHIDController.detect()` then `verifyConfiguration(expected:)`,
  rendering one of `verified` / `mismatch` / `unreadable` / `noDevice` with a
  colored status glyph, and shows the **Program** button on `mismatch`.
  `programPedal()` calls `program(combo:)` synchronously and re-refreshes;
  `showDeviceInfo()` shows `deviceInfo()`. All strings go through
  `Sources/Footswitch/L10n.swift` (e.g. `L10n.deviceDetected(name:)`,
  `L10n.deviceConfigMismatch`).

- **Localization**: **30** `*.lproj` folders under
  `Sources/Footswitch/Resources/Localizations/`. `LocalizationParityTests`
  discovers locales from disk and asserts every locale's key set and positional
  placeholder arity match `en`. Any new user-facing key must be added to **all 30**
  locales or the parity test fails.

- **Entitlements**: `Footswitch.entitlements` is an intentionally empty `<dict/>`.
  The app is **not** sandboxed under the hardened runtime; the comment notes
  CGEvent tap / synthesis are gated by the Accessibility TCC permission at runtime,
  not by an entitlement.

- **FS17Pro on-device findings (2026-06-02 investigation; carried forward):**

  | Mode      | VID:PID         | Enumerates as                       | Programmable | How |
  |-----------|-----------------|-------------------------------------|--------------|-----|
  | USB wired | `0x3553:0xC100` | PCsensor "FS17Pro", multi-interface | Yes          | IOKit HID output reports (existing path) |
  | Bluetooth | `0x245A:0x8276` | HID keyboard "FS17Pro" (BLE)        | Yes          | CoreBluetooth GATT writes (new path) |

  - Default emit is a bare key, no modifiers (`b` over BLE, observed). The pedal
    ships configured, so the **first** value written must differ from the existing
    one to prove a write actually mutated the device.
  - USB read-only probe with the app's own `readStoredConfig` returned
    `04 01 00 04 …` → `parseKeyResponse` decodes type=1, mods=0, usage=`0x04` ("A").
    Config endpoint is interface 0, 8-byte reports — i.e. the existing path works
    verbatim once the table recognizes `0x3553:0xC100`.
  - BLE programming uses the **same `FootswitchProgram` report sequence over GATT**:
    each 8-byte report is prefixed with a `0x01` report-ID byte and written to
    **service `FFF0`, characteristic `FFF2`** (write); the read-back arrives as a
    **notification on `FFF1`**. The data-report "key" type byte observed over BLE is
    `0x81` (our `keyReports` emits `0x01`; `parseKeyResponse` already accepts both).
    The captured exchange programmed pedal index 2 (`pedalIndex+1 = 0x02`). Raw
    frames are in the retained protocol notes doc.
  - **Trigger key = F16.** PCsensor's "ElfKey" config app rejects F13/F14/F15 but
    accepts F16. F16 is already in `Keymap` (`0x6A`) and `HIDUsage` (`0x6b`), has no
    physical Mac key and no terminal escape — the same desirable properties F13 has
    today.

## Chosen approach

Three candidate shapes were weighed:

**A. Transport-abstracted programmer behind a protocol (recommended).**
Introduce a `PedalProgramming` protocol in `FootswitchCore` with two
implementations in the app target: `USBPedalProgrammer` (refactor of today's
`FootswitchHIDController` IOKit logic) and `BLEPedalProgrammer` (new
CoreBluetooth). A `PedalProgrammerFactory` picks the implementation from the
matched `SupportedDevice.Program` family. `SettingsView` calls the protocol, not a
transport. The pure report builder (`FootswitchProgram`/`HIDUsage`/`DeviceModifier`)
is untouched.
*Trade-offs:* one new protocol + one new file (BLE) + a modest refactor of the
existing controller; in exchange the UI never branches on transport, and future
BLE pedals are additive. Matches the FootswitchCore/Footswitch split (protocol +
pure logic in Core, IO in app).

**B. Branch on transport inside `FootswitchHIDController`.** Keep the static
`enum`; add `if family == .footswitchBLE { …CoreBluetooth… }` arms to
`verifyConfiguration`, `deviceInfo`, `program`.
*Trade-offs:* fewer files, but scatters USB-vs-BLE conditionals across four methods
and grows a file that is named for one transport (`HID`) into a two-transport
grab-bag. Harder to test and to extend.

**C. Recognize-only; program BLE with PCsensor's ElfKey + docs.** Add the table
entries, tell users to set F16 with the vendor app.
*Trade-offs:* least code, but strictly worse UX than every other supported pedal,
which the app programs itself — and the on-device work already proved the app can
program over both transports. Throws away a known capability.

**Recommendation: A.** It is the smallest change that keeps the call site
transport-agnostic, preserves the Core/IO split, leaves the proven report builder
shared and untouched, and is the only option that cleanly generalizes "Bluetooth
devices in general" (issue ask #1) rather than hard-coding one BLE pedal. The
extra surface over B is one protocol and a factory — justified by removing
transport branches from the UI and by isolating the async CoreBluetooth machinery
in one file behind a synchronous-looking call.

### Rejected alternatives

- **B (branch inside the static controller)** — scatters transport conditionals;
  rejected for maintainability and testability.
- **C (recognize-only)** — abandons proven programming capability; worst UX.
- **Make the trigger key literally "B" and listen for it** — avoids programming
  entirely but globally swallows every `b` keypress; unusable.
- **Collapse the two FS17Pro identities into one table entry** — the per-mode
  VID:PID genuinely differ and the matcher is a flat VID/PID lookup; special-casing
  it is more code than two honest rows.
- **`scanForPeripherals` to find the BLE pedal** — it is bonded as a HID keyboard
  and does not advertise connectably (confirmed); a scan times out. Use
  `retrieveConnectedPeripherals` instead.

## Section 1 — Device table (`FootswitchCore/FootswitchDevice.swift`)

Add one `Program` case and two table entries. Both FS17Pro identities are
programmable; the family records **how**.

```swift
public enum Program: String, Sendable {
    case footswitch, scythe, scythe2, footswitch1p, footswitchBLE
}
...
// FS17Pro, USB-wired: programmable via IOKit HID output reports (existing path).
SupportedDevice(vendorID: 0x3553, productID: 0xc100, program: .footswitch,    name: "PCsensor FS17Pro"),
// FS17Pro, Bluetooth LE: programmable via CoreBluetooth GATT (service FFF0).
SupportedDevice(vendorID: 0x245a, productID: 0x8276, program: .footswitchBLE, name: "PCsensor FS17Pro"),
```

Rationale for the case name `footswitchBLE` (rather than a generic `.bluetooth`):
it is *the footswitch report protocol carried over the BLE transport* — same
report bytes, different wire. The shared `name "PCsensor FS17Pro"` makes the UI
read identically regardless of how the pedal is connected. Two rows, not one,
because the flat matcher genuinely sees two VID/PIDs.

The pure report builder needs **no change**: `parseKeyResponse` already accepts the
BLE `0x81` key-type byte (`case 1, 0x81`), and `keyReports`/`queryReport` already
produce the 8 bytes the BLE writer wraps. The only protocol-doc nuance — BLE
prepends a `0x01` report-ID byte and uses type `0x81` — is handled in the BLE
writer (Section 3), not in the shared builder.

## Section 2 — Transport abstraction (`PedalProgramming`)

A small protocol expresses the two operations the Settings flow needs. It lives in
`FootswitchCore` (it is pure interface; no AppKit/IOKit/CoreBluetooth in the
signatures), so it is reachable from both targets and unit-testable with a fake.

```swift
// FootswitchCore/PedalProgramming.swift
public protocol PedalProgramming {
    /// The device this programmer drives (already matched).
    var device: SupportedDevice { get }
    /// Reads pedal-1 stored config and compares to `expected`.
    func verifyConfiguration(expected: KeyCombo) -> ConfigVerification
    /// Reads the raw stored config for the info sheet, or nil if unreadable.
    func readStoredConfig() -> FootswitchProgram.StoredConfig?
    /// Programs the pedal to emit `combo`; throws on failure.
    func program(combo: KeyCombo) throws
}

/// Moved out of FootswitchHIDController so it is transport-neutral.
public enum ConfigVerification: Equatable, Sendable {
    case verified      // stored key matches expected
    case mismatch      // read OK but different / non-key
    case unreadable    // present but config read failed
}
```

Notes on the migration:

- `FootswitchHIDController.Verification` had a `noDevice` case used only because
  detection and verification were entangled in one static call. In the new model,
  **detection is separate** (Section 4 returns an optional programmer); a `nil`
  programmer *is* "no device", so `ConfigVerification` drops `noDevice`. The
  Settings code branches on the optional first (as it already does with
  `detect()`), then on `verified/mismatch/unreadable`.
- The two concrete programmers live in the **app** target (they touch IOKit /
  CoreBluetooth):

  - **`USBPedalProgrammer`** (`Sources/Footswitch/USBPedalProgrammer.swift`):
    the existing `FootswitchHIDController` IOKit logic, lifted to an instance that
    holds the matched `IOHIDDevice` handles. `IOHIDDeviceSetReport` writes,
    interrupt-IN run-loop read-back — **no behavioral change** for existing pedals.
    Applies to the `.footswitch` (and remains the only programmable USB) family.
  - **`BLEPedalProgrammer`** (`Sources/Footswitch/BLEPedalProgrammer.swift`):
    new, CoreBluetooth. Applies to `.footswitchBLE`. Detailed in Section 3.

## Section 3 — BLE transport (`BLEPedalProgrammer`)

A focused CoreBluetooth client that turns the async GATT exchange into the same
synchronous-looking call the USB path already exposes (the USB read-back already
spins the run loop, so a bounded run-loop wait is an established pattern here).

**GATT recipe (from the protocol notes, treated as settled):**

1. Resolve the peripheral via
   `centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1812")])`
   (HID service) - the pedal is bonded and does not advertise connectably, so a
   scan is not used. (Implementation note: confirm on-device that this returns the
   bonded pedal; if the array is empty, surface `BLEProgramError.notConnected`.)
2. **Call `central.connect(peripheral, options: nil)` explicitly and await
   `centralManager(_:didConnect:)` before any discovery** - even a peripheral
   returned by `retrieveConnectedPeripherals` is reported with
   `state == .connected` at the *system* level but must still be connected by *this*
   central before its services are usable; skipping this step is an easy and common
   omission. Then discover service `FFF0`; discover its characteristics - `FFF2`
   (`[write, writeWithoutResponse]`, the **config write** char) and `FFF1`
   (`[notify]`, the **read-back / status notify** char).
3. `peripheral.setNotifyValue(true, for: FFF1)` (CoreBluetooth writes the CCCD).
4. Write to `FFF2` (Write **With Response**, matching the captured `Write Request`):
   `[0x01] + header`, then `[0x01] + data`, then `[0x01] + query`, where the 8-byte
   payloads come from `FootswitchProgram` (data-report type byte normalized to
   `0x81` for BLE — see below).
5. On the `FFF1` notification, strip the leading `0x01` byte and decode the
   remaining bytes with `FootswitchProgram.parseKeyResponse` to confirm. An interim
   3-byte status notification (`01 81 55`) may arrive first and is ignored (it is
   not a parseable key response).

**Report shaping.** `BLEPedalProgrammer` does not duplicate report logic. It calls
`FootswitchProgram.keyReports`/`queryReport`, prepends the `0x01` report-ID byte,
and sets the data-report type byte to `0x81`. To keep this honest and shared rather
than hand-mangled in the app target, `FootswitchProgram` gains one **pure** helper
(unit-testable in Core):

```swift
// In FootswitchProgram (FootswitchCore):
/// Wraps an 8-byte report as a BLE ATT value: prepend the 0x01 report-ID byte.
public static func bleValue(_ report: [UInt8]) -> [UInt8] { [0x01] + report }

/// Key reports with the BLE-canonical key-type byte (0x81 instead of 0x01).
public static func keyReportsBLE(pedalIndex: Int, combo: KeyCombo)
    -> (header: [UInt8], data: [UInt8])?  // data[1] == 0x81
```

(`keyReportsBLE` is a thin variant of `keyReports` differing only in the type byte;
implementation may share a private builder. This keeps the one-byte BLE/USB
difference in pure, tested Core code rather than in IO code.)

**Pedal index.** The capture programmed index 2 (`pedalIndex+1 = 0x02`,
i.e. `pedalIndex = 1`); the captured *query* frame also used `pedalIndex 1`
(`0x02`). USB uses `pedalIndex: 0`. The FS17Pro is single-pedal in our usage.
**Decision:** the BLE programmer uses `pedalIndex: 1` on **every** BLE GATT
operation - `program`, `verifyConfiguration`, and `readStoredConfig` alike - to
match the observed working exchange. The same cheap **1-then-0 fallback** applies
to all three: if a read-back / query at index 1 yields no parseable response, retry
once at index 0 before giving up. This matters for the refresh-time verify path:
`refreshDeviceStatus()` calls `verifyConfiguration` (and `readStoredConfig` for the
info sheet) **without** a preceding `program`, so the verify/read path must itself
query index 1 - defaulting to USB's index 0 would return `.unreadable`/`.mismatch`
on a correctly-programmed BLE pedal. (USB is unaffected and keeps `pedalIndex: 0`
on all paths.) This is recorded under Assumptions.

**Synchronization & lifetime (single coherent threading model).**
`BLEPedalProgrammer` owns a `CBCentralManager` **created with its own dedicated
serial dispatch queue** (`CBCentralManager(delegate:queue:)` with a private
`DispatchQueue(label: "footswitch.ble")`), and acts as the central's and the
peripheral's delegate. Because the manager is given an explicit queue, **all
CoreBluetooth delegate callbacks are serviced on that private queue - not on the
main run loop** - so the programmer does **not** depend on the main run loop
spinning to make progress. `verifyConfiguration` / `program` / `readStoredConfig`
are **synchronous, blocking** calls: they kick off the
power-on → retrieve → connect → discover → notify → write → await-notification
sequence on the private queue and block the *calling* thread on a bounded wait
(a `DispatchSemaphore` signaled from the delegate queue) with an overall budget
~3 s (CoreBluetooth needs time to power on the central and connect). The delegate
queue signals the semaphore on completion or timeout.

Because the wait blocks on a semaphore (not a spun `CFRunLoop`) and the callbacks
run on the private queue, this blocking call is **safe to invoke off the main
actor** - which is exactly how Section 5 dispatches the BLE verify/program. It must
**not** be called synchronously on the main thread for a BLE pedal: blocking the
main thread ~3 s would hang the UI, and (unlike the run-loop-spinning USB path)
spinning is not what drives BLE progress here. The USB path is unchanged: it keeps
its existing `CFRunLoopRunInMode` read-back and is effectively synchronous
(<=500 ms), so it may run on the main thread as today.

The instance is short-lived: created per Settings operation by the factory, torn
down (cancel connection, release central) when the call returns.

## Section 4 — Detection & factory (`FootswitchHIDController` + `PedalProgrammerFactory`)

`FootswitchHIDController` remains the **HID enumerator** (it is the only thing that
can see VID/PIDs via IOKit — including the BLE pedal's HID interface, which IOKit
also enumerates). Its `matches()`/`Detected` stay. Three changes:

1. **Deterministic detection order.** `detect()` today returns `matches().first`
   over an unordered set. Replace with a stable priority so a mixed setup (a USB
   PCsensor pedal *and* the BLE FS17Pro, or the FS17Pro wired *while* still
   BLE-bonded) resolves predictably:
   **prefer a programmable USB `.footswitch` match, then `.footswitchBLE`, then any
   other match.** USB wins ties because its read-back is synchronous and proven; BLE
   is used when the device is present only over Bluetooth. This is deliberate,
   minimal multi-device disambiguation — **not** the general multi-pedal feature
   (out of scope).

2. **A factory maps the matched family to a programmer:**

   ```swift
   // Sources/Footswitch/PedalProgrammerFactory.swift
   enum PedalProgrammerFactory {
       /// The highest-priority connected programmable pedal, or nil.
       static func current() -> PedalProgramming? {
           // uses FootswitchHIDController.matches() ordered as above
           // .footswitch / .footswitch1p / scythe* (programmable subset) -> USBPedalProgrammer
           // .footswitchBLE                                               -> BLEPedalProgrammer
       }
   }
   ```

   (Today only `.footswitch` is actually programmable on USB; `scythe*`/`footswitch1p`
   keep their current "detected but not programmable" behavior, surfaced as a thrown
   `unsupportedProgram` from `USBPedalProgrammer`, unchanged.)

3. **`deviceInfo()`** stays in `FootswitchHIDController` (it is the only thing that
   can read the IOKit HID-interface identity properties), but it must become
   **transport-aware**, because detection priority (item 1) now lets a
   Bluetooth-connected FS17Pro reach it. Today (`FootswitchHIDController.swift`
   lines 81-92) it emits a hard-coded `"USB device"` header followed by USB-only
   IOKit identity lines (`kIOHIDManufacturerKey`, `kIOHIDLocationIDKey`,
   `kIOHIDVersionNumberKey`). For a BLE HID interface those values are typically
   absent/empty, and the `"USB device"` header is simply wrong. Changes:

   - **Header by transport.** Branch on the matched family: print `"USB device"`
     for the USB families and `"Bluetooth device"` for `.footswitchBLE`.
   - **Guard the USB-only identity lines.** `Location ID` and `Version` are emitted
     **only** for the USB families and suppressed for `.footswitchBLE` (a BLE HID
     interface carries no USB Location ID / bcdDevice; they are already
     presence-guarded, so for BLE they are simply absent - this makes that
     intentional rather than incidental). The `Vendor` line currently always prints
     a `-` fallback for an empty manufacturer string; change it to print the
     manufacturer fragment only when that string is non-empty, so a BLE interface
     with no manufacturer reads `Vendor: (0x245A)` rather than `Vendor: - (0x245A)`.
     `Vendor`/`Product` (VID/PID) and `Serial` stay for both transports - IOKit
     enumerates the BLE HID interface with its own VID/PID (`0x245A:0x8276`), which
     is real, useful identity.
   - **Protocol line.** For `.footswitchBLE` the `"  Protocol:"` line reads
     `footswitch (Bluetooth)`; USB families keep `program.rawValue` unchanged.
   - **Programmed-configuration line** now reads through
     `PedalProgrammerFactory.current()?.readStoredConfig()` (replacing the inline
     `.footswitch`-only `matches().filter...` read) so it works for the BLE family
     too. This routes the BLE read-back through `BLEPedalProgrammer`, which queries
     the BLE pedal index (Section 3), not the USB `pedalIndex: 0`.

   These header/label strings (`"USB device"`, `"Bluetooth device"`,
   `"Recognized model"`, `"Protocol:"`) live in the info sheet's preformatted,
   monospaced body and are **not** routed through `L10n`/`.lproj` - they are
   unlocalized today and stay unlocalized, so the new `"Bluetooth device"` header
   introduces **no** new localized key and **no** 30-locale pass.

`detect()` keeps its signature for the existing `deviceInfo()`/Settings call sites;
the new factory is what Settings uses to obtain a programmer. (`detectName()` -
`FootswitchHIDController.swift` line 41 - has no remaining call sites in the tree;
the refactor may keep or drop it, and the spec no longer relies on it.)

## Section 5 — Settings UI (`SettingsView.swift`)

Both FS17Pro identities are programmable, so the existing
detected → verify → **Program** flow applies to both with **no transport-specific
UI branch**. `refreshDeviceStatus()` changes from calling the static controller to:

```swift
guard let programmer = PedalProgrammerFactory.current() else { /* ⊘ deviceNone, hide rows */ }
deviceStatusLabel = statusLine("✓", L10n.deviceDetected(name: programmer.device.name), .systemGreen)
let expected = KeyCombo(modifiers: [], key: baseConfig.triggerKey)
switch programmer.verifyConfiguration(expected: expected) {
case .verified:   // ✓ green,  Program hidden
case .mismatch:   // ⚠ yellow, Program shown
case .unreadable: // ✗ red,    Program hidden
}
```

`programPedal()` calls `programmer.program(combo:)` (the programmer is re-fetched at
click time) and re-refreshes. `showDeviceInfo()` is unchanged at the call site.

**Async caveat (consistent with the Section 3 threading model).** USB
`verifyConfiguration` is effectively synchronous (run-loop spin <=500 ms) and may
run inline on the main actor as today. BLE adds a connect/discover round-trip
(~1-3 s) and its programmer blocks the *calling* thread on a semaphore signaled
from its own private CoreBluetooth queue (Section 3) - it does **not** rely on the
main run loop, so it is safe (and required) to call it **off** the main actor. To
avoid a visible main-thread hang when a BLE pedal is present, `refreshDeviceStatus()`
shows the green "detected" line immediately on the main actor, then runs the BLE
`verifyConfiguration` in a detached `Task` (off the main actor); when it returns,
the result is applied back to the `configStatusLabel`/`programButton` on the
`@MainActor` `SettingsViewController`. Because the programmer's delegate callbacks
are serviced on its private queue (not the main run loop), dispatching the blocking
call off-main does **not** starve CoreBluetooth - resolving the contradiction
between an off-main dispatch and a main-run-loop-pinned manager. The config row
shows the existing `deviceConfigUnreadable` styling only if verification genuinely
fails (including read-back timeout). **No new persistent string is introduced**
(issue scope keeps the 30-locale gate closed): the design reuses `device.detected`,
`device.config.verified/mismatch/unreadable`. If a transient "checking..."
affordance proves necessary in implementation, it would be the single candidate
string and would trigger the full 30-locale pass - the design's intent is to avoid
it.

## Section 6 — Programming semantics & the F16 default

- The **Program** button writes `KeyCombo(modifiers: [], key: baseConfig.triggerKey)`
  — unchanged behavior.
- The app's global default `triggerKey` stays **`F13`** (`Config.swift`). FS17Pro
  users set `"triggerKey": "F16"` (documented), because ElfKey/PCsensor firmware
  rejects F13 but accepts F16, and F16 is already in `Keymap`/`HIDUsage`.
- Because the FS17Pro ships pre-configured, end-to-end verification must program
  **two distinct values** and read each back (a single F16 write-then-read could
  pass without the write taking effect). See Testing.

## Section 7 — Permissions / entitlements

- CoreBluetooth requires a usage-description string. Add
  `NSBluetoothAlwaysUsageDescription` to `Sources/Footswitch/Resources/Info.plist`
  (English value, e.g. "Footswitch uses Bluetooth to program your wireless foot
  switch."). The first BLE program/verify attempt triggers a one-time macOS
  Bluetooth permission prompt, analogous to the existing Accessibility grant.
  - **Localization:** this single English value is shown in the macOS permission
    prompt for **all 30 locales**. Per-locale `InfoPlist.strings` is **out of
    scope** for this change (it is an OS-prompt string, not a `LocalizationParityTests`-
    governed `.lproj` key, so it does not affect the parity gate). Accepted trade-off:
    the Bluetooth prompt appears in English regardless of system language; localizing
    it is deferred to the broader i18n pass.
- The app is **not sandboxed** (empty `Footswitch.entitlements`, hardened-runtime
  comment). `com.apple.security.device.bluetooth` is a **sandbox** entitlement and
  is therefore **not required** here. **Decision:** leave `Footswitch.entitlements`
  empty; do not add a sandbox Bluetooth entitlement, matching the current posture.
  (If the project ever sandboxes, that entitlement gets added then — noted, not done
  now.)
- The runtime listener path never touches CoreBluetooth; only Settings
  programming/verification does.

## Section 8 — Documentation

- `docs/supported-devices.md`: add both FS17Pro rows (`3553:c100 footswitch`,
  `245a:8276 footswitchBLE`); note the USB/BLE identity split and that the app
  programs over either transport.
- `README.md`: remove "does not currently support bluetooth pedals" from the
  Limitations section (line ~20) and add a short **FS17Pro setup** subsection:
  connect over USB or pair over Bluetooth → open Settings → set `triggerKey` to
  `F16` → click **Program** → use wirelessly. Note that F13 is unavailable via the
  vendor app but the Footswitch app programs F16 over either transport.

## Section 9 — Error handling

- **USB** (`USBPedalProgrammer`): preserves the existing `ProgramError` cases
  (`noDevice`, `unsupportedKey`, `openFailed`, `writeFailed`, `unsupportedProgram`)
  and their `CustomStringConvertible` text, surfaced unchanged via
  `L10n.alertProgramFailed(error:)`.
- **BLE** (`BLEPedalProgrammer`): a parallel error type, e.g.
  `BLEProgramError { .bluetoothUnavailable(CBManagerState), .notConnected,
  .serviceNotFound, .characteristicNotFound, .writeFailed(Error), .readbackTimeout,
  .unsupportedKey }`, each `CustomStringConvertible` with a plain-English sentence.
  These flow through the *same* `L10n.alertProgramFailed(error:)` path (it
  interpolates `"\(error)"`), so **no new localized string** is needed for failure
  display — only the (non-localized, English) error descriptions differ.
- **Permission denied / Bluetooth off**: `bluetoothUnavailable(.poweredOff/.unauthorized)`
  produces a clear message ("Turn on Bluetooth…" / "Allow Bluetooth access in System
  Settings…"). The factory still reports the device as *detected* (IOKit sees the HID
  interface); only verify/program degrade to `unreadable` / a failure alert.
- **Read-back timeout**: if no parseable `FFF1` notification arrives within the
  budget, `program` treats a clean write as success (mirroring the USB path's
  "writes posted but unconfirmed → success if the post was clean" behavior) and
  `verifyConfiguration` returns `.unreadable`.

## Section 10 — Testing

**Unit (FootswitchCore, `swift test` — no `.app`, no hardware, no CoreBluetooth):**

- `SupportedDevices.match(0x3553, 0xc100)` → `.footswitch`, name "PCsensor FS17Pro".
- `SupportedDevices.match(0x245a, 0x8276)` → `.footswitchBLE`, name "PCsensor FS17Pro".
- `FootswitchProgram.keyReports(pedalIndex: 1, combo: F16)` →
  header `[0x01,0x81,0x08,0x02,0,0,0,0]`, data `[0x08,0x01,0x00,0x6b,0,0,0,0]`.
- `FootswitchProgram.keyReportsBLE(pedalIndex: 1, combo: F16)` → data byte[1] == `0x81`.
- `FootswitchProgram.bleValue(header)` == `[0x01] + header`; round-trips against the
  captured frames in the protocol notes (`010181080200000000`,
  `010881006b00000000`, `010182080200000000`).
- `parseKeyResponse([0x04,0x01,0x00,0x6b,…])` → `.key(F16)` and
  `parseKeyResponse([0x08,0x81,0x00,0x6b,…])` (BLE shape, type `0x81`) → `.key(F16)`
  (round-trip both report shapes). (`testParseKeyResponseWithType0x81` already covers
  the `0x81` path generally; add the F16-usage case.)
- A `PedalProgramming` **fake** verifies the Settings decision logic
  (verified/mismatch/unreadable) without hardware - i.e. the verify->render mapping
  is testable in Core via the protocol.
- `FootswitchProgram.queryReport(pedalIndex: 1)` -> `[0x01,0x82,0x08,0x02,0,0,0,0]`
  (the index-1 query frame the BLE verify/read path uses; matches the captured
  `010182080200000000` query).

**Localization parity:** unchanged — the design adds **no new localized keys**, so
`LocalizationParityTests` stays green across all 30 locales with no edits. (If a
transient "checking…" string is added in implementation, all 30 locales must be
updated in the same change.)

**Manual / on-device (implementation verification) — both transports:**

- **USB** (`0x3553:0xC100`): Settings shows "✓ PCsensor FS17Pro"; program **F17**,
  read back F17; then program **F16**, read back F16. End on F16. (Two distinct
  values prove the write mutates the device, since it ships pre-set.)
- **BLE** (`0x245A:0x8276`): same two-value write/read-back over CoreBluetooth; first
  run triggers the one-time Bluetooth permission prompt. End on F16.
- With `triggerKey = F16` and the pedal set to F16, pressing it over Bluetooth fires
  the resolved action and types nothing (confirms the unchanged listener path).
- Mixed-device sanity: with a USB PCsensor pedal and the BLE FS17Pro both present,
  `detect()`/factory deterministically resolve to the USB pedal (priority order).

**Verification gates (per CLAUDE.md):** `swift build`, `swift test`, and lint clean
before commit.

## Out of scope (YAGNI)

- **Independent multi-pedal actions** (different pedals → different actions): a
  multi-trigger-key / per-pedal-action rework of `Config` + `PedalListener`.
  Separate spec. The detection-priority change here is *disambiguation only*, not
  multi-pedal support.
- **2.4 GHz dongle mode** (the FS17Pro's third mode): not investigated; presents as
  yet another HID keyboard and would be additive later.
- **The 128-bit vendor service** (`…1912` / char `…2B12`, "qiekgnayqiekgnay"): an
  alternate/OTA config path seen in GATT discovery but unused by the captured
  exchange. The `FFF0`/`FFF2`/`FFF1` path is the implementation target.
- **BLE scanning / pairing UI**: the pedal is bonded as a HID keyboard by macOS;
  the app retrieves it via `retrieveConnectedPeripherals` and does not pair it.
- **Sandboxing the app / adding sandbox entitlements**: the app is not sandboxed;
  no entitlement change is made.
- **Changing the global default `triggerKey`**: stays `F13`; FS17Pro users opt into
  F16 via config.

## Affected / new files

- Edit `Sources/FootswitchCore/FootswitchDevice.swift` — add `Program.footswitchBLE`,
  two FS17Pro table rows, and `keyReportsBLE`/`bleValue` pure helpers.
- New `Sources/FootswitchCore/PedalProgramming.swift` — `PedalProgramming` protocol
  and `ConfigVerification` enum (transport-neutral).
- New `Sources/Footswitch/USBPedalProgrammer.swift` — `PedalProgramming` over IOKit;
  the existing `FootswitchHIDController` programming/read-back logic as an instance.
- New `Sources/Footswitch/BLEPedalProgrammer.swift` — `PedalProgramming` over
  CoreBluetooth (service `FFF0`, write `FFF2`, notify `FFF1`).
- New `Sources/Footswitch/PedalProgrammerFactory.swift` — maps the highest-priority
  matched device to a `PedalProgramming` instance.
- Edit `Sources/Footswitch/FootswitchHIDController.swift` — deterministic detection
  order; `deviceInfo()` reads config via the factory; programming/verify logic moves
  into `USBPedalProgrammer`.
- Edit `Sources/Footswitch/SettingsView.swift` — use `PedalProgrammerFactory`; render
  via `ConfigVerification`; off-main-actor BLE verify with main-actor apply.
- Edit `Sources/Footswitch/Resources/Info.plist` — add `NSBluetoothAlwaysUsageDescription`.
- Edit `docs/supported-devices.md` — add the two FS17Pro rows + identity-split note.
- Edit `README.md` — drop the Bluetooth limitation; add FS17Pro setup section.
- Edit `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift` — FS17Pro match,
  F16 reports, BLE report/value helpers, BLE-shape parse cases, `PedalProgramming` fake.

## Assumptions

- **BLE pedal index = 1** (`pedalIndex+1 = 0x02`) on **all** BLE GATT operations
  (`program`, `verifyConfiguration`, `readStoredConfig`), matching the observed
  working ElfKey program *and* query exchanges; with a cheap **1-then-0 fallback**
  on every path if a read-back/query at index 1 yields no parseable response. USB
  keeps `pedalIndex: 0`.
- **BLE data-report key-type byte = `0x81`** (as captured), exposed via
  `keyReportsBLE`; USB keeps `0x01`. Both are accepted by `parseKeyResponse` already.
- **GATT layout is settled** at service `FFF0` / write `FFF2` / notify `FFF1`, per the
  retained protocol notes; the 128-bit vendor service is ignored.
- **An explicit `central.connect(...)` is required** before service discovery even
  for a peripheral returned by `retrieveConnectedPeripherals(withServices:[1812])`;
  confirmed at implementation time on-device. An empty retrieve result surfaces as
  `BLEProgramError.notConnected`.
- **No new localized strings.** Reusing existing `device.*` keys keeps the 30-locale
  parity gate closed; a "checking…" string is deliberately avoided.
- **Entitlements unchanged** (empty dict). The app is not sandboxed, so only the
  `NSBluetoothAlwaysUsageDescription` Info.plist key is required; no
  `com.apple.security.device.bluetooth` entitlement.
- **Global `triggerKey` default stays `F13`.** FS17Pro users set `F16` in config; the
  app programs F16 over either transport.
- **Detection priority** USB-footswitch → BLE-footswitch → other is acceptable
  minimal multi-device disambiguation; full multi-pedal support is a separate spec.
- **`ConfigVerification` drops the `noDevice` case** (the optional programmer from the
  factory now represents "no device"), replacing `FootswitchHIDController.Verification`.
- **BLE threading: dedicated CoreBluetooth queue + off-main blocking call.**
  `BLEPedalProgrammer` gives its `CBCentralManager` a private serial dispatch queue
  (delegate callbacks run there, not on the main run loop) and exposes a synchronous
  blocking call (semaphore-backed). Settings calls it **off** the main actor and
  applies the result back on the `@MainActor` controller. The USB path stays
  main-run-loop-driven and synchronous. This is the single coherent threading model;
  Sections 3 and 5 are written to agree.
- The retained protocol-notes doc and the on-device findings (2026-06-02) are
  accurate and need no re-verification before implementation; implementation-time
  on-device testing per Section 10 is the confirmation step.

## Review & revision notes

Autonomous integration of a reviewer pass (status "Issues Found"; 3 issues, 6
recommendations) against the real codebase
(`FootswitchHIDController.swift`, `FootswitchDevice.swift`, `SettingsView.swift`).

**Issue 1 - `deviceInfo()` mislabels a BLE pedal as "USB device" (Section 4 item
3).** Confirmed against `FootswitchHIDController.swift` lines 81-92: the method
hard-codes a `"USB device"` header and emits USB-only IOKit lines
(`kIOHIDManufacturerKey`, `kIOHIDLocationIDKey`, `kIOHIDVersionNumberKey`), and
detection priority now lets a `.footswitchBLE` device reach it. **Fixed:** Section
4 item 3 now specifies a transport-branched header (`"USB device"` vs
`"Bluetooth device"`), suppression of the USB-only `Location ID`/`Version` lines for
BLE, a presence-guarded `Vendor` manufacturer fragment, retention of VID/PID +
`Serial` (real for the BLE HID interface), the `footswitch (Bluetooth)` protocol
label, and the read-through to `PedalProgrammerFactory.current()?.readStoredConfig()`.
It also records that these are unlocalized info-sheet body strings, so no 30-locale
pass is triggered.

**Issue 2 - BLE verify/read pedal index unspecified (Section 3 / `readStoredConfig`).**
Confirmed: the spec pinned `pedalIndex: 1` only for `program()`, while USB's
`verifyConfiguration`/`readStoredConfig` use `pedalIndex: 0`
(`FootswitchHIDController.swift` lines 60, 103, 220). A refresh-time verify (no
preceding program) would query the wrong index. **Fixed:** the Section 3 "Pedal
index" decision now applies `pedalIndex: 1` with the 1-then-0 fallback to **all
three** BLE operations (program, verify, read), notes the captured query frame also
used index 1, and the Assumptions and Section 10 entries match (added a
`queryReport(pedalIndex: 1)` unit case).

**Issue 3 - contradictory BLE threading model (Section 3 vs Section 5).** Confirmed
the conflict: Section 3 said CB callbacks are serviced on the already-spinning main
run loop and the call blocks on a run-loop wait; Section 5 said the BLE verify is
dispatched off the main actor - which would starve a main-run-loop-pinned manager.
`SettingsViewController` is `@MainActor` (`SettingsView.swift` line 26). **Fixed**
with one coherent model (reviewer recommendation (a)): `BLEPedalProgrammer` gives
its `CBCentralManager` a **private serial dispatch queue**, so delegate callbacks do
not depend on the main run loop; the call is synchronous/semaphore-blocking and is
therefore safe to run **off** the main actor; Settings runs it in a detached `Task`
and applies results back on `@MainActor`. The USB path stays main-run-loop-driven
and synchronous. Sections 3, 5, and Assumptions were rewritten to agree.

**Recommendations:**
- (deviceInfo BLE label) - **applied** (Issue 1).
- (state BLE verify/read index = 1 with fallback) - **applied** (Issue 2).
- (resolve threading in one place via dedicated CB queue) - **applied**, option (a)
  (Issue 3).
- (confirm `retrieveConnectedPeripherals` + explicit `connect()`) - **applied**: the
  GATT recipe now makes the explicit `central.connect(...)`/await-`didConnect` step
  mandatory and calls out confirming the retrieve result on-device; an empty result
  maps to `BLEProgramError.notConnected`.
- (note `NSBluetoothAlwaysUsageDescription` stays English across locales) -
  **applied**: Section 7 now records that the single English value appears in the
  permission prompt for all 30 locales, with per-locale `InfoPlist.strings` explicitly
  out of scope and unrelated to the parity gate.
- (`detectName()` has no call sites; claim is harmless) - **applied as a minor
  correction**: Section 4 no longer asserts `detectName()` is kept "for the existing
  call sites"; it notes the method has no remaining callers and the spec no longer
  relies on it. (Verified: no `detectName` references outside its declaration.)

No reviewer point required a human product decision; all were resolvable against the
codebase and the settled protocol notes. The remaining open items are the same
implementation-time on-device confirmations the spec already carried (pedal-index
fallback actually firing, `retrieveConnectedPeripherals` returning the bonded pedal),
now stated explicitly rather than left implicit.
