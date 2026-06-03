# FS17Pro Bluetooth Foot Switch Support — Design

Date: 2026-06-02
Status: Approved (pending written-spec review)

## Goal

Add full support for the PCsensor **FS17Pro** wireless foot switch:

1. **Recognize** it as a known device in both its connection modes.
2. **Program** it over USB to emit the app's trigger key, using the protocol the
   app already implements for the existing PCsensor pedals.
3. **Document** the setup so a user can take an FS17Pro from out-of-the-box to
   working with the app.

This removes the README's current "does not support bluetooth pedals" limitation.

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
device, two connection modes:

| Mode          | VID:PID         | Enumerates as                         | Programmable here? |
|---------------|-----------------|---------------------------------------|--------------------|
| **USB wired** | `0x3553:0xC100` | PCsensor "FS17Pro", multi-interface   | **Yes**            |
| **Bluetooth** | `0x245A:0x8276` | HID keyboard "FS17Pro" (BLE)          | No (no config endpoint) |

- **Default emit:** a bare key with no modifiers (observed `b` = HID usage `0x05`
  over BLE; `a` = `0x04` over USB after reprogramming). Verified genuine ASCII
  (keyCode 11, `U+0062`) — not a homoglyph.
- **USB is programmable with the existing protocol.** A read-only probe using the
  app's own `readStoredConfig` logic against `0x3553:0xC100` returned
  `04 01 00 04 …` — i.e. type=`1` (key), modifiers=`0`, usage=`0x04` ("A") — which
  `FootswitchProgram.parseKeyResponse` decodes correctly. The config endpoint is
  interface 0 (`PrimaryUsagePage`=1, `PrimaryUsage`=0), 8-byte reports.
- **Trigger key = F16.** PCsensor's "ElfKey" config app rejects F13/F14/F15 (PC
  legacy: PrintScreen/ScrollLock/Pause), but accepts **F16**. F16 is in the app's
  `Keymap` (`0x6A`) and `HIDUsage` table (`0x6b`), has no physical key on Mac
  keyboards, and no terminal escape — same desirable properties F13 has today.

## Chosen approach

**Treat the FS17Pro as one device with two table entries, reuse the existing
`.footswitch` programming path for the USB identity, and add a lightweight
`.bluetooth` family for the BLE identity so the UI is honest about where it can be
programmed.**

### 1. Device table — `Sources/FootswitchCore/FootswitchDevice.swift`

Add a `.bluetooth` case to `Program` and two table entries:

```swift
public enum Program: String, Sendable {
    case footswitch, scythe, scythe2, footswitch1p, bluetooth
}
...
// USB wired mode: programmable via the existing .footswitch protocol.
SupportedDevice(vendorID: 0x3553, productID: 0xc100, program: .footswitch, name: "PCsensor FS17Pro"),
// Bluetooth-LE mode: recognized for status display; configured over USB.
SupportedDevice(vendorID: 0x245A, productID: 0x8276, program: .bluetooth,  name: "PCsensor FS17Pro"),
```

Rationale for two entries rather than one: the IDs genuinely differ per mode, and
the existing match is a flat VID/PID lookup. Two entries keep that model intact and
let each mode carry the right `Program` family. The shared `name` ("PCsensor
FS17Pro") means the UI reads identically regardless of how it's currently
connected.

### 2. Detection prefers a programmable match — `FootswitchHIDController`

`detect()` currently returns `matches().first` (arbitrary; `Set` order is
undefined). With multiple devices attached — e.g. a USB PCsensor pedal *and* the
BLE FS17Pro — this can show the wrong device or pair a "FS17Pro detected" label
with a Program button that acts on a different pedal.

Change `detect()` (and the status logic) to **prefer a `.footswitch`-family match**
(programmable, has a readable config) over a `.bluetooth`-only match, falling back
to any match. This:
- shows the programmable device when one is present (correct target for the
  Program button),
- still reports the FS17Pro as detected when it's the only thing connected over
  BLE,
- gracefully covers the user's separate USB pedal coexisting with the BLE FS17Pro.

This is a deliberate, minimal improvement to existing multi-device behavior that
the FS17Pro work exposes — not a general multi-pedal feature.

### 3. Settings UI — `SettingsView.refreshDeviceStatus`

Behavior by what's connected:

- **A `.footswitch` device present** (existing pedals, or FS17Pro over USB):
  unchanged — "✓ detected", run `verifyConfiguration`, show **Program** button on
  mismatch.
- **Only a `.bluetooth` device present** (FS17Pro over BLE): show the existing
  "✓ {name} detected" line (**reusing `device.detected` — no new localized
  string**), and **hide the config row + Program button** (you program it over
  USB). Concretely, `refreshDeviceStatus` checks `detected.device.program ==
  .bluetooth` and hides the config row the same way the `.noDevice` branch already
  does — before calling `verifyConfiguration`, which is only meaningful for
  `.footswitch` devices. (`Verification` gains no new case.)

No new user-facing strings ⇒ no 30-locale translation pass required.

### 4. `deviceInfo()` — `FootswitchHIDController`

Already prints USB identity + recognized model + "Protocol: {family}". For a
`.bluetooth` device, print identity and `Protocol: bluetooth`, and **skip the config
read** (no endpoint) — show a short "Configured over USB" note instead of "Could
not read configuration", so the info sheet isn't misleading over BLE.

### 5. Programming writes the configured trigger key

The existing **Program** button writes `KeyCombo(modifiers: [], key:
config.triggerKey)` to pedal 1. For the FS17Pro this is unchanged code: in USB
mode it's a `.footswitch` device, so `program()` works as-is. Implementation will
**verify the write path end-to-end with F16** (reads are proven; a real write is
not yet tested on this PID). The app does not change the global `triggerKey`
default (`F13`); FS17Pro users set `"triggerKey": "F16"` themselves (documented).

### 6. Documentation

- `docs/supported-devices.md`: add both FS17Pro rows; note the USB-vs-BLE identity
  split and that programming happens in USB mode.
- `README.md`: remove the "does not currently support bluetooth pedals" sentence;
  add a short **FS17Pro setup** section: switch to USB (blue LED) → open Settings →
  set `triggerKey` to `F16` → click **Program** (or use ElfKey to set F16) →
  switch back to Bluetooth for daily use.

## Rejected alternatives

- **Recognize-only (ElfKey + F16 docs), no app programming.** Simpler, but ignores
  the proven capability — the app already speaks the protocol the USB FS17Pro
  uses. Worse UX than every other supported pedal.
- **Make the trigger key "B" and listen for that.** Avoids programming entirely but
  swallows *all* `b` keypresses globally — unusable if you ever type. Rejected.
- **One table entry / collapse the two identities.** The per-mode VID:PID genuinely
  differ; the flat matcher would need special-casing. Two entries are simpler and
  truthful.
- **A new BLE-specific status string.** Would force a 30-locale translation pass.
  Reusing `device.detected` conveys the same thing with zero new strings.

## Components & data flow

```
USB mode:   FS17Pro(0x3553:0xC100) ──IOKit HID──▶ FootswitchHIDController
              .footswitch family ──▶ verifyConfiguration / program (existing path)
              Settings: detected ✓, verify, [Program] writes triggerKey (F16)

BLE mode:   FS17Pro(0x245A:0x8276) ──IOKit HID──▶ FootswitchHIDController
              .bluetooth family ──▶ detected ✓, no Program button
            Pressing pedal ──macOS key event(F16)──▶ PedalListener tap
              keyCode == triggerKey(F16) ──▶ debounce ──▶ resolve action ──▶ dispatch
              (listener unchanged; hardware-agnostic)
```

## Testing

- **Unit (FootswitchCore):**
  - `SupportedDevices.match(0x3553,0xC100)` → `.footswitch`, name "PCsensor FS17Pro".
  - `SupportedDevices.match(0x245A,0x8276)` → `.bluetooth`, name "PCsensor FS17Pro".
  - `FootswitchProgram.keyReports(pedalIndex:0, combo: F16)` produces the expected
    header/data bytes (usage `0x6b`).
  - `parseKeyResponse([0x04,0x01,0x00,0x6b,…])` → `.key(F16)` (round-trip).
- **Manual / on-device (implementation verification):**
  - USB mode: Settings shows "✓ PCsensor FS17Pro", **Program** sets the trigger
    key, read-back verifies. **Test multiple distinct values** — e.g. program F17,
    read back F17; then program F16, read back F16. The device ships from this
    user already set to F16 (via ElfKey), so a single F16 write-then-read could
    pass without the app's write actually taking effect; changing the value at
    least twice proves the write path mutates the device. End on **F16** (the
    documented default).
  - BLE mode: Settings shows "✓ PCsensor FS17Pro", **no** Program button, info
    sheet shows "Configured over USB" (no false "unreadable").
  - With `triggerKey=F16` and the pedal programmed to F16, pressing it over
    Bluetooth fires the resolved action and types nothing.
- **Verification gates (per CLAUDE.md):** `swift build`, `swift test`, lint clean
  before commit. No new localized strings ⇒ no locale parity work.

## Out of scope (separate spec)

- Independent multi-pedal actions (different pedals → different actions): a
  multi-trigger-key / per-pedal-action rework of `Config` + `PedalListener`.
- 2.4G dongle mode (the FS17Pro's third mode). Not investigated; the dongle
  presents as yet another HID keyboard and would be additive later if wanted.
