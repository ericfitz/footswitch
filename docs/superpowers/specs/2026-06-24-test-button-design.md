# Test button: detect the key the pedal actually emits, reconcile with config

**Issue:** [#6](https://github.com/ericfitz/footswitch/issues/6)
**Status:** Design approved — pending implementation plan
**Date:** 2026-06-24

## Problem

The app programs a foot switch to emit a chosen key, and the runtime listener
catches that key. But the app has no way to confirm what the pedal *actually*
emits. This matters most for the FS17Pro over Bluetooth: a BLE-programmed key is
written to the device's config slot but the **live keymap only reloads on a
physical power-cycle** (see
`2026-06-03-fs17pro-ble-live-apply-investigation.md` / issue #7). Until then the
pedal keeps emitting the old key while config says otherwise, and the user has no
in-app signal of the drift.

A **Test button** closes this loop: detect the key the pedal really emits, compare
it to config, and let the user reconcile — either by adopting the emitted key into
config (the #7 escape hatch: change config to match the device, no power-cycle) or
by reprogramming the device to the configured key.

## Goals

- Per-slot "Test" action that captures the key a physically-pressed pedal emits.
- Diagnostic confirmation when the emitted key matches config ("is it working?").
- On mismatch, offer two explicit reconciliation paths: **adopt** the emitted key
  into config, or **reprogram** the device to the configured key.
- Work for both USB and Bluetooth, against the currently-connected transport.

## Non-goals

- Modifier/combo trigger detection. Capture deliberately ignores modifier-only and
  combo presses; full combo support is tracked in **issue #10**.
- Attributing a keycode to a specific physical pedal automatically. The runtime
  listener only sees keycodes, never which device/pedal emitted them, so the user
  selects the slot (per-slot Test button) and presses that pedal.
- Any change to the BLE live-apply behavior itself (impossible without a private
  API; see #7). Test is the UX mitigation, not a fix for the firmware constraint.

## User stories

1. **Diagnostic.** User clicks Test on a slot, presses that pedal, and sees
   "Emits **F16** ✓ — matches config." Confirms the pedal works and is configured
   correctly.
2. **Reconcile (the #7 escape hatch).** The pedal emits a key other than config
   expects (e.g. after BLE programming that hasn't been power-cycled, or a
   pre-programmed pedal). User sees the mismatch and chooses:
   - **Use F19** — adopt the emitted key into config. The listener rebuilds and
     catches it immediately. No reprogramming, no power-cycle.
   - **Reprogram to F16** — write the configured key to the device via the existing
     program path (BLE still warns to power-cycle).

## Architecture

### Capture mechanism — capture mode on `PedalListener`

The runtime listener (`Sources/Footswitch/PedalListener.swift`) is a
`CGEventTap` that swallows configured trigger keys before they reach any
application. A plain `NSEvent` monitor in the Settings window therefore would not
reliably observe a trigger key. Capture must happen at the event-tap level.

**Decision:** add a transient *capture mode* to the existing `PedalListener`
rather than installing a second tap.

- When armed, the listener grabs the first **non-modifier** keydown of any key,
  swallows it (so it never reaches the focused Settings window), fires a capture
  callback with the raw keycode, and reverts to normal mode.
- While armed, normal action dispatch is suspended app-wide so the press does not
  fire dictation or an app rule in a background app.
- Arming carries a **15-second timeout** and a **Cancel** affordance.
- Rejected alternative: a second one-shot `CGEventTap` head-inserted for the test.
  Rejected because two simultaneous taps add teardown edge cases and contention;
  the existing listener already owns "swallow a keydown and report it," and reusing
  one tap keeps the runtime path single-owner.

The event-tap glue stays a thin app-target shell. The reconciliation decision
logic is IO-free and unit-tested (mirrors how `PedalListener` already isolates its
`keyCodeToSlot` map from the tap).

### Reconciliation decision (IO-free core)

A pure function takes `(capturedKeyCode, expectedKey, transport, slot)` and yields
one of:

- **match** — captured key resolves to a Keymap name equal to the configured key.
  → green diagnostic confirmation, no action buttons.
- **mismatch** — captured key resolves to a known Keymap name different from
  config. → offer **Use \<captured\>** (adopt) and **Reprogram to \<expected\>**.
- **unknown** — captured keycode has no Keymap name. → show raw code
  ("Emits unknown key (0x6E)"); **Use** disabled (can't store/catch an unnamed
  key); **Reprogram** still offered.

### Adopt-into-config

On **Use \<captured\>**:

- Update `triggers.<currentTransport>` slot N's `key` to the captured key name.
- Persist and reload through the existing `ConfigStore.save` + `AppDelegate.reload`
  path so the listener rebuilds and catches the new key immediately.
- Only the currently-connected transport's list is touched — the device emits per
  the transport it is connected on, matching the per-transport `Triggers` model.
- Current transport is taken from the existing `currentTransport()` helper.

### Reprogram-to-expected

Reuses the existing `programSlot(_:button:)` path verbatim, including the BLE
power-cycle alert (`alert.programmed.bluetooth`).

## UI

Per-slot rows in `SettingsView` gain a `[Test]` button next to `[Program]`. Each
row is a small state machine:

```
idle      →  Slot 2   F17 ⚠   [Program] [Test]
armed     →  Slot 2   "Press pedal 2 now…"                 [Cancel]   (15s)
result ok →  Slot 2   "Emits F17 ✓ matches"  (green, auto-clears) [Program] [Test]
mismatch  →  Slot 2   "Emits F19, expected F17"  [Use F19] [Reprogram to F17] [Cancel]
unknown   →  Slot 2   "Emits unknown key (0x6E)"  [Reprogram to F17] [Cancel]
```

- Only one slot may be armed at a time; arming one disables Test on the others.
- Test is hidden/disabled under the same "no device / transport not connected"
  condition the existing Program button uses.

## Edge cases & error handling

- **Unknown captured key:** show raw code; disable Use; allow Reprogram.
- **Modifier/combo press:** ignored during capture (single-key model). Deferred to
  **#10**.
- **Timeout (15s, no press):** revert to idle, "No key detected — is the pedal
  connected?"
- **Captured key already matches config:** green diagnostic confirmation only.
- **No device / BLE not connected:** Test unavailable (same gating as Program).
- **Adopted key collides with another slot's trigger:** the listener's existing
  "first writer wins per keycode" dedup still holds; surface a non-blocking warning
  ("F19 is also slot 1's key") rather than block adoption.

## Testing

- **Core / unit (IO-free):**
  - Reconciliation decision: `(capturedKeyCode, expectedKey, transport, slot)` →
    match | mismatch | unknown, plus the correct config mutation for adopt.
  - Keymap name resolution for adopt-eligibility (known vs unknown keycode).
  - Adopt config mutation round-trips through `ConfigStore`.
- **App-target:** the capture-mode tap stays a thin shell around the testable
  decision logic; manual verification for the live event-tap capture.
- **Localization:** new L10n keys (arm prompt, match / mismatch / unknown / timeout
  strings, Use / Reprogram labels) added across all 30 locales;
  `LocalizationParityTests` green.

## Related

- #7 — FS17Pro BLE live-apply investigation (why Test is the chosen mitigation).
- #10 — modifier keys in trigger detection (combo capture deferred there).
- #9 — per-device / per-transport trigger configuration (separate spec).
