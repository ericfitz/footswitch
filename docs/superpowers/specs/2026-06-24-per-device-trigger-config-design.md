# Per-device trigger configuration (full `devices` section)

**Issue:** [#9](https://github.com/ericfitz/footswitch/issues/9) (follow-up to [#4](https://github.com/ericfitz/footswitch/issues/4))
**Status:** Design approved — pending implementation plan
**Date:** 2026-06-24

## Problem

Issue #4 made the device table data-driven (`customDevices`: a VID/PID array merged
with the built-in table at detection time) but deferred **per-device trigger
configuration**. Today all trigger keys live in a single global, transport-keyed
`Config.triggers` (`usb` / `bluetooth` lists). That can't express "this device uses
these keys" — it only distinguishes USB vs Bluetooth globally.

This spec folds trigger configuration into a per-device `devices` section so each
recognized foot switch carries its own keys.

## The architectural constraint (scope-defining)

The runtime path is `keycode → slot → RuleResolver.resolve(bundleID, slot, config)
→ action`. The listener (`PedalListener`, a global `CGEventTap`) only ever sees a
**keycode** — never which physical device or transport produced it. Detection
matches by **VID+PID only**; two same-model pedals are indistinguishable.

Therefore **per-device config governs the static / programming-time layer**
(the device table, what Program / verify / Test write and read, and which keys the
listener watches) — **not runtime action routing**. Runtime dispatch stays
`keycode → slot`. True per-device runtime attribution would require replacing the
global event tap with per-device HID input-report reading — a separate, much larger
rearchitecture that is explicitly **out of scope** here.

## Goals

- A `devices` section where each entry is `{ vendorId, productId, program, name,
  triggers }` and owns its trigger keys.
- `devices` replaces `customDevices`: it serves both roles — device identity (the
  #4 table) and per-device triggers.
- Global `Config.triggers` is removed; all trigger config lives on device entries,
  with a code-level default for entry-less devices.
- Lossless one-time migration of existing configs.
- Settings' Program / verify / Test operate on the connected device's entry.

## Non-goals

- Per-device runtime action routing (the wall above).
- An in-app device-table editor for adding/removing/renaming devices or editing
  disconnected devices' triggers — that stays hand-editable in `config.json`,
  consistent with how #4 shipped.
- Per-device, per-transport split within one entry: transport is implied by the
  entry's VID/PID + program family, so each transport is its own entry.

## Data model

```swift
/// One recognized foot switch and its trigger keys. Replaces `CustomDevice`:
/// carries device identity (the #4 table role) AND this device's trigger keys.
/// VID/PID are hex strings (e.g. "245A") matching the ioreg/USB convention.
/// `triggers` is a flat list for THIS device; transport is implied by `program`.
public struct Device: Codable, Equatable, Sendable {
    public var vendorId: String
    public var productId: String
    public var program: String
    public var name: String
    public var triggers: [TriggerKey]
}
```

```swift
public struct Config {
    // REMOVED: public var triggers: Triggers
    // REMOVED: public var customDevices: [CustomDevice]
    public var devices: [Device]
    public var dictationShortcut: KeyCombo
    public var debounceMs: Int
    public var defaultAction: DefaultAction
    public var rules: [Rule]
}
```

- `Device.resolved() -> SupportedDevice?` keeps `CustomDevice`'s tolerant validation
  (parse hex VID/PID, validate `program` against `SupportedDevice.Program`, require
  non-blank name); malformed entries are skipped at use, never failing config load.
- The `Triggers` type (`usb`/`bluetooth` split) is **retired**. `TriggerKey`
  (`key` + `slot`) is unchanged.

### Transport derivation

Transport is derived, not stored:

```
.footswitch, .scythe, .scythe2, .footswitch1p → .usb
.footswitchBLE                                → .bluetooth
```

Used for programming (USB vs BLE path), config-verify, and BLE power-cycle
messaging.

## Resolution

The trigger keys for a **connected** device (matched by VID/PID):

1. The matching `devices` entry's `triggers`, if non-empty.
2. Else the **code-level default** `[F13/slot1, F14/slot2, F15/slot3]` (the
   historical `Config.default` set).

Always clamped to the detected slot count by the existing `buildListener` logic, so
single-pedal users never have F14/F15 swallowed.

The **listener** watches the **union of every device's trigger keys** (deduped by
keycode, first-writer-wins, as today), clamped to detected slots; an empty union
falls back to the code default. Runtime dispatch (`keycode → slot → RuleResolver`)
is unchanged.

## Migration (lossless, on decode)

`Config`'s decoder branches on the JSON shape:

- **Has `devices`** → decode directly (tolerant: skip malformed entries).
- **Old config** (`triggers` present and/or `customDevices`, no `devices`) → seed
  `devices`:
  - For every built-in `SupportedDevices.all` device, create a `Device` with
    `triggers` = old `triggers.usb` for USB-family programs, old
    `triggers.bluetooth` for `.footswitchBLE`.
  - For each old `customDevices` entry, create the corresponding `Device` with
    `triggers` assigned the same way (by its program family's transport).
  - Old trigger keys are preserved exactly; nothing is lost.
- **Neither** (fresh) → `devices: []` (code default applies).

The encoder always writes `devices` and never `triggers`/`customDevices`, so the
migration is a deterministic one-time rewrite. `Config.default.devices == []`.

Migration tolerances:
- Built-in seeding uses the same key set for every USB-family device (they share the
  historical default unless the user customized `triggers.usb`), so the rewritten
  config is verbose but readable and editable.
- A malformed old `customDevices` entry is dropped on migration (it would have been
  skipped at use anyway).

## Detection & listener wiring

- `SupportedDevices.match(vendorID:productID:custom:)` is updated to take the
  resolved `devices` (still "custom entries first, then built-ins"). The parameter/
  registry rename: `FootswitchHIDController.registeredCustomDevices` →
  `registeredDevices: [Device]`, set by `AppDelegate` on launch/reload from
  `config.devices`.
- `AppDelegate.buildListener` builds the trigger-key union from `config.devices`
  (replacing `config.allTriggerKeys`), clamped to detected slots, with the code
  default fallback.

## UI (connected device only)

`SettingsView`:

- `keyForSlot(_ slot:)` drops its `transport:` parameter and resolves against the
  **connected device's** entry (matched via `FootswitchHIDController.detect()`'s
  VID/PID) → its `triggers` → else the code default.
- Program / verify / per-slot rows operate on that connected device's entry,
  unchanged in behavior other than the resolution source.
- Adding/removing/renaming devices and editing disconnected devices' triggers is
  hand-editable in `config.json`.

## Relationship to #6 (Test button)

The #6 plan (`docs/superpowers/plans/2026-06-24-test-button.md`) adopts a captured
key into the global `triggers.<transport>` via `Triggers.adopting(...)`. Removing
global `triggers` here changes that substrate.

**Resolution:** the Test button's "Use \<key\>" must adopt into the **connected
device entry's `triggers`** instead — a `Device`-level adopt (replace the key for
the slot, append if absent). The reconciliation logic (`TriggerReconciler`,
`CapturedKey`) is unaffected.

**Sequencing recommendation:** implement **#9 before #6**. If #6 lands first, its
adopt path and `keyForSlot` must be retargeted from `Triggers` to `Device` entries
when #9 is implemented. A pointer note will be added to the #6 plan.

## Testing

**Core / IO-free (unit):**
- `Device` codable: tolerant decode (skip malformed VID/PID / unknown program /
  blank name), `resolved()` validation, encode only the new shape.
- **Migration**: old `triggers` (+ `customDevices`) → seeded `devices`; lossless
  (every old key preserved on the right device); byte-stable re-encode; fresh config
  → `devices: []`.
- **Resolution**: connected-device lookup → entry triggers vs code default; clamping
  composes with detection.
- **Listener union builder**: union across devices, dedup, code-default fallback.
- `SupportedDevices.match` against `devices` (override-then-built-in).

**App target:**
- Detection wiring (`registeredDevices`), `keyForSlot` re-resolution; manual
  multi-device verification (USB pedal + FS17Pro USB/BLE).

**Localization:**
- Device editing is config-only → expect **no new user-facing strings**; confirm
  during implementation. `LocalizationParityTests` stays green.

## Related

- #4 — data-driven custom device table (this supersedes its `customDevices` array).
- #6 — Test button (adopt substrate changes; see Relationship to #6).
- #10 — modifier keys in trigger detection (orthogonal; `TriggerKey` unchanged).
