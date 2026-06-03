# Multi-Pedal Foot Switch Support — Design

Date: 2026-06-03
Status: Reviewed (autonomous)

## Goal

Support multi-pedal USB foot switches (e.g. the common 3-pedal PCsensor/iKKEGOL
page-turner units) end to end:

1. **Slot-aware detection & programming.** Learn that a connected device has 1, 2,
   or 3 physical pedals ("slots"), and program each slot independently with the key
   the app catches for that slot.
2. **Graceful single ↔ multi UI.** The Settings device section and rules table
   adapt to the detected pedal count without breaking the single-pedal experience.
3. **Per-app, per-slot actions.** Each app rule can map slot 1 / slot 2 / slot 3 to
   distinct key combos (or dictation), resolved at press time by which slot fired.
4. **Back-compatible config.** Existing single-pedal `config.json` files keep
   working unchanged; new fields are additive and migrate losslessly.

This removes the README's "does not currently support multi-pedal devices"
limitation (GitHub issue #2).

## Context (real codebase facts)

- SwiftPM macOS menu-bar app, Swift 6, AppKit. `LSUIElement`. Two targets:
  `FootswitchCore` (pure, `swift test`-covered logic) and `Footswitch` (AppKit/IO).
- **The runtime press path is trigger-key based, not device-based.**
  `Sources/Footswitch/PedalListener.swift` installs a single `CGEventTap`, resolves
  exactly one `config.triggerKey` to a virtual key code via `Keymap.keyCode(for:)`,
  debounces with one `Debouncer`, **swallows** that key (returns `nil` from the tap
  callback so the key never reaches the focused app), and calls a single `onFire`
  closure. It does not know which hardware produced the key — multi-pedal devices
  emit a *different key per pedal*, so the listener must learn to catch and
  distinguish more than one key. This is the central architectural change.
- `Sources/Footswitch/AppDelegate.swift` wires it up: builds one `PedalListener`
  with `config.triggerKey`, and `handlePress()` resolves the frontmost-app action
  via `RuleResolver.resolve(bundleID:config:)` then dispatches it with one
  `ActionDispatcher`.
- **Slot identity already exists in the programming layer.** `FootswitchProgram` in
  `Sources/FootswitchCore/FootswitchDevice.swift` is already parameterized by
  `pedalIndex` (0-based): `keyReports(pedalIndex:combo:)` and `queryReport(pedalIndex:)`
  encode `pedalIndex + 1` into byte 3 of the header/query reports. The
  FS17Pro BLE capture (`docs/superpowers/specs/2026-06-02-fs17pro-ble-programming-protocol.md`)
  confirms the device addresses pedals by this 1-based index (it programmed
  "pedal 2"). **But the app target hardcodes `pedalIndex: 0` everywhere** —
  `FootswitchHIDController.verifyConfiguration`, `.deviceInfo`, and `.program` all
  read/write only slot 0. So the *protocol* understands slots; the *app* does not.
- **The device table does not record pedal count.** `SupportedDevice` in
  `FootswitchDevice.swift` has `vendorID`, `productID`, `program`, and `name`. The
  real `Program` enum today is `case footswitch, scythe, scythe2, footswitch1p`
  (`FootswitchDevice.swift:8`) — **there is no `.footswitchBLE` case in the
  codebase.** A `.footswitchBLE` case is *proposed* by the separate, unmerged
  FS17Pro design specs (`docs/superpowers/specs/2026-06-0{2,3}-fs17pro-bluetooth-support-design.md`);
  this multi-pedal spec must not treat it as an existing symbol. `SupportedDevice`
  has no `pedalCount`. All current `SupportedDevices.all` entries are single-pedal in
  practice. Multi-pedal PCsensor units typically share the same `.footswitch` family
  and VID/PID as single-pedal ones (the count is a hardware SKU difference), so a
  static table column is unreliable; count must be *detected*.
- **Config / models** (`Sources/FootswitchCore/Models/`):
  - `Config` (`Config.swift`): `triggerKey: String`, `dictationShortcut`, `debounceMs`,
    `defaultAction`, `rules`. Has a custom `init(from:)` that already performs
    forward-migration (a legacy `keyCombo` `defaultAction` migrates to `.dictation`).
  - `Rule` (`Rule.swift`): `match` (bundle ID), `appName`, `action: Action`.
  - `Action` (`Action.swift`): `.keyCombo(KeyCombo)` | `.dictation`, with custom
    `Codable` keyed on `"type"`.
  - `DefaultAction` (`DefaultAction.swift`): `.dictation` | `.none` (custom Codable,
    migrates removed `muteInput` → `.none`). `ResolvedAction`: `.keyCombo` |
    `.dictation` | `.none`.
  - `KeyCombo` / `Modifier` in `Action.swift`.
- `RuleResolver.resolve(bundleID:config:)` returns one `ResolvedAction`: first
  exact bundle-ID rule wins, else `config.defaultAction`.
- **Settings UI** (`Sources/Footswitch/SettingsView.swift`): an AppKit
  `SettingsViewController`. A device section (`refreshDeviceStatus`) shows
  detected/verified/mismatch/unreadable status + a **Program pedal** button gated on
  the `.footswitch` family; a default-action checkbox; and an `NSTableView` of rules
  with two columns — "Application" and "Shortcut", added once in `configureTable()`.
  The shortcut column hosts a `ShortcutCaptureView` (live key recorder); its cell
  closure captures only `row` and calls `updateShortcut(row:combo:)`. Every mutation
  auto-saves via `onSave`. **`ShortcutCaptureView` only ever emits a captured combo
  via `onCapture`** — Escape cancels without changing the stored combo, and there is
  **no existing "clear"/delete affordance** that removes a shortcut.
- **`detectedSlotCount()` cost.** The read path `readStoredConfig(_:pedalIndex:)`
  registers an input-report callback and **spins the run loop up to ~500 ms** waiting
  for the device's reply (`FootswitchHIDController.swift:158-162`). Probing slots
  0/1/2 is therefore up to ~1.5 s worst case. `refreshDeviceStatus` runs on the
  `@MainActor`, so a naive synchronous three-slot probe blocks the UI thread (see
  Section 5 — detection is backgrounded).
- **Localization:** 30 `.lproj` locales under
  `Sources/Footswitch/Resources/Localizations/` (verified: 30 directories present).
  `Sources/Footswitch/L10n.swift` is the single string catalog; `en` is
  authoritative. Any new user-facing string is a 30-locale change. (Note: the
  CLAUDE.md verification gate text says "16 locales"; the repo actually has 30. The
  30-locale figure is correct for this project and is what this spec uses.)
  `LocalizationParityTests` asserts key + placeholder-arity parity across all locales.
- **Tooling:** `swift build`, `swift test`. SwiftLint is used (inline
  `// swiftlint:disable` directives exist) with the default ruleset (no committed
  `.swiftlint.yml`). The `.app` is assembled by `scripts/package-app.sh`.

## Chosen approach

The hard part is **runtime slot identity**: a multi-pedal device emits a different
key for each pedal, so the app must catch up to three keys and know which slot each
one represents. Three candidate approaches:

### Candidate A — N trigger keys, one per slot (recommended)

Generalize `config.triggerKey: String` into a small ordered set of **per-slot
trigger keys**, and `PedalListener` catches *all of the keys it is told to catch*
(still one event tap, matching against a set), tagging each fire with its slot index.
`handlePress(slot:)` resolves a per-slot action for the frontmost app. Programming
writes each slot's trigger key to the corresponding `pedalIndex`. Pedal count is
**detected** at runtime (how many slots the device reports a config for) and surfaced
in the UI; the config carries up to three slot trigger keys, but the listener is only
given the keys for the slots actually present (see Section 4 — this is what keeps
single-pedal pass-through intact).

- **Pros:** Minimal, faithful extension of the existing trigger-key model — the tap,
  debounce, swallow, and resolve machinery all generalize from "one key" to "a set
  of keys." `FootswitchProgram`'s `pedalIndex` is already the right seam. No new IPC
  or device-event channel. Single-pedal stays a 1-element set (identical behavior).
- **Cons:** Requires distinct, collision-free trigger keys per slot (we have F13–F20
  available — eight function keys with no physical Mac key and no terminal escape).
  Must pick sane defaults for slots 2/3.

### Candidate B — read pedal state from the HID device directly

Open the device's HID input endpoint and read which physical pedal changed, instead
of catching synthesized keys.

- **Pros:** Truly device-native; no key collisions; could distinguish pedals even if
  two were programmed to the same key.
- **Cons:** Abandons the entire proven trigger-key/event-tap architecture; needs a
  privileged exclusive-ish HID read path that competes with the OS HID stack already
  delivering the keypress; far larger, riskier change for no user-visible benefit
  over A. The device *is* a keyboard — fighting that is wrong. **Rejected.**

### Candidate C — keep one trigger key, disambiguate by timing/sequence

Treat multiple pedals as one trigger key and use press patterns (double-tap, hold)
to pick slot 2/3.

- **Pros:** No config schema change for keys.
- **Cons:** Defeats the purpose (the device *has* independent pedals); unreliable;
  bad UX. **Rejected.**

**Recommendation: Candidate A.** It reuses the existing seams (trigger-key listener,
`FootswitchProgram.pedalIndex`, `RuleResolver`) and keeps `FootswitchCore` pure and
unit-testable. The data model grows from a single `triggerKey` + single per-app
`action` to **slot-indexed** trigger keys and **slot-indexed** per-app actions, with
slot 1 decoded from the legacy single-value fields for full back-compat.

### Rejected alternatives

- **Candidate B (native HID read path):** replaces a working architecture for no
  user benefit; high risk.
- **Candidate C (timing/sequence disambiguation):** unreliable, poor UX, ignores
  that the hardware already exposes independent pedals.
- **Static `pedalCount` column in `SupportedDevices.all`:** multi- and single-pedal
  PCsensor units share VID/PID and family, so a table column would misreport count.
  Count is detected, not tabled (see Section 1).
- **A separate `triggerKeys` listener per slot (N event taps):** redundant; one tap
  matching a key *set* is simpler and avoids N re-enable handlers.

---

## Section 1 — Slot model & device detection

### Slot as a first-class concept

Introduce a 0-based **slot index** (0, 1, 2) used uniformly across detection,
programming, config, and resolution. It maps to `FootswitchProgram`'s existing
`pedalIndex` directly (slot `i` → `pedalIndex: i` → device byte `i + 1`). The app
supports **up to 3 slots** (`Slot.maxCount = 3`), matching the dominant 3-pedal SKUs;
the constant localizes the cap if larger units appear later.

### Detecting pedal count (runtime, not tabled)

Add to `FootswitchHIDController` a `detectedSlotCount() -> Int` that probes the
device for how many pedals it can report a config for:

- Issue `FootswitchProgram.queryReport(pedalIndex:)` for `pedalIndex` 0, 1, 2 in
  turn (reusing the existing `readStoredConfig(_:pedalIndex:)`, which is already
  parameterized — only the call sites hardcode 0).
- A slot is **present** if the query returns a parseable `StoredConfig` (any of
  `.unconfigured` / `.key` / `.other`); it is **absent** if the read fails/times out
  for that index on every interface.
- Count = the highest present slot index + 1, clamped to `1...Slot.maxCount`. A
  device that answers only slot 0 is single-pedal (today's behavior, unchanged).

**This probe is expensive and must not run synchronously on the UI thread.** Each
`readStoredConfig` spins the run loop up to ~500 ms (`FootswitchHIDController.swift:158`),
so probing three slots is up to ~1.5 s. Therefore:

- `detectedSlotCount()` runs on a **background queue**; `refreshDeviceStatus`
  dispatches the probe off-main and hops back to `@MainActor` to update the UI when
  the count is known (Section 5). The device section shows the existing detected
  line immediately and fills in per-slot rows when the probe completes.
- The detected count is **cached** per connected device (keyed by VID/PID + location
  ID) for the lifetime of the Settings window so re-renders (column rebuilds, row
  reloads) don't re-probe. The cache is invalidated when the detected device changes
  or Settings is reopened.

This keeps detection truthful for units that share VID/PID with single-pedal models.
`SupportedDevice` gains **no** `pedalCount` field. (If a future device needs a
hard-coded count because it cannot answer per-slot queries, that is a separate,
additive change — out of scope here.)

`FootswitchHIDController.Detected` is unchanged; a new lightweight result type
carries the count to the UI:

```swift
struct DetectedPedal {
    let device: SupportedDevice
    let slotCount: Int          // 1...Slot.maxCount, runtime-detected
}
```

### `FootswitchDevice.swift` additions (FootswitchCore)

A small `Slot` namespace (pure, testable) holds the cap and validation:

```swift
public enum Slot {
    public static let maxCount = 3
    public static let allIndices = 0..<maxCount
    public static func isValid(_ index: Int) -> Bool { (0..<maxCount).contains(index) }
}
```

`FootswitchProgram` needs **no protocol change** — it already takes `pedalIndex`.
The per-slot data-report type byte stays `0x01` for USB (existing tests assert this).
(BLE transport, including any `0x81`-typed reports, is owned entirely by the FS17Pro
spec — see Out of scope.)

---

## Section 2 — Config & model schema (back-compatible)

### Goal

Grow `Config.triggerKey: String` (single) into per-slot trigger keys, and `Rule`'s
single `action: Action` into per-slot actions — **without** breaking existing files.

### Trigger keys → per-slot

Replace the single `triggerKey` with an ordered, slot-indexed list while keeping the
JSON key name `triggerKey` decodable for back-compat. Concretely, `Config` gains:

```swift
public var triggerKeys: [String]   // index 0 = slot 1, 1 = slot 2, 2 = slot 3
```

Decoding rules (in `Config.init(from:)`, which already does migration):

- New form: a JSON array `"triggerKeys": ["F13","F14","F15"]` decodes directly.
- **Legacy form:** a scalar `"triggerKey": "F13"` decodes to `["F13"]` (single slot).
  Both keys are attempted; `triggerKeys` wins if present, else the scalar is wrapped.
- Empty/missing → `["F13"]` (the existing single-slot default; see the default note).
- The list is clamped to `Slot.maxCount` and de-duplicated on load (two slots may not
  share a trigger key, or the listener could not tell them apart — see Section 4
  error handling).

Encoding always writes the array form `"triggerKeys"`. A one-time read of an old file
followed by any save upgrades it transparently (same pattern as the existing
`defaultAction` migration). To avoid silently dropping data, the scalar `triggerKey`
is **not** re-emitted.

**Slot trigger-key defaults.** `Config.default.triggerKeys = ["F13", "F14", "F15"]`.
F13–F15 are in `Keymap` and `HIDUsage`, have no physical Mac key, and no terminal
escape — the same desirable properties F13 has today.

**Important — the default carries three keys, but only detected slots are caught at
runtime.** Populating `triggerKeys` with three values does *not* mean the listener
catches all three. The listener is built from `triggerKeys` **clamped to the detected
slot count** (Section 4), so a single-pedal device catches only F13 and F14/F15 pass
through to the focused app exactly as before. The extra default entries exist only so
that when a 2nd/3rd pedal is detected and programmed there is a sensible key already
configured for it; they are inert (never caught, never swallowed) for single-pedal
users. This resolves what an earlier draft described inconsistently as "inert
defaults" vs. "pass the full list to the listener."

### Per-app actions → per-slot

`Rule.action: Action` becomes slot-indexed. Add a small value type:

```swift
public struct SlotActions: Codable, Equatable, Sendable {
    public var bySlot: [Int: Action]   // sparse: only configured slots present

    public func action(forSlot index: Int) -> Action?  // nil = no per-slot action
}
```

`Rule` becomes:

```swift
public struct Rule: Codable, Equatable, Sendable {
    public var match: String
    public var appName: String
    public var slots: SlotActions
}
```

Decoding rules (custom `Rule.init(from:)`):

- New form: `"slots": { "0": {…Action…}, "1": {…}, "2": {…} }`.
- **Legacy form:** a single `"action": {…Action…}` decodes into
  `SlotActions(bySlot: [0: action])` — i.e. the old action becomes slot 1's action.
- Encoding always writes `slots`; legacy `action` is not re-emitted.

`Action`, `KeyCombo`, `Modifier`, `DefaultAction`, `ResolvedAction` are **unchanged**.
`defaultAction` remains a single global fallback (it is not per-slot — see Section 3
rationale).

### Migration test surface

The property rename (`Config.triggerKey` → `triggerKeys`, `Rule.action` →
`slots`) **breaks the source compatibility of the existing coding tests**, which
must be rewritten — they are *not* "preserved verbatim":

- `ConfigCodingTests.testDecodesSpecExample` currently asserts
  `config.triggerKey == "F13"` and
  `config.rules[0].action == .keyCombo(...)` — both members are removed. Rewrite to
  `config.triggerKeys == ["F13"]` and
  `config.rules[0].slots.action(forSlot: 0) == .keyCombo(KeyCombo(modifiers: [.command], key: "D"))`.
  The same legacy JSON (scalar `triggerKey` + rule `action`) must still **decode**
  (now into `triggerKeys[0]` / `slots[0]`).
- `ConfigCodingTests.testDefaultHasDictationDefaultAndNoRules` asserts
  `Config.default.triggerKey == "F13"`; rewrite to
  `Config.default.triggerKeys == ["F13", "F14", "F15"]`.
- `ConfigCodingTests.testRoundTrips` (round-trips `Config.default`) and
  `testDecodesDefaultsAndMigratesRemovedMute` / `testLegacyKeyComboDefaultMigratesToDictation`
  use scalar `"triggerKey":"F13"` only inside JSON literals (not the removed Swift
  property), so their JSON stays valid via the legacy decode path; only assertions
  that *read* the removed Swift members change.
- New `RuleCodingTests`: legacy `"action":{…}` → `slots.bySlot == [0: action]`;
  `"slots":{"0":…,"1":…}` round-trips; encode emits `slots` (not `action`).

Note: `RuleResolverTests` continues to call `resolve(bundleID:config:)` (the kept
slot-0 wrapper, Section 3) and `Config.default`/`makeConfig` helpers that don't
reference the renamed members directly, so those assertions **do** survive unchanged.

---

## Section 3 — Resolution & dispatch (data flow)

### Slot-aware resolution

`RuleResolver` gains a slot-aware overload; the existing signature is kept as a
thin wrapper (slot 0) so call sites and tests that don't care about slots still
compile:

```swift
public static func resolve(bundleID: String?, slot: Int, config: Config) -> ResolvedAction
```

Logic for `resolve(bundleID:slot:config:)`:

1. If a rule matches `bundleID` (first wins, as today) **and** that rule has a
   per-slot action for `slot` (`rule.slots.action(forSlot: slot) != nil`), resolve
   that action (`.keyCombo` → `.keyCombo`; `.dictation` → `.dictation`).
2. Else fall back to `config.defaultAction` (`.dictation` → `.dictation`,
   `.none` → `.none`) — **the same global default applies to every slot.**

**Rationale for a global (not per-slot) default action.** The default action is the
"no rule matched" behavior; making it per-slot would multiply UI and config
complexity for negligible benefit (a user who wants slot 2 to do something specific
in an app adds a per-app, per-slot rule). YAGNI. A slot with no per-app action and a
`.dictation` default will start dictation — acceptable and predictable. Slots the
hardware doesn't have never fire, so they never reach resolution.

The existing `resolve(bundleID:config:)` becomes a thin wrapper that calls
`resolve(bundleID:slot:config:)` with `slot: 0` — preserving every current
`RuleResolverTests` assertion verbatim (those tests call the wrapper).

### Dispatch

`ActionDispatcher.dispatch(_:)` is **unchanged** — it already maps a `ResolvedAction`
to a keystroke or dictation. Slot is resolved *before* dispatch; the dispatcher never
needs to know about slots.

### End-to-end flow

```
RUNTIME (multi-pedal):
  Pedal i pressed ─macOS key event(triggerKeys[i])─▶ PedalListener tap
    keyCode ∈ {caught keys} ─▶ map keyCode→slot i ─▶ per-slot debounce ─▶ swallow
      ─▶ AppDelegate.handlePress(slot: i)
          bundleID = FrontmostApp.bundleID()
          action = RuleResolver.resolve(bundleID:, slot: i, config:)
          dispatcher.dispatch(action)
          menuBar.setLastFire(app:, slot: i, action:)

PROGRAMMING (Settings):
  For each detected slot i: write triggerKeys[i] via
    FootswitchProgram.keyReports(pedalIndex: i, combo: KeyCombo([], triggerKeys[i]))
    → IOHIDDeviceSetReport → read back via queryReport(pedalIndex: i) → verify
```

---

## Section 4 — `PedalListener` & `AppDelegate` (multi-key tap)

### PedalListener: catch a key set, tag with slot

`PedalListener` generalizes from one trigger key to an ordered list:

```swift
init(triggerKeys: [String], debounceMs: Int, onFire: @escaping @Sendable (_ slot: Int) -> Void)
```

- Build a `[UInt16: Int]` map from each trigger key's `Keymap.keyCode(for:)` to its
  slot index (skip keys that don't resolve — they simply won't fire).
- The single existing `CGEventTap` stays; in `handle(type:event:)`, look the event's
  keyCode up in the map. **Miss → pass through** (unchanged behavior for normal
  typing). **Hit → debounce, fire `onFire(slot)`, swallow.**
- **Per-slot debounce:** keep one `Debouncer` *per slot* (small `[Int: Debouncer]`)
  so a fast slot-1 press doesn't suppress a near-simultaneous slot-2 press. Each
  slot debounces independently with the same `debounceMs`.
- The tap-disabled re-enable path is unchanged.

Single-pedal devices pass a 1-element `triggerKeys`, yielding byte-for-byte the
current behavior (one key, one debounce, swallow).

### AppDelegate

- **Build the listener from `triggerKeys` clamped to the detected slot count.**
  This is the decided rule that resolves the earlier draft's contradiction: the
  listener must catch *only* keys for slots the connected device actually has, so a
  single-pedal user's F14/F15 are **not** swallowed and continue to reach apps
  normally. `PedalListener` swallows every key it is told to catch, so giving it the
  full default `["F13","F14","F15"]` on a single-pedal device would silently eat
  F14/F15 system-wide — a regression. Clamping prevents that.
  - At startup, `AppDelegate` calls `FootswitchHIDController.detectedSlotCount()`
    (off the main thread; see Section 1) and builds the listener with
    `Array(config.triggerKeys.prefix(slotCount))`.
  - **No device detected** → behave as single-slot: catch `triggerKeys[0]` only
    (today's behavior). This is conservative — never swallow more than the primary
    key when we can't confirm extra pedals exist.
  - **Detection ambiguity favors not regressing pass-through:** if the probe can't
    confirm a slot, that slot's key is *not* caught (so it is never swallowed),
    rather than caught defensively. A press on an undetected-but-present pedal would
    fall through as a literal F14/F15 keypress until the next detection; this is
    strictly safer than swallowing keys system-wide for single-pedal users.
    Re-opening Settings / replugging re-probes and rebuilds.
- `handlePress(slot:)` calls `RuleResolver.resolve(bundleID:, slot:, config:)` and
  dispatches; `setLastFire` gains the slot for display (Section 5).
- `reload(_:)` rebuilds the dispatcher as today; the documented "triggerKey/debounce
  changes take effect on next launch" rule now reads "trigger keys / debounce."
  Detection-driven listener rebuilds (e.g. plugging in a 3-pedal unit) follow the
  same next-launch semantics as today's trigger-key change unless the app already
  re-creates the listener on device-change notification (out of scope to add here).

### Trigger-key uniqueness (error handling)

Two slots mapped to the same key are indistinguishable at the tap. The config loader
(Section 2) de-duplicates `triggerKeys` on load (later duplicates dropped). The
Settings UI prevents assigning a duplicate slot trigger key (Section 5). If, despite
this, the map would collide, **last-writer-wins by slot order** and the duplicate is
dropped from the map (the higher slot becomes unreachable) — a deterministic,
non-crashing fallback.

---

## Section 5 — Settings UI (single ↔ multi, graceful)

`SettingsView.swift` adapts based on `FootswitchHIDController.detectedSlotCount()`.
The two affected areas are the **device section** and the **rules table**.

### Detection is backgrounded

`refreshDeviceStatus` must not block the `@MainActor` for the ~1.5 s worst-case
three-slot probe (Section 1). On entry it renders the immediate detected/no-device
line synchronously (cheap), then dispatches `detectedSlotCount()` to a background
queue; the completion hops back to `@MainActor` to render per-slot rows and rebuild
the rules-table columns. The detected count is cached for the Settings window's
lifetime so column rebuilds and `reloadData()` don't re-probe. While the probe is in
flight the section shows the single-slot layout (safe default), then expands.

### Device section (`refreshDeviceStatus`)

- **Detection line:** when a device is detected, show its name plus the detected
  pedal count, e.g. "✓ PCsensor FootSwitch (3 pedals)" via a new pluralized
  `device.detectedSlots` string. Single-pedal collapses to the existing
  "✓ … detected" wording (count 1 uses the existing `device.detected` string — no
  behavioral change for single-pedal users).
- **Per-slot configuration rows:** the single config row becomes **one row per
  detected slot**. Each row reads back *that slot's* stored key
  (`verifyConfiguration(expected:slot:)`) and shows verified / mismatch / unreadable
  with a per-row **Program** button that writes `triggerKeys[slot]` to `pedalIndex:
  slot`. A "Program all" affordance is **out of scope** (YAGNI — per-row is clear and
  matches the per-slot mental model). Each row is labeled "Pedal 1 / 2 / 3" via a new
  `device.slotLabel` string.
- When `slotCount == 1`, the section renders exactly as today (one row, "Program
  pedal"), so single-pedal users see no change.

`verifyConfiguration` and `program` in `FootswitchHIDController` gain a `slot:`
parameter (default `0`), threading it to the already-parameterized
`readStoredConfig(_:pedalIndex:)` / `keyReports(pedalIndex:)`. The hardcoded `0`s at
the three current call sites become the loop/row's slot.

### Rules table

The rules table grows from 2 columns to **1 + N(detected) shortcut columns**:

- Column "Application" (unchanged).
- One shortcut column per detected slot: "Pedal 1", "Pedal 2", "Pedal 3"
  (`settings.col.pedalShortcut` positional). Each cell is a `ShortcutCaptureView`
  bound to `rule.slots.action(forSlot: i)`.
- When `slotCount == 1`, the table shows exactly one shortcut column titled
  "Shortcut" (existing `settings.col.shortcut`) bound to slot 0 — identical to today.
- The pre-fill from `KnownAppDefaults.suggestedShortcut(forBundleID:)` seeds **slot
  0 only** (the primary pedal); slots 2/3 start blank. `KnownAppDefaults` is
  unchanged.

**Dynamic columns.** Today the two columns are added once in `configureTable()`.
The per-slot table requires rebuilding the shortcut columns when the detected count
changes. On the `@MainActor` completion of the backgrounded probe (and whenever the
detected device changes while Settings is open), the controller:

1. Removes the existing shortcut `NSTableColumn`(s) (keeps the "app" column).
2. Adds N shortcut columns with identifiers `"shortcut.0"`, `"shortcut.1"`,
   `"shortcut.2"` (slot index encoded in the identifier so the cell builder can parse
   the slot back out).
3. Calls `tableView.reloadData()`.

**Per-slot, per-row cell binding & callback.** The cell builder in
`tableView(_:viewFor:row:)` parses the slot index out of the column identifier
(`"shortcut.<i>"` → `i`), seeds the capture from `rule.slots.action(forSlot: i)`, and
on capture calls a new signature
`updateShortcut(row: Int, slot: Int, combo: KeyCombo)` (replacing today's
`updateShortcut(row:combo:)`), which sets `rules[row].slots.bySlot[slot] =
.keyCombo(combo)` and saves. (The legacy single-slot path calls it with `slot: 0`.)

**Clearing a slot (new UI affordance — explicitly scoped here).** Today
`ShortcutCaptureView` has *no* way to clear a shortcut: `onCapture` only ever fires
with a captured combo, and Escape merely cancels recording without changing the
stored value. To support removing a slot's action (`bySlot[i] = nil`), this spec
adds a minimal clear affordance to `ShortcutCaptureView`:

- Add an optional `onClear: (() -> Void)?` callback alongside `onCapture`.
- While **recording**, pressing **Delete/Backspace** (`keyCode 0x33`) clears the
  combo: set `combo = nil`, stop recording, render the empty "click to set" state,
  and invoke `onClear?()`. This mirrors macOS's standard "press Delete to clear a
  shortcut" convention and reuses the existing in-recording key handling in
  `handle(_:)` (which already special-cases Escape at `keyCode 0x35`).
- The rules-table cell wires `onClear = { self.clearShortcut(row: row, slot: i) }`,
  which removes the entry (`rules[row].slots.bySlot[i] = nil`) and saves.

This closes the "Clearing a slot's capture removes that entry" gap with a concrete,
scoped mechanism rather than leaving it as undefined behavior.

`SettingsViewController` recomputes column layout when the detected count changes
(e.g. user plugs in a 3-pedal unit while Settings is open) per "Dynamic columns"
above. If **no** device is detected, the UI falls back to single-slot editing
(slot 0) so a user can still prepare a config offline — the same graceful posture as
today's "no device" state.

### Localization

New strings (all 30 locales, per the verification gate; English authoritative):

| Key | English |
|---|---|
| `device.detectedSlots` | `Detected pedal: %1$@ (%2$@ pedals)` |
| `device.slotLabel` | `Pedal %@` |
| `settings.col.pedalShortcut` | `Pedal %@` |

Plural handling uses `.stringsdict` only if a locale needs it; English "%2$@ pedals"
is acceptable for counts 2–3 (we never show "1 pedals" — count 1 uses the existing
singular `device.detected`). Existing `settings.programButton`,
`device.config.{verified,mismatch,unreadable}`, and `device.detected` are reused
unchanged. The Delete-to-clear affordance reuses existing capture strings (no new
key). This keeps the new-string footprint to **three** keys.

---

## Section 6 — Error handling

- **Detection under-/over-count:** `detectedSlotCount()` clamps to
  `1...Slot.maxCount`. If a query times out intermittently, the worst case is a slot
  row missing from Settings and that slot's key **not** being caught by the listener
  (so a press on that pedal falls through as a literal keypress rather than being
  swallowed — see Section 4). No single-pedal key is ever swallowed. Re-opening
  Settings / replugging re-probes.
- **Duplicate trigger keys:** de-duplicated on config load and prevented in the UI;
  residual collisions resolve last-writer-wins by slot order (Section 4), never
  crashing.
- **Unsupported / unknown trigger key in config:** keys that don't resolve via
  `Keymap.keyCode(for:)` are skipped by the listener (that slot won't fire) and
  rejected by the UI capture (existing `capture.unsupportedKey`). No throw.
- **Programming failure per slot:** `program(combo:slot:)` reuses the existing
  `ProgramError` and per-interface retry/read-back-confirm logic; a failed slot
  surfaces via that row's mismatch/unreadable status and the existing
  `alert.programFailed`. Other slots are unaffected (each row programs
  independently).
- **Non-`.footswitch` families** (`.scythe`, `.scythe2`, `.footswitch1p`): still not
  programmable; multi-slot programming is gated on `.footswitch` **only** (the same
  single family that is programmable today). There is no `.footswitchBLE` case in the
  codebase, so this spec does not reference it; BLE/multi-pedal composition is
  deferred to the FS17Pro work (see Out of scope). Detection may still report a count
  for display on non-programmable families.

---

## Section 7 — Testing approach

**Unit (FootswitchCore — `swift test`, no device):**

- **Config migration** (`ConfigCodingTests`, rewritten + new cases): legacy scalar
  `"triggerKey":"F13"` JSON → `triggerKeys == ["F13"]`;
  `"triggerKeys":["F13","F14","F15"]` round-trips; default `triggerKeys` is
  `["F13","F14","F15"]`; encode emits `triggerKeys` (not `triggerKey`); de-dup drops
  a repeated key on load. The existing assertions that referenced the removed
  `triggerKey`/`action` Swift members are rewritten to `triggerKeys` /
  `slots.action(forSlot:)` (these tests are **not** preserved verbatim — see
  Section 2 "Migration test surface").
- **Rule migration** (new `RuleCodingTests`): legacy `"action":{…}` →
  `slots.bySlot == [0: action]`; `"slots":{"0":…,"1":…}` round-trips; encode emits
  `slots`.
- **Slot resolution** (`RuleResolverTests` + new cases): the existing tests call the
  kept `resolve(bundleID:config:)` wrapper and stay **unchanged**; new cases call
  `resolve(bundleID:slot:config:)` — a rule with slot-1 and slot-2 actions resolves
  each slot distinctly; a slot with no per-app action falls back to the global
  default; matched-rule-wins and first-match-wins still hold per slot.
- **Slot helpers:** `Slot.isValid`, `maxCount`; `FootswitchProgram.keyReports`/
  `queryReport` for `pedalIndex` 0/1/2 produce bytes 3 = `0x01/0x02/0x03` (extends
  existing `FootswitchDeviceTests`).
- **Localization parity** (`LocalizationParityTests`): the three new keys exist in
  all 30 locales with matching placeholder arity.

**Manual / on-device (per the verification checklist; multi-pedal unit required):**

- Settings detects the correct pedal count; one config row + one shortcut column per
  pedal appears; single-pedal unit still shows the one-row/one-column layout.
- On a **single-pedal** unit with the new default config, confirm F14 and F15 are
  *not* swallowed — they reach a focused app as ordinary keypresses (proves the
  listener is clamped to detected count, no pass-through regression).
- Program each slot with a distinct key (slot 1 → F13, slot 2 → F14, slot 3 → F15);
  read-back verifies each independently. Program a slot to a *different* value first
  (e.g. F16) and read it back, then to the target, to prove the write mutates that
  specific slot (not just slot 0).
- Add a per-app rule with distinct slot-1/slot-2 actions; press each pedal in that
  app → the correct action fires; press in an unmapped app → the global default runs
  for every pedal. Clear a slot's shortcut (Delete while recording) and confirm the
  entry is removed and that slot falls back to the default. Confirm no trigger key
  leaks as a visible character.

**Verification gates (CLAUDE.md):** `swift build`, `swift test`, SwiftLint clean
before commit. New strings applied across all 30 locales.

---

## Out of scope (YAGNI)

- **Per-slot default action.** The default (no-rule-matched) action stays a single
  global setting (Section 3 rationale).
- **More than 3 slots.** `Slot.maxCount = 3` covers the dominant SKUs; a higher cap
  is a one-constant change later if a real device needs it.
- **Static `pedalCount` in the device table** / per-model count overrides. Count is
  detected; tabling it is unnecessary and error-prone for shared-VID/PID SKUs.
- **Distinguishing two pedals programmed to the *same* key** (native HID read path,
  Candidate B). Pedals must use distinct trigger keys.
- **BLE multi-pedal programming, and the `Program.footswitchBLE` enum case.** The
  `.footswitchBLE` case does **not** exist in the current codebase — it is a proposed
  addition in the separate FS17Pro specs. This multi-pedal spec gates programmability
  on `.footswitch` alone and does not depend on the FS17Pro work landing. The slot
  model is transport-agnostic (`pedalIndex`-based), so it will *compose* with BLE once
  `Program.footswitchBLE` is merged, but wiring BLE multi-pedal is owned by the
  FS17Pro spec and is explicitly out of scope here. **Ordering note:** the two efforts
  are independent — neither blocks the other; if both land, the implementer simply
  adds `.footswitchBLE` to the programmability gate at that time.
- **Device-change live re-detection / hot-rebuild of the runtime listener** beyond
  the next-launch semantics already in place (Section 4).
- **A "Program all slots" button**, drag-to-reorder pedals, or naming pedals.
- **Migrating away from the legacy JSON keys** beyond the load-time upgrade-on-save
  already specified.

---

## Affected / new files

- Edit `Sources/FootswitchCore/Models/Config.swift` — `triggerKeys: [String]`;
  decode legacy scalar `triggerKey`; default `["F13","F14","F15"]`; encode array form.
- Edit `Sources/FootswitchCore/Models/Rule.swift` — `slots: SlotActions`; decode
  legacy single `action` into slot 0.
- New `Sources/FootswitchCore/Models/SlotActions.swift` — sparse per-slot
  `[Int: Action]` value type with `action(forSlot:)` accessor + custom Codable.
- Edit `Sources/FootswitchCore/FootswitchDevice.swift` — add `Slot` namespace
  (`maxCount`, `isValid`); no change to `FootswitchProgram` (already `pedalIndex`-aware).
  No change to `Program` enum (no `.footswitchBLE` here).
- Edit `Sources/FootswitchCore/RuleResolver.swift` — add
  `resolve(bundleID:slot:config:)`; keep old signature as a slot-0 wrapper.
- Edit `Sources/Footswitch/FootswitchHIDController.swift` — `detectedSlotCount()`
  (backgrounded, cached), `DetectedPedal`; thread `slot:` through
  `verifyConfiguration`, `program`, `deviceInfo`, replacing the hardcoded
  `pedalIndex: 0`.
- Edit `Sources/Footswitch/PedalListener.swift` — accept `triggerKeys: [String]`,
  build keyCode→slot map, per-slot `Debouncer`, `onFire(slot:)`.
- Edit `Sources/Footswitch/AppDelegate.swift` — build listener from `triggerKeys`
  **clamped to detected slot count** (off-main detection); `handlePress(slot:)` →
  `RuleResolver.resolve(bundleID:slot:config:)`.
- Edit `Sources/Footswitch/SettingsView.swift` — per-slot config rows + per-slot
  shortcut columns (dynamic `NSTableColumn` rebuild, slot encoded in identifier),
  backgrounded detection, `updateShortcut(row:slot:combo:)` + `clearShortcut(row:slot:)`
  callbacks, `ShortcutCaptureView.onClear` + Delete-to-clear handling; single-pedal
  fallback layout.
- Edit `Sources/Footswitch/MenuBarController.swift` — `setLastFire` shows the slot
  that fired (e.g. "Pedal 2").
- Edit `Sources/Footswitch/L10n.swift` — add `deviceDetectedSlots`, `deviceSlotLabel`,
  `settingsColPedalShortcut` accessors.
- Edit `Sources/Footswitch/Resources/Localizations/*/Localizable.strings` (all 30) —
  the three new keys.
- Edit `Tests/FootswitchCoreTests/ConfigCodingTests.swift` — **rewrite** the
  assertions that read the removed `triggerKey`/`action` members (to `triggerKeys` /
  `slots.action(forSlot:)`); add trigger-key migration cases.
- New `Tests/FootswitchCoreTests/RuleCodingTests.swift` — rule/slot migration.
- Edit `Tests/FootswitchCoreTests/RuleResolverTests.swift` — add per-slot resolution
  cases (existing wrapper-based assertions unchanged).
- Edit `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift` — multi-slot
  `keyReports`/`queryReport` bytes; `Slot` helpers.
- Edit `docs/supported-devices.md` & `README.md` — note multi-pedal support; remove
  the "does not support multi-pedal devices" limitation.

## Assumptions

- **Max 3 slots.** The 3-pedal page-turner is the target SKU; `Slot.maxCount = 3`.
- **Slot-2/3 default trigger keys are F14 and F15** (F13 stays slot 1). All three are
  in `Keymap`/`HIDUsage`, collision-free with normal typing, and consistent with the
  app's F13 rationale. They are configured by default but only *caught* when the
  matching pedal is detected (Section 2/4).
- **Pedal count is detected at runtime** by probing per-slot config read-back, not
  recorded in `SupportedDevices.all`, because multi- and single-pedal PCsensor units
  share VID/PID and the `.footswitch` family. Detection is backgrounded and cached
  because each per-slot probe spins the run loop up to ~500 ms (~1.5 s for three).
- **Slots are addressed by the existing `pedalIndex`** (slot `i` → `pedalIndex i` →
  device byte `i+1`), matching `FootswitchProgram` and the FS17Pro capture.
- **The default action remains global**, not per-slot (UI/UX simplicity; per-app
  per-slot rules cover the real need).
- **Trigger keys must be unique per slot**; duplicates are de-duplicated on load and
  prevented in the UI (resolution would otherwise be ambiguous).
- **The runtime listener catches only keys for detected slots** (clamped), so
  single-pedal users never have F14/F15 swallowed. This is the decided resolution of
  the listener-scope question.
- **Back-compat is upgrade-on-save:** legacy `triggerKey`/`action` decode into slot 0
  and the next save rewrites the file in the new `triggerKeys`/`slots` form; old keys
  are not re-emitted.
- **`KnownAppDefaults` seeds slot 0 only**; slots 2/3 start blank.
- **JSON key names** are `triggerKeys` (array of strings) and, in each rule, `slots`
  (object keyed by stringified slot index → `Action`). These names were chosen
  autonomously to read naturally and migrate cleanly from the singular forms.
- **No `.footswitchBLE` dependency.** This spec is independent of the FS17Pro BLE
  spec; programmability is gated on `.footswitch` only.
- **No `.swiftlint.yml` is added**; the default SwiftLint ruleset already in use applies.

## Open questions (need a human product decision)

- **Live device-change behavior of the runtime listener.** This spec keeps today's
  "trigger-key changes take effect on next launch" semantics, so plugging in a
  multi-pedal unit while the app is already running may not start catching the new
  slots' keys until relaunch (Settings re-probes for display, but the runtime tap is
  built at launch). Whether to add live re-detection + listener rebuild on USB
  device-change notification is a product/UX call (added latency, complexity vs.
  convenience) and is currently scoped **out**. If "hot-plug just works" is required,
  this needs explicit sign-off and a small additional design (device-change observer
  → recompute clamped `triggerKeys` → rebuild `PedalListener`).

---

## Review & revision notes

This spec was revised to integrate a reviewer pass ("Issues Found", 4 issues +
6 recommendations). All four issues were verified against the real source and fixed.

**Issue 1 — phantom `.footswitchBLE` case.** Verified: `SupportedDevice.Program` is
`case footswitch, scythe, scythe2, footswitch1p` (`FootswitchDevice.swift:8`); no
`.footswitchBLE` exists in `Sources/`. It appears only in the unmerged FS17Pro specs.
Fixed by removing every `.footswitchBLE` reference from this spec: the Context
section now states the real enum and labels `.footswitchBLE` as a proposed FS17Pro
addition; Section 6 gates programming on `.footswitch` **only**; the Out-of-scope
bullet now explicitly states this spec does not depend on the FS17Pro work and adds
an ordering note (the two efforts are independent). The Section 1 BLE `0x81` aside
was reframed as FS17Pro-owned.

**Issue 2 — Section 2 vs Section 4 contradiction on the caught key-set.** Verified:
`PedalListener.handle` returns `nil` to swallow any matched key
(`PedalListener.swift:55`); with default `triggerKeys = ["F13","F14","F15"]` the old
Section 4 wording ("pass the full configured list, do NOT clamp") would swallow
F14/F15 system-wide for single-pedal users. Resolved decisively in favor of **not
regressing pass-through**: Section 4 (and Section 2's default note, Section 6, the
Assumptions, and the flow diagram) now specify the listener is built from
`triggerKeys` **clamped to the detected slot count**; no-device falls back to slot 0
only; undetected slots are not caught (fall through as literal keypresses rather than
being swallowed). Added a single-pedal F14/F15 pass-through manual test.

**Issue 3 — "preserved verbatim" vs renamed-member tests.** Verified:
`ConfigCodingTests` asserts `config.triggerKey == "F13"` (lines 19, 36) and
`config.rules[0].action == .keyCombo(...)` (line 24); these reference removed members
and cannot compile verbatim. `RuleResolverTests` only calls the kept
`resolve(bundleID:config:)` wrapper and so does survive. Fixed the Section 2
"Migration test surface", Section 7, and the "Affected files" entry to state clearly
that `ConfigCodingTests` assertions touching `triggerKey`/`action` must be
**rewritten** (with the exact new assertions), while only the wrapper-based
`RuleResolverTests` stay unchanged. Removed the misleading "preserved verbatim" claim
for the coding tests.

**Issue 4 — per-slot capture, dynamic columns, and the missing clear path.**
Verified: columns are added once in `configureTable()` (lines 171-179); the cell
closure captures only `row` and calls `updateShortcut(row:combo:)` (lines 379-381);
`ShortcutCaptureView.onCapture` only ever emits a captured combo and Escape merely
cancels — there is **no** clear path. Fixed Section 5 to (a) specify dynamic
`NSTableColumn` rebuild with the slot index encoded in the column identifier
(`"shortcut.<i>"`), (b) state the new cell callback signature
`updateShortcut(row:slot:combo:)`, and (c) concretely scope a clear affordance: add
`onClear` to `ShortcutCaptureView` and handle Delete/Backspace (keyCode 0x33) while
recording to set `bySlot[i] = nil` (mirroring the existing Escape special-case at
0x35). This turns "clearing removes the entry" from undefined behavior into scoped UI
work.

**Recommendations:**
- *Bound the caught key-set* — applied (Issue 2).
- *Drop `.footswitchBLE` / add dependency note* — applied; dropped all references and
  added an explicit "independent, no dependency" note (Issue 1).
- *Clarify which tests are rewritten vs unchanged* — applied (Issue 3).
- *Spec the clear path + `(row, slot, combo)` callback* — applied (Issue 4).
- *Note the 16-vs-30 locale discrepancy* — applied: Context now flags that CLAUDE.md
  says 16 but the repo has 30 (verified), and the spec uses 30.
- *Note the ~1.5 s blocking probe / background or cache detection* — applied: added
  the cost note in Context, made `detectedSlotCount()` backgrounded + cached in
  Section 1, and threaded the off-main detection through Section 5 (UI) and Section 4
  (startup listener build).

**Deferred (human product decision):** Live hot-plug re-detection of the runtime
listener was added to a new "Open questions" section and is listed as an unresolved
concern. The spec keeps today's next-launch semantics; whether to add a USB
device-change observer that rebuilds the listener is a UX/complexity trade-off
needing sign-off. This was not silently assumed because it changes runtime behavior
beyond the issue's stated scope.
