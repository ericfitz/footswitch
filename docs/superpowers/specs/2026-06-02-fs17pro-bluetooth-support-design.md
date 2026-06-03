# FS17Pro Bluetooth Foot Switch Support — Design

Date: 2026-06-02
Status: Revised — dual-transport programming (USB + BLE); pending written-spec review

## Goal

Add full support for the PCsensor **FS17Pro** wireless foot switch:

1. **Recognize** it as a known device in both its connection modes (USB and BLE).
2. **Program** it to emit the app's trigger key **over whichever transport it is
   currently connected on** — USB (existing HID protocol) *or* Bluetooth LE (newly
   reverse-engineered GATT protocol). Both reuse the same `FootswitchProgram` report
   bytes.
3. **Document** the setup so a user can take an FS17Pro from out-of-the-box to
   working with the app, wired or wireless.

This removes the README's current "does not support bluetooth pedals" limitation.

The BLE programming protocol was reverse-engineered from an ElfKey-over-BLE capture;
full details are in the companion notes
`docs/superpowers/specs/2026-06-02-fs17pro-ble-programming-protocol.md`.

This spec covers the FS17Pro device only. A *separate* spec will cover
"independent multi-pedal actions" (different pedals → different actions), which is
a general architectural change to the config/listener model and is out of scope
here.

## Context

- SwiftPM macOS menu-bar app, Swift 6, AppKit. `LSUIElement` (no Dock icon).
- The press-handling path is **trigger-key based, not device-based**:
  `PedalListener` installs a `CGEventTap`, catches whatever `config.triggerKey`
  resolves to via `Keymap`, debounces, swallows it, and fires the resolved action.
  It does not know or care which hardware produced the key.
- Device **detection and programming** live in
  `Sources/Footswitch/FootswitchHIDController.swift`, which enumerates IOKit HID
  devices (`IOHIDManagerCopyDevices`, no transport filter — so it sees USB *and*
  Bluetooth-LE HID devices) and matches them against the table in
  `Sources/FootswitchCore/FootswitchDevice.swift` (`SupportedDevices.all`).
- Only the `.footswitch` `Program` family is programmable today. The protocol:
  8-byte output reports with report ID `0x01`; config read-back via a query report
  `[0x01,0x82,0x08,pedal,…]` answered on an interrupt-IN report.
  See `FootswitchProgram` in `FootswitchDevice.swift`.
- The Settings device section (`SettingsView.refreshDeviceStatus`) shows a
  detected/verified/mismatch/unreadable status and a **Program** button gated on
  the `.footswitch` family.
- 30 locales exist under `Sources/Footswitch/Resources/Localizations/`. Any new
  user-facing string must be added to all 30 (project verification gate).

## Investigation findings (on-device, 2026-06-02)

The FS17Pro presents **two distinct USB/Bluetooth identities** — one logical
device, two connection modes — and is **programmable over both**:

| Mode          | VID:PID         | Enumerates as                         | Programmable? | How |
|---------------|-----------------|---------------------------------------|---------------|-----|
| **USB wired** | `0x3553:0xC100` | PCsensor "FS17Pro", multi-interface   | **Yes**       | IOKit HID output reports (existing path) |
| **Bluetooth** | `0x245A:0x8276` | HID keyboard "FS17Pro" (BLE)          | **Yes**       | CoreBluetooth GATT writes (new path) |

- **Default emit:** a bare key with no modifiers (observed `b` = HID usage `0x05`
  over BLE; `a` = `0x04` over USB after reprogramming). Verified genuine ASCII
  (keyCode 11, `U+0062`) — not a homoglyph.
- **USB is programmable with the existing protocol.** A read-only probe using the
  app's own `readStoredConfig` logic against `0x3553:0xC100` returned
  `04 01 00 04 …` — type=`1` (key), modifiers=`0`, usage=`0x04` ("A") — which
  `FootswitchProgram.parseKeyResponse` decodes correctly. Config endpoint is
  interface 0 (`PrimaryUsagePage`=1, `PrimaryUsage`=0), 8-byte reports.
- **BLE is programmable with the *same report sequence over GATT*.** An ElfKey-over-
  BLE capture showed the identical `FootswitchProgram` header/data/query reports
  written (with a `0x01` report-ID byte prepended, data-report type byte `0x81`) to
  **service `FFF0`, characteristic `FFF2`** (write), with the read-back arriving as
  a **notification on characteristic `FFF1`**. See the companion protocol notes.
- **Trigger key = F16.** PCsensor's "ElfKey" config app rejects F13/F14/F15 (PC
  legacy: PrintScreen/ScrollLock/Pause), but accepts **F16**. F16 is in the app's
  `Keymap` (`0x6A`) and `HIDUsage` table (`0x6b`), has no physical key on Mac
  keyboards, and no terminal escape — same desirable properties F13 has today.

## Chosen approach

**Recognize the FS17Pro under both identities, and make "program the pedal" a
transport-abstracted operation backed by the shared `FootswitchProgram` report
bytes — dispatched to a USB-HID writer or a CoreBluetooth-GATT writer depending on
how the device is currently connected.** The pure report-building logic
(`FootswitchProgram`, `HIDUsage`, `DeviceModifier`) is unchanged and stays in
`FootswitchCore`; only the transport layer is new.

### 1. Device table — `Sources/FootswitchCore/FootswitchDevice.swift`

Add a `.footswitchBLE` case to `Program` and two table entries. Both FS17Pro
identities are programmable; the family distinguishes *how*:

```swift
public enum Program: String, Sendable {
    case footswitch, scythe, scythe2, footswitch1p, footswitchBLE
}
...
// USB wired mode: programmable via IOKit HID output reports.
SupportedDevice(vendorID: 0x3553, productID: 0xc100, program: .footswitch,    name: "PCsensor FS17Pro"),
// Bluetooth-LE mode: programmable via CoreBluetooth GATT (service FFF0).
SupportedDevice(vendorID: 0x245A, productID: 0x8276, program: .footswitchBLE, name: "PCsensor FS17Pro"),
```

Two entries (not one): the per-mode VID:PID genuinely differ and the matcher is a
flat VID/PID lookup. The shared `name` means the UI reads identically regardless of
how it's connected. (`.footswitchBLE` over `.bluetooth` as the case name signals
"the footswitch protocol, BLE transport" — both families program; they differ only
in transport.)

### 2. A programming-transport abstraction

Introduce a small protocol so the Settings flow doesn't branch on transport:

```swift
protocol PedalProgrammer {
    func readStoredConfig() throws -> FootswitchProgram.StoredConfig
    func program(combo: KeyCombo) throws
}
```

- **`USBPedalProgrammer`** — the existing `FootswitchHIDController` logic
  (`IOHIDDeviceSetReport` writes, interrupt-IN read-back), refactored to conform.
  No behavioral change for existing pedals.
- **`BLEPedalProgrammer`** — new, CoreBluetooth. Resolves the FS17Pro via
  `retrieveConnectedPeripherals(withServices:[1812])` (it's bonded as a HID
  keyboard and does **not** advertise connectably — confirmed), discovers service
  `FFF0` → write char `FFF2` + notify char `FFF1`, `setNotifyValue(true)` on
  `FFF1`, then writes `[0x01] + header`, `[0x01] + data`, `[0x01] + query` (bytes
  from `FootswitchProgram`, data-report type byte `0x81`) to `FFF2`, and parses the
  `FFF1` notification (strip leading `0x01`) via `parseKeyResponse`. GATT discovery
  + write + notify is inherently **async**; the programmer exposes a sync-looking
  call that drives a short run-loop wait with a timeout (mirroring how the USB
  read-back already spins the run loop), so the Settings call site stays simple.

`FootswitchHIDController.detect()` selects which programmer applies based on the
matched `Program` family.

### 3. Detection prefers a USB-programmable match — `FootswitchHIDController`

`detect()` currently returns `matches().first` (arbitrary; `Set` order is
undefined). With multiple devices attached — e.g. a USB PCsensor pedal *and* the
BLE FS17Pro — this can show the wrong device or mismatch the Program button target.

Order detection: **prefer a `.footswitch` (USB) match, then `.footswitchBLE`, then
any other match.** USB is preferred when both transports of the *same* FS17Pro are
somehow present (e.g. wired while still BLE-connected), since the USB read-back is
synchronous and proven. The BLE programmer is used when the device is only present
over Bluetooth. This also gracefully covers the user's separate USB pedal coexisting
with the BLE FS17Pro. (Deliberate, minimal multi-device handling — not the general
multi-pedal feature, which is a separate spec.)

### 4. Settings UI — `SettingsView.refreshDeviceStatus`

Both FS17Pro identities are programmable, so the existing detected → verify →
**Program** flow applies to **both** — no transport-specific UI branch:

- **Any programmable device present** (existing pedals, FS17Pro over USB, *or*
  FS17Pro over BLE): "✓ {name} detected", run `verifyConfiguration` through the
  selected `PedalProgrammer`, show the **Program** button on mismatch. The Program
  button writes `config.triggerKey` via whichever transport applies.
- BLE `verifyConfiguration`/`program` go through `BLEPedalProgrammer`; because GATT
  is async, the status row may briefly show a "checking…" state before resolving —
  acceptable, and no new *persistent* string is required if we reuse the existing
  detected/verified/mismatch strings.

Aim to add **no new localized strings** (reuse `device.detected`,
`device.config.*`). If a transient "checking over Bluetooth…" string proves
necessary, it is the *only* candidate addition and would require the 30-locale pass
— to be decided during implementation, preferring reuse.

### 5. `deviceInfo()` — `FootswitchHIDController`

Print USB identity + recognized model + "Protocol: {family}", and the read-back
key for **both** families (USB via HID read, BLE via the GATT notify read). For
`.footswitchBLE`, label the transport (e.g. "Protocol: footswitch (Bluetooth)") so
the info sheet is accurate about how it's connected.

### 6. Programming writes the configured trigger key — verification

The **Program** button writes `KeyCombo(modifiers: [], key: config.triggerKey)`.
Implementation will verify **both** transports end-to-end by programming **multiple
distinct values** and reading each back (the device ships already set to F16, so a
single F16 write-then-read could pass without the write taking effect):

- **USB:** program F17 → read back F17; program F16 → read back F16.
- **BLE:** same two-value check over GATT.

End on **F16** (documented default). The app does not change the global
`triggerKey` default (`F13`); FS17Pro users set `"triggerKey": "F16"`.

### 7. Permissions / entitlements

CoreBluetooth requires a usage description and (sandboxed) the Bluetooth
entitlement. Add `NSBluetoothAlwaysUsageDescription` to
`Sources/Footswitch/Resources/Info.plist` and, if needed for the build's sandbox
posture, the `com.apple.security.device.bluetooth` entitlement to
`Footswitch.entitlements`. First BLE program attempt triggers a one-time macOS
Bluetooth permission prompt (like the existing Accessibility grant). The menu-bar
listener path is unaffected — it never touches CoreBluetooth.

### 8. Documentation

- `docs/supported-devices.md`: add both FS17Pro rows; note the USB/BLE identity
  split and that the app programs over **either** transport.
- `README.md`: remove the "does not currently support bluetooth pedals" sentence;
  add an **FS17Pro setup** section: pair over Bluetooth (or connect USB) → open
  Settings → set `triggerKey` to `F16` → click **Program** → use wirelessly. Note
  that F13 is unavailable via ElfKey but the app can program F16 over either
  transport.

## Rejected alternatives

- **Recognize-only (ElfKey + docs), no app programming.** Ignores the proven
  capability — the app already speaks the protocol over both transports. Worse UX
  than every other supported pedal.
- **USB-programming only; BLE recognize-only.** Was the prior plan, before the BLE
  capture proved GATT programming is the same report sequence. Rejected: it would
  force users to find a data USB cable to set F16 when the pedal is already
  wirelessly connected and programmable as-is.
- **Make the trigger key "B" and listen for that.** Avoids programming entirely but
  swallows *all* `b` keypresses globally — unusable if you ever type. Rejected.
- **One table entry / collapse the two identities.** The per-mode VID:PID genuinely
  differ; the flat matcher would need special-casing. Two entries are simpler and
  truthful.
- **Branch the Settings flow on transport instead of a `PedalProgrammer`
  abstraction.** Scatters USB-vs-BLE conditionals through the UI. The protocol
  abstraction keeps the call site transport-agnostic and the report-builder shared.

## Components & data flow

```
PROGRAMMING (Settings → Program button), transport chosen by matched family:

  USB:  FS17Pro(0x3553:0xC100) ─IOKit HID─▶ USBPedalProgrammer
          IOHIDDeviceSetReport(header/data/query) ─▶ interrupt-IN read-back
  BLE:  FS17Pro(0x245A:0x8276) ─CoreBluetooth─▶ BLEPedalProgrammer
          GATT write FFF2: [0x01]+header/data/query ─▶ notify FFF1 read-back
          (retrieveConnectedPeripherals[1812] → discover FFF0 → setNotify FFF1)

  both drive the SAME FootswitchProgram bytes; read-back → parseKeyResponse.

RUNTIME (press handling) — unchanged, hardware-agnostic:

  Press ─macOS key event(F16)─▶ PedalListener tap
    keyCode == triggerKey(F16) ─▶ debounce ─▶ resolve action ─▶ dispatch
```

## Testing

- **Unit (FootswitchCore):**
  - `SupportedDevices.match(0x3553,0xC100)` → `.footswitch`, name "PCsensor FS17Pro".
  - `SupportedDevices.match(0x245A,0x8276)` → `.footswitchBLE`, name "PCsensor FS17Pro".
  - `FootswitchProgram.keyReports(pedalIndex:…, combo: F16)` produces the expected
    header/data bytes (usage `0x6b`).
  - `parseKeyResponse([0x04,0x01,0x00,0x6b,…])` → `.key(F16)` and
    `parseKeyResponse([0x08,0x81,0x00,0x6b,…])` (BLE-shape, type `0x81`) → `.key(F16)`
    (round-trip both report shapes).
  - A BLE-payload builder helper (`[0x01] + report`) round-trips against the
    captured frames (`010181080200000000`, `010881006b00000000`,
    `010182080200000000`).
- **Manual / on-device (implementation verification) — both transports:**
  - **USB:** Settings shows "✓ PCsensor FS17Pro"; **Program** sets the trigger key;
    read-back verifies. **Test multiple distinct values** — program F17, read back
    F17; then F16, read back F16. (Device ships set to F16, so a single F16
    write-read could pass without the write taking effect; two values prove the
    write mutates the device.) End on **F16**.
  - **BLE:** same two-value write/read-back check via CoreBluetooth (first run
    triggers the Bluetooth permission prompt). End on **F16**.
  - With `triggerKey=F16` and the pedal set to F16, pressing it over Bluetooth
    fires the resolved action and types nothing.
- **Verification gates (per CLAUDE.md):** `swift build`, `swift test`, lint clean
  before commit. Prefer reusing existing localized strings; only a transient
  "checking over Bluetooth…" string (if unavoidable) triggers the 30-locale pass.

## Out of scope (separate spec)

- Independent multi-pedal actions (different pedals → different actions): a
  multi-trigger-key / per-pedal-action rework of `Config` + `PedalListener`.
- 2.4G dongle mode (the FS17Pro's third mode). Not investigated; the dongle
  presents as yet another HID keyboard and would be additive later if wanted.
- The 128-bit vendor service (`…1912`) / `…2B12` characteristic — an alternate
  config/OTA path seen in GATT discovery but unused by the captured exchange. The
  `FFF0`/`FFF2`/`FFF1` path is the implementation target.
