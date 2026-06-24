# Modifier keys in trigger detection (end-to-end)

**Issue:** [#10](https://github.com/ericfitz/footswitch/issues/10)
**Status:** Design approved — pending implementation plan
**Date:** 2026-06-24

## Problem

The runtime listener (`PedalListener`) matches a pressed key by **keycode alone**
(`keyboardEventKeycode`), ignoring modifier flags. `TriggerKey` is `{ key, slot }`
with no modifiers. So a foot switch that emits a modifier combo (e.g. `⌃F13`,
`⌃⌥C`) cannot be expressed as a trigger, and two buttons that share a keycode but
differ by modifier are indistinguishable — a bare `F13` trigger fires for any
`F13` event regardless of held modifiers.

The device side already supports modifiers: the USB and BLE program payloads write
the modifier byte (`DeviceModifier.bits(for: combo.modifiers)`), read-back parses
it (`parseKeyResponse` fills `KeyCombo.modifiers`), and `verify` compares full
`KeyCombo` equality (`combo == expected`). The gap is entirely on the
config/detection/capture side, which always feeds those paths an empty modifier
set.

This spec closes that gap end-to-end: detection, Test-button capture, config, and
programming all carry modifier combos.

## Goals

- `TriggerKey` can express a modifier combo (backward-compatible with the bare-key
  form).
- `PedalListener` matches `(keycode + modifiers)` with **exact** modifier semantics.
- The Test button captures the full combo a pedal emits and adopts it into config.
- The Program button writes the configured combo (already supported by the program
  payloads once the trigger carries modifiers); verify compares modifiers.

## Non-goals

- Subset / "modifiers-are-a-superset" matching (see Matching semantics).
- A Settings UI for hand-editing per-device trigger modifiers — the `devices`
  table stays config-editable (#4 ethos) and Test-adopt is the in-app path.
- Changing the action side (`Action`/`KeyCombo`) — actions already model modifiers.

## Matching semantics — exact

A trigger fires only when the event's active modifiers, **masked to the four device
modifiers** (`⌃⌥⇧⌘`), **equal** the trigger's modifier set exactly.

- `{F13}` fires on a bare `F13` only; `{⌃F13}` fires on `⌃F13` only.
- Consistent with how `verify` already compares (`combo == expected`) and faithful
  to "the pedal emits *this* combo."
- **Accepted behavior change:** a bare-key trigger no longer fires if a modifier is
  *incidentally held* while pressing the pedal (`⇧F13` event ≠ `{F13}`). This is the
  deliberate consequence of exact semantics. Other modifiers (Caps Lock, `fn`,
  numeric-pad, etc.) are outside the mask and never affect matching.

## Architecture

### 1. Data model — `TriggerKey.modifiers`

```swift
public struct TriggerKey: Codable, Equatable, Sendable {
    public var key: String
    public var slot: Int
    public var modifiers: [Modifier]   // NEW; default []

    public var combo: KeyCombo { KeyCombo(modifiers: modifiers, key: key) }
}
```

- Custom `Codable`: `modifiers` decodes to `[]` when absent (the existing bare-key
  form still decodes); encoded **only when non-empty** so existing
  `devices[].triggers` stay byte-stable.
- `Modifier` already conforms to `Codable, CaseIterable` and is reused as-is.

### 2. Listener — exact `(keycode + modifiers)` match

- Replace `keyCodeToSlot: [UInt16: Int]` with a map keyed by a small `Hashable`
  match key:

  ```swift
  struct TriggerMatch: Hashable { let keyCode: UInt16; let modBits: UInt64 }
  // built per trigger: keyCode = Keymap.keyCode(for: tk.key),
  //                    modBits = Keymap.flagBits(for: tk.modifiers)
  ```

- In `handle`, compute `let mods = event.flags.rawValue & Self.deviceModifierMask`
  where `deviceModifierMask = 0x20000 | 0x40000 | 0x80000 | 0x100000` (shift,
  control, option, command — the same bit values `Keymap.flagBits` produces), and
  look up `TriggerMatch(keyCode: code, modBits: mods)`. Exact match.
- First-writer-wins dedup is now per `(keyCode, modBits)`, so `{F13}` and `{⌃F13}`
  can occupy different slots. Debounce is keyed per distinct match. Triggers whose
  `key` does not resolve via `Keymap` are skipped (as today). Empty/unresolved set
  falls back to `(F13, no modifiers) → slot 1`.
- **Testable seam:** the match decision is a pure function
  `slot(forKeyCode:modBits:in table:) -> Int?` (and the table-builder from
  `[TriggerKey]`), unit-tested independently of the `CGEventTap` glue.

### 3. Test-button capture (#6 integration) — capture the full combo

- `PedalListener.beginCapture` handler changes from `@Sendable (UInt16) -> Void` to
  `@Sendable (UInt16, UInt64) -> Void` (keycode + masked modifier bits). The capture
  branch reports `(keyCode, event.flags.rawValue & deviceModifierMask)`.
- `AppDelegate.beginCapture`'s completion builds a `CapturedKey` from both.
- `CapturedKey` carries a combo:

  ```swift
  enum CapturedKey: Equatable, Sendable {
      case named(KeyCombo)     // was: .named(String)
      case unknown(UInt16)
      case none
      static func from(keyCode: UInt16, modifierBits: UInt64) -> CapturedKey
  }
  ```

  `from` resolves the key name via `Keymap.keyName(forCode:)` and the modifiers via
  `Keymap.modifiers(forFlagBits:)` (new reverse helper), yielding `.named(KeyCombo)`
  or `.unknown(code)`.
- `TriggerReconciler.reconcile(captured:expected:)` takes `expected: KeyCombo` and
  compares full combos (case-insensitive key + equal modifier set):
  - `match(combo)` — captured equals expected;
  - `mismatch(captured: KeyCombo, expected: KeyCombo)`;
  - `unknown(code: UInt16, expected: KeyCombo)`;
  - `noKey`.
  Display strings come from `KeyComboFormatter.display`.

### 4. Resolution / adopt — combos, not bare keys

- Add `Config.triggerCombo(in devices: [Device], forVendorID:productID:slot:) ->
  KeyCombo` (matching entry's `TriggerKey.combo`, else `defaultTriggerKeys`'
  combo). The bare-key `Config.triggerKey(in:...) -> String` helper is replaced by /
  reframed around the combo form.
- Settings `keyForSlot(_:device:)` returns a `KeyCombo`; `programSlot` and
  `verifyAndRenderRow` use it directly (drop the `KeyCombo(modifiers: [], key:)`
  wrapping). Program + verify then carry modifiers with no further change.
- `Config.adoptingTriggerKey(in:key:slot:for:)` →
  `Config.adoptingTriggerCombo(in: devices, combo:slot:for:)`, and
  `Device.adopting(key:slot:)` → `Device.adopting(combo:slot:)`, storing the
  combo's `modifiers` on the `TriggerKey`.
- `defaultTriggerKeys` are unchanged (bare keys; `modifiers == []`).

### 5. Display / localization

- The Settings device-row status, Test prompt/outcome, and Use/Reprogram labels
  render the full combo via `KeyComboFormatter.display(combo)` in place of a bare
  key name. The existing L10n format strings (`%@` key) are reused with the combo
  display string. **No new localized keys expected;** `LocalizationParityTests`
  stays green (confirm during implementation).

## Backward compatibility / migration

- Existing `devices[].triggers` entries decode with `modifiers == []` → exact match
  on the bare key, identical to today for pedals that emit a bare key.
- The encoder omits empty `modifiers`, so already-saved configs round-trip
  byte-for-byte.
- No config-version bump needed; the change is an additive, tolerant field.

## Testing

**Core / IO-free (unit):**
- `TriggerKey` codable: `modifiers` absent → `[]`; non-empty round-trips; empty
  omitted on encode (byte-stable). `combo` helper.
- `Keymap.modifiers(forFlagBits:)` reverse mapping (and the mask constant).
- Pure listener match: table-builder from `[TriggerKey]` (dedup per `(keyCode,
  modBits)`, skip unresolved, F13 fallback) and `slot(forKeyCode:modBits:)` exact
  lookup (bare vs modifier triggers; `⇧F13` does not match `{F13}`).
- `CapturedKey.from(keyCode:modifierBits:)` named/unknown.
- `TriggerReconciler.reconcile` over combos: exact match incl. modifiers, mismatch
  on differing modifiers, unknown, noKey.
- `Config.triggerCombo` resolution; `adoptingTriggerCombo`/`Device.adopting(combo:)`
  store modifiers; round-trip through `ConfigStore`.

**App target:** `PedalListener`/`AppDelegate`/Settings wiring builds warning-free;
manual hardware verification of programming, detecting, and Test-adopting a real
modifier combo on a USB and a BLE pedal.

**Localization:** `LocalizationParityTests` green (no new keys expected).

## Related

- #6 — Test button (capture/adopt path extended here from bare key to combo).
- #9 — per-device trigger config (`TriggerKey` lives on `Device.triggers`; this adds
  the modifier field).
- The device program/verify paths (`FootswitchProgram.keyReports`,
  `BLEProgramPayload`, `parseKeyResponse`, `PedalProgrammer.verify`) already model
  modifiers and need no changes beyond receiving non-empty combos.
