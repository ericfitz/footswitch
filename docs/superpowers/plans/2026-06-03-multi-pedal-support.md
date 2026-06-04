# Multi-Pedal Foot Switch Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a multi-pedal USB foot switch program, detect, and trigger each physical pedal independently, with per-app / per-pedal actions, while single-pedal and BLE behavior stay unchanged.

**Architecture:** Build on the *already-merged* slot-aware, per-transport model (`Triggers` + `TriggerKey { key, slot }`), NOT the original spec's `triggerKeys:[String]` / `SlotActions` proposal (which predates and conflicts with that merge). We add: (1) a slot field already exists on `TriggerKey` — start *honoring* it; (2) per-slot per-app actions via a new `SlotActions` value type on `Rule` (1-based slot keys, matching `TriggerKey.slot`); (3) slot-aware resolution; (4) `slot:`-threaded USB programming + read-back and a backgrounded `detectedSlotCount()`; (5) a keycode→slot map in `PedalListener` so each pedal fires `onFire(slot:)`; (6) live hot-plug re-detection that rebuilds the listener on USB device-change; (7) per-slot Settings rows/columns with a Delete-to-clear affordance.

**Tech Stack:** Swift 6, SwiftPM, AppKit (`Footswitch` target), pure logic in `FootswitchCore`, IOKit HID (USB), CoreBluetooth (BLE), XCTest.

---

## Conventions decided for this plan (read first)

- **Slot is 1-based everywhere in the model**, matching the existing `TriggerKey.slot` ("1 = first button"). Convert to the wire's 0-based `pedalIndex` ONLY at the HID boundary: `pedalIndex = slot - 1`. Do **not** introduce a second 0-based slot convention.
- **`Slot.maxCount = 3`**, valid slots are `1...3`.
- **Default trigger keys:** USB gains `[F13/slot1, F14/slot2, F15/slot3]`; Bluetooth stays `[F13/slot1]` (BLE is single-pedal FS17Pro). The listener is built from `config.allTriggerKeys` (the de-duplicated union) **clamped to detected slots** for USB (Task 9), so a single-pedal user never has F14/F15 swallowed.
- **Multi-slot programming is USB-only** (`.footswitch`). BLE keeps its fixed single `pedalIndex = 1`; we do NOT make BLE multi-slot.
- **Default action stays global** (not per-slot) — unchanged.
- **Back-compat:** legacy `Rule.action` decodes into slot 1; encoding emits `slots` only. The three existing `Config` decode shapes are untouched.
- **Locales:** 30 `.lproj` dirs. Every new user-facing string is a 30-locale change; `LocalizationParityTests` enforces key + placeholder-arity parity. English is authoritative.
- **Verification gate (run before EVERY commit):** `swift build && swift test`, and SwiftLint clean. Do not commit on red.

---

## File Structure

**FootswitchCore (pure, unit-tested):**
- Create `Sources/FootswitchCore/Models/SlotActions.swift` — sparse `[Int: Action]` (1-based) per-slot map, custom Codable.
- Modify `Sources/FootswitchCore/Models/Rule.swift` — replace `action: Action` with `slots: SlotActions`; decode legacy `action` into slot 1; keep a convenience `init(match:appName:action:)`.
- Modify `Sources/FootswitchCore/FootswitchDevice.swift` — add `Slot` namespace (`maxCount`, `validRange`, `isValid`). `FootswitchProgram` already takes `pedalIndex`; no protocol change.
- Modify `Sources/FootswitchCore/Models/Config.swift` — change `Config.default` USB triggers to F13/F14/F15 (slots 1/2/3); Bluetooth stays F13/slot1.
- Modify `Sources/FootswitchCore/RuleResolver.swift` — add `resolve(bundleID:slot:config:)`; keep `resolve(bundleID:config:)` as a `slot: 1` wrapper.

**Footswitch (AppKit/IO):**
- Modify `Sources/Footswitch/PedalProgrammer.swift` — add `slot:` params (default `1`) to `readStoredConfig`/`program`/`verify`.
- Modify `Sources/Footswitch/FootswitchHIDController.swift` — thread `slot:` through USB read/program/info; add `detectedSlotCount()` (backgrounded helper) + per-slot `verifyConfiguration(expected:slot:)` / `program(combo:slot:)`.
- Modify `Sources/Footswitch/BLEPedalProgrammer.swift` — conform to the new protocol signatures (ignore `slot:`, keep fixed `pedalIndex = 1`).
- Modify `Sources/Footswitch/PedalListener.swift` — build a `[UInt16: Int]` keycode→slot map; `onFire(slot:)`.
- Modify `Sources/Footswitch/AppDelegate.swift` — `handlePress(slot:)` → slot-aware resolve; build listener clamped to detected slots off-main; live hot-plug re-detection via IOKit device-change observer.
- Modify `Sources/Footswitch/SettingsView.swift` — per-slot config rows + per-slot shortcut columns (dynamic rebuild), `updateShortcut(row:slot:combo:)` + `clearShortcut(row:slot:)`, `ShortcutCaptureView.onClear` + Delete-to-clear.
- Modify `Sources/Footswitch/MenuBarController.swift` — `setLastFire(app:slot:action:)` shows which pedal fired.
- Modify `Sources/Footswitch/L10n.swift` — add `deviceDetectedSlots`, `deviceSlotLabel`, `settingsColPedalShortcut`, `menuLastFireSlot`.
- Modify `Sources/Footswitch/Resources/Localizations/*/Localizable.strings` (all 30) — the new keys.

**Tests:**
- Create `Tests/FootswitchCoreTests/RuleCodingTests.swift`
- Create `Tests/FootswitchCoreTests/SlotActionsTests.swift`
- Modify `Tests/FootswitchCoreTests/RuleResolverTests.swift`
- Modify `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift`
- Modify `Tests/FootswitchCoreTests/ConfigCodingTests.swift`
- (`LocalizationParityTests.swift` is unchanged but must stay green.)

**Docs:**
- Modify `docs/supported-devices.md`, `README.md`.

---

## Task 1: `Slot` namespace (FootswitchCore)

**Files:**
- Modify: `Sources/FootswitchCore/FootswitchDevice.swift` (append the `Slot` enum at end of file)
- Test: `Tests/FootswitchCoreTests/FootswitchDeviceTests.swift`

- [ ] **Step 1: Write the failing test** — append to `FootswitchDeviceTests.swift`:

```swift
func testSlotNamespace() {
    XCTAssertEqual(Slot.maxCount, 3)
    XCTAssertEqual(Array(Slot.validRange), [1, 2, 3])
    XCTAssertTrue(Slot.isValid(1))
    XCTAssertTrue(Slot.isValid(3))
    XCTAssertFalse(Slot.isValid(0))
    XCTAssertFalse(Slot.isValid(4))
}

func testKeyReportsEncodePedalIndexInByte3() {
    // slot i (1-based) -> pedalIndex i-1 -> device byte i.
    for slot in Slot.validRange {
        let reports = FootswitchProgram.keyReports(
            pedalIndex: slot - 1, combo: KeyCombo(modifiers: [], key: "F13"))
        XCTAssertEqual(reports?.header[3], UInt8(slot))
        XCTAssertEqual(FootswitchProgram.queryReport(pedalIndex: slot - 1)[3], UInt8(slot))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FootswitchDeviceTests`
Expected: FAIL — `Slot` is undefined.

- [ ] **Step 3: Implement** — append to `Sources/FootswitchCore/FootswitchDevice.swift`:

```swift
/// Logical pedal/button slots. 1-based to match `TriggerKey.slot` ("1 = first
/// button"). Convert to the wire's 0-based `pedalIndex` with `slot - 1`.
public enum Slot {
    public static let maxCount = 3
    public static let validRange = 1...maxCount
    public static func isValid(_ slot: Int) -> Bool { validRange.contains(slot) }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FootswitchDeviceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/FootswitchDevice.swift Tests/FootswitchCoreTests/FootswitchDeviceTests.swift
git commit -m "feat(core): add Slot namespace (1-based, maxCount 3)"
```

---

## Task 2: `SlotActions` value type (FootswitchCore)

**Files:**
- Create: `Sources/FootswitchCore/Models/SlotActions.swift`
- Test: `Tests/FootswitchCoreTests/SlotActionsTests.swift`

- [ ] **Step 1: Write the failing test** — create `Tests/FootswitchCoreTests/SlotActionsTests.swift`:

```swift
import XCTest
@testable import FootswitchCore

final class SlotActionsTests: XCTestCase {
    func testAccessorReturnsConfiguredSlotAndNilOtherwise() {
        let combo = Action.keyCombo(KeyCombo(modifiers: [.command], key: "D"))
        let slots = SlotActions(bySlot: [1: combo])
        XCTAssertEqual(slots.action(forSlot: 1), combo)
        XCTAssertNil(slots.action(forSlot: 2))
    }

    func testRoundTripsCodableWithStringKeys() throws {
        let slots = SlotActions(bySlot: [
            1: .keyCombo(KeyCombo(modifiers: [.command], key: "A")),
            2: .dictation,
        ])
        let data = try JSONEncoder().encode(slots)
        let decoded = try JSONDecoder().decode(SlotActions.self, from: data)
        XCTAssertEqual(decoded, slots)
        // Keys are emitted as stringified slot indices.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["1"])
        XCTAssertNotNil(object?["2"])
    }

    func testEmptyRoundTrips() throws {
        let empty = SlotActions(bySlot: [:])
        let decoded = try JSONDecoder().decode(
            SlotActions.self, from: try JSONEncoder().encode(empty))
        XCTAssertEqual(decoded, empty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SlotActionsTests`
Expected: FAIL — `SlotActions` is undefined.

- [ ] **Step 3: Implement** — create `Sources/FootswitchCore/Models/SlotActions.swift`:

```swift
import Foundation

/// Per-slot actions for one app rule. Sparse: only configured slots appear.
/// Slot keys are 1-based, matching `TriggerKey.slot`. Encodes as a JSON object
/// keyed by the stringified slot index → `Action`.
public struct SlotActions: Codable, Equatable, Sendable {
    public var bySlot: [Int: Action]

    public init(bySlot: [Int: Action]) {
        self.bySlot = bySlot
    }

    /// The action configured for `slot` (1-based), or nil if none.
    public func action(forSlot slot: Int) -> Action? { bySlot[slot] }

    private struct SlotKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = Int(stringValue) }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SlotKey.self)
        var result: [Int: Action] = [:]
        for key in c.allKeys {
            guard let slot = Int(key.stringValue) else { continue }
            result[slot] = try c.decode(Action.self, forKey: key)
        }
        bySlot = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SlotKey.self)
        // Deterministic key order for stable round-trips.
        for slot in bySlot.keys.sorted() {
            try c.encode(bySlot[slot], forKey: SlotKey(intValue: slot)!)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter SlotActionsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/Models/SlotActions.swift Tests/FootswitchCoreTests/SlotActionsTests.swift
git commit -m "feat(core): add SlotActions (sparse 1-based per-slot Action map)"
```

---

## Task 3: `Rule.slots` with legacy `action` migration (FootswitchCore)

This breaks source compatibility of every `Rule(... action:)` callsite. We keep a
convenience initializer so existing callers (tests, SettingsView) still compile,
and we update the few places that *read* `rule.action` in later tasks (Resolver in
Task 4, SettingsView in Task 12).

**Files:**
- Modify: `Sources/FootswitchCore/Models/Rule.swift`
- Test: `Tests/FootswitchCoreTests/RuleCodingTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `Tests/FootswitchCoreTests/RuleCodingTests.swift`:

```swift
import XCTest
@testable import FootswitchCore

final class RuleCodingTests: XCTestCase {
    func testLegacyActionDecodesIntoSlot1() throws {
        let json = """
        { "match": "com.x.app", "appName": "X",
          "action": { "type": "keyCombo", "modifiers": ["cmd"], "key": "D" } }
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.slots.bySlot,
                       [1: .keyCombo(KeyCombo(modifiers: [.command], key: "D"))])
        XCTAssertNil(rule.slots.action(forSlot: 2))
    }

    func testNewSlotsFormRoundTrips() throws {
        let json = """
        { "match": "com.x.app", "appName": "X",
          "slots": {
            "1": { "type": "keyCombo", "modifiers": ["cmd"], "key": "A" },
            "2": { "type": "dictation" }
          } }
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.slots.action(forSlot: 1),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
        XCTAssertEqual(rule.slots.action(forSlot: 2), .dictation)
        let decoded = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule)
    }

    func testEncodeEmitsSlotsNotAction() throws {
        let rule = Rule(match: "com.x.app", appName: "X",
                        action: .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
        let data = try JSONEncoder().encode(rule)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["slots"], "encoder must write slots")
        XCTAssertNil(object?["action"], "encoder must not write legacy action")
    }

    func testConvenienceInitPutsActionInSlot1() {
        let rule = Rule(match: "m", appName: "n",
                        action: .keyCombo(KeyCombo(modifiers: [], key: "F13")))
        XCTAssertEqual(rule.slots.action(forSlot: 1),
                       .keyCombo(KeyCombo(modifiers: [], key: "F13")))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RuleCodingTests`
Expected: FAIL — `rule.slots` does not exist.

- [ ] **Step 3: Implement** — replace the entire contents of `Sources/FootswitchCore/Models/Rule.swift`:

```swift
import Foundation

public struct Rule: Codable, Equatable, Sendable {
    public var match: String          // frontmost app bundle ID
    public var appName: String        // display only
    public var slots: SlotActions     // per-slot (1-based) actions

    public init(match: String, appName: String, slots: SlotActions) {
        self.match = match
        self.appName = appName
        self.slots = slots
    }

    /// Convenience: a single action becomes slot 1's action (the primary pedal).
    /// Lets existing single-pedal callers keep working unchanged.
    public init(match: String, appName: String, action: Action) {
        self.init(match: match, appName: appName, slots: SlotActions(bySlot: [1: action]))
    }

    private enum CodingKeys: String, CodingKey { case match, appName, slots, action }

    // Decodes TWO shapes, newest first:
    //  - new:    "slots": { "1": Action, "2": Action, ... }
    //  - legacy: "action": Action   -> becomes slot 1's action
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = try c.decode(String.self, forKey: .match)
        appName = try c.decode(String.self, forKey: .appName)
        if let s = try? c.decode(SlotActions.self, forKey: .slots) {
            slots = s
        } else if let legacy = try? c.decode(Action.self, forKey: .action) {
            slots = SlotActions(bySlot: [1: legacy])
        } else {
            slots = SlotActions(bySlot: [:])
        }
    }

    // Encode the new `slots` form only (legacy `action` is read-only, for migration).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(match, forKey: .match)
        try c.encode(appName, forKey: .appName)
        try c.encode(slots, forKey: .slots)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter RuleCodingTests`
Expected: PASS.

- [ ] **Step 5: Run the full core suite to find broken `rule.action` readers**

Run: `swift build`
Expected: Compile errors ONLY in files that *read* `rule.action` as a property — `Sources/FootswitchCore/RuleResolver.swift` and `Sources/Footswitch/SettingsView.swift`. These are fixed in Tasks 4 and 12. If `swift build` fails only there, that's expected; proceed to commit the core model + test now (the test target for these tasks builds independently).

Actually verify the test passed in Step 4 first; do NOT commit if `swift build` of the whole package is red. Instead, do Task 4 next (it fixes the core reader) and commit Tasks 3+4 together. To keep commits green:

- [ ] **Step 5 (revised): Defer commit to Task 4.** Leave the working tree as-is and proceed to Task 4. Task 4 fixes `RuleResolver` (the only `FootswitchCore` reader of `rule.action`), after which `swift build` of `FootswitchCore` is green and we commit Tasks 3+4 together.

---

## Task 4: Slot-aware `RuleResolver` (FootswitchCore)

**Files:**
- Modify: `Sources/FootswitchCore/RuleResolver.swift`
- Test: `Tests/FootswitchCoreTests/RuleResolverTests.swift`

- [ ] **Step 1: Update existing tests + add slot cases.** In `RuleResolverTests.swift`, the existing tests build rules with `Rule(... action:)` (still valid via the convenience init) and call `resolve(bundleID:config:)` (kept wrapper). They stay as-is. Append new cases:

```swift
func testSlotAwareResolvesPerSlotAction() {
    let r = Rule(match: "com.x.app", appName: "X", slots: SlotActions(bySlot: [
        1: .keyCombo(KeyCombo(modifiers: [.command], key: "A")),
        2: .keyCombo(KeyCombo(modifiers: [.command], key: "B")),
    ]))
    let config = makeConfig(rules: [r], def: .dictation)
    XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", slot: 1, config: config),
                   .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
    XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", slot: 2, config: config),
                   .keyCombo(KeyCombo(modifiers: [.command], key: "B")))
}

func testSlotWithNoActionFallsBackToGlobalDefault() {
    let r = Rule(match: "com.x.app", appName: "X",
                 slots: SlotActions(bySlot: [1: .keyCombo(KeyCombo(modifiers: [.command], key: "A"))]))
    let config = makeConfig(rules: [r], def: .dictation)
    // slot 2 has no per-app action -> global default applies.
    XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", slot: 2, config: config), .dictation)
}

func testWrapperUsesSlot1() {
    let r = Rule(match: "com.x.app", appName: "X",
                 slots: SlotActions(bySlot: [1: .keyCombo(KeyCombo(modifiers: [.command], key: "A"))]))
    let config = makeConfig(rules: [r])
    XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", config: config),
                   .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
}
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `swift test --filter RuleResolverTests`
Expected: FAIL to compile — `resolve(bundleID:slot:config:)` does not exist.

- [ ] **Step 3: Implement** — replace the entire contents of `Sources/FootswitchCore/RuleResolver.swift`:

```swift
import Foundation

public enum RuleResolver {
    /// Resolve what to do for `bundleID` when pedal `slot` (1-based) fires. An
    /// exact bundle-ID match (first wins) that has a per-slot action contributes
    /// it; otherwise the config's global DefaultAction applies. The default is
    /// global (not per-slot) by design.
    public static func resolve(bundleID: String?, slot: Int, config: Config) -> ResolvedAction {
        if let bundleID,
           let rule = config.rules.first(where: { $0.match == bundleID }),
           let action = rule.slots.action(forSlot: slot) {
            switch action {
            case .keyCombo(let combo): return .keyCombo(combo)
            case .dictation:           return .dictation
            }
        }
        switch config.defaultAction {
        case .dictation: return .dictation
        case .none:      return .none
        }
    }

    /// Back-compat wrapper: resolves for the primary pedal (slot 1).
    public static func resolve(bundleID: String?, config: Config) -> ResolvedAction {
        resolve(bundleID: bundleID, slot: 1, config: config)
    }
}
```

- [ ] **Step 4: Run to verify all resolver tests pass**

Run: `swift test --filter RuleResolverTests`
Expected: PASS (old + new).

- [ ] **Step 5: Build FootswitchCore green, then commit Tasks 3+4**

Run: `swift build --target FootswitchCore`
Expected: PASS (no more `rule.action` readers in core).

```bash
git add Sources/FootswitchCore/Models/Rule.swift Sources/FootswitchCore/RuleResolver.swift \
        Tests/FootswitchCoreTests/RuleCodingTests.swift Tests/FootswitchCoreTests/RuleResolverTests.swift
git commit -m "feat(core): per-slot Rule.slots + slot-aware RuleResolver (legacy action -> slot 1)"
```

---

## Task 5: Multi-pedal default trigger keys (FootswitchCore)

**Files:**
- Modify: `Sources/FootswitchCore/Models/Config.swift`
- Test: `Tests/FootswitchCoreTests/ConfigCodingTests.swift`

- [ ] **Step 1: Update the default-config assertions.** In `ConfigCodingTests.swift`, `testDefaultHasDictationDefaultAndNoRules` currently asserts USB == `[F13/slot1]` and `allTriggerKeys == [F13/slot1]`. Replace that test's trigger assertions with:

```swift
    func testDefaultHasDictationDefaultAndNoRules() {
        XCTAssertEqual(Config.default.defaultAction, .dictation)
        XCTAssertTrue(Config.default.rules.isEmpty)
        XCTAssertEqual(Config.default.triggers.usb, [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F14", slot: 2),
            TriggerKey(key: "F15", slot: 3),
        ])
        XCTAssertEqual(Config.default.triggers.bluetooth, [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(Config.default.triggers.primary(for: .usb), TriggerKey(key: "F13", slot: 1))
        XCTAssertEqual(Config.default.triggers.primary(for: .bluetooth), TriggerKey(key: "F13", slot: 1))
        // Union de-dupes F13 (shared) -> F13, F14, F15.
        XCTAssertEqual(Config.default.allTriggerKeys, [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F14", slot: 2),
            TriggerKey(key: "F15", slot: 3),
        ])
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ConfigCodingTests/testDefaultHasDictationDefaultAndNoRules`
Expected: FAIL — default USB is still single F13.

- [ ] **Step 3: Implement** — in `Sources/FootswitchCore/Models/Config.swift`, change the `static let default` USB list:

```swift
    public static let `default` = Config(
        triggers: Triggers(
            usb: [
                TriggerKey(key: "F13", slot: 1),
                TriggerKey(key: "F14", slot: 2),
                TriggerKey(key: "F15", slot: 3),
            ],
            bluetooth: [TriggerKey(key: "F13", slot: 1)]),
        dictationShortcut: KeyCombo(modifiers: [.control, .option, .command], key: "D"),
        debounceMs: 250,
        defaultAction: .dictation,
        rules: []
    )
```

- [ ] **Step 4: Run the full Config + round-trip tests**

Run: `swift test --filter ConfigCodingTests`
Expected: PASS. (`testRoundTrips` round-trips `Config.default`; the new defaults round-trip fine through the existing `triggers` encode/decode.)

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/Models/Config.swift Tests/FootswitchCoreTests/ConfigCodingTests.swift
git commit -m "feat(core): default USB triggers F13/F14/F15 for slots 1-3"
```

---

## Task 6: `PedalProgrammer` protocol — `slot:` parameters

Add a `slot:` parameter (default `1`) to the protocol so USB can target any slot
while BLE and existing callers keep working with the default.

**Files:**
- Modify: `Sources/Footswitch/PedalProgrammer.swift`

- [ ] **Step 1: Implement** — replace the protocol + extension in `Sources/Footswitch/PedalProgrammer.swift` (keep the `PedalVerification` enum above it unchanged):

```swift
protocol PedalProgrammer {
    /// Human-readable model name of the device this programmer targets.
    var deviceName: String { get }
    /// Reads slot `slot`'s (1-based) stored config; nil if it could not be read.
    func readStoredConfig(slot: Int) -> FootswitchProgram.StoredConfig?
    /// Programs slot `slot` (1-based) to emit `combo` on press. Throws on failure.
    func program(combo: KeyCombo, slot: Int) throws
    /// A human-readable, read-only info report (USB identity / model / stored key).
    func info() -> String
}

extension PedalProgrammer {
    /// Default verification for `slot` (1-based): read its stored config, compare.
    func verify(expected: KeyCombo, slot: Int) -> PedalVerification {
        guard let stored = readStoredConfig(slot: slot) else { return .unreadable }
        switch stored {
        case .key(let combo): return combo == expected ? .verified : .mismatch
        case .unconfigured, .other: return .mismatch
        }
    }

    // Slot-1 conveniences so single-pedal callsites stay unchanged.
    func readStoredConfig() -> FootswitchProgram.StoredConfig? { readStoredConfig(slot: 1) }
    func program(combo: KeyCombo) throws { try program(combo: combo, slot: 1) }
    func verify(expected: KeyCombo) -> PedalVerification { verify(expected: expected, slot: 1) }
}
```

- [ ] **Step 2: Build** — this will fail until the two conformers (USB in `FootswitchHIDController`, BLE in `BLEPedalProgrammer`) adopt the new signatures.

Run: `swift build`
Expected: FAIL — `USBPedalProgrammer`/`BLEPedalProgrammer` don't satisfy the protocol yet. Fixed in Tasks 7–8; commit together at the end of Task 8.

---

## Task 7: USB programmer — thread `slot:` through read/program (Footswitch)

**Files:**
- Modify: `Sources/Footswitch/FootswitchHIDController.swift`

- [ ] **Step 1: Update `USBPedalProgrammer` conformance.** In `FootswitchHIDController.swift`, replace the `USBPedalProgrammer` methods that read/program:

```swift
        func readStoredConfig(slot: Int) -> FootswitchProgram.StoredConfig? {
            for dev in interfaces {
                if let stored = FootswitchHIDController.readStoredConfig(dev, pedalIndex: slot - 1) {
                    return stored
                }
            }
            return nil
        }

        func program(combo: KeyCombo, slot: Int) throws {
            try FootswitchHIDController.programUSB(interfaces: interfaces, combo: combo, slot: slot)
        }
```

- [ ] **Step 2: Thread `slot:` into `programUSB`.** Replace the `programUSB` signature + the two `pedalIndex: 0` usages inside it:

```swift
    static func programUSB(interfaces: [IOHIDDevice], combo: KeyCombo, slot: Int = 1) throws {
        guard !interfaces.isEmpty else { throw ProgramError.noDevice }
        guard let reports = FootswitchProgram.keyReports(pedalIndex: slot - 1, combo: combo) else {
            throw ProgramError.unsupportedKey
        }
        var lastWrite: IOReturn = kIOReturnSuccess
        for dev in interfaces {
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
            if case .key(let stored)? = interfaces.lazy
                .compactMap({ readStoredConfig($0, pedalIndex: slot - 1) }).first, stored == combo {
                return
            }
        }
        if lastWrite == kIOReturnSuccess { return }
        throw ProgramError.writeFailed(lastWrite)
    }
```

- [ ] **Step 3: Add slot-aware public entry points + `detectedSlotCount()`.** Replace `verifyConfiguration(expected:)` and `program(combo:)`, and add the count probe. The static `usbeInfo`/`deviceInfo` keep reading slot 1 (`pedalIndex: 0`) — info display is primary-pedal only, unchanged:

```swift
    /// Reads slot `slot` (1-based) and compares it to `expected`.
    static func verifyConfiguration(expected: KeyCombo, slot: Int = 1) -> PedalVerification {
        guard let p = programmer() else { return .noDevice }
        return p.verify(expected: expected, slot: slot)
    }

    /// Programs slot `slot` (1-based) of the connected device to emit `combo`.
    static func program(combo: KeyCombo, slot: Int = 1) throws {
        guard let p = programmer() else { throw ProgramError.noDevice }
        try p.program(combo: combo, slot: slot)
    }

    /// Probes how many pedals the connected USB device can report a config for.
    /// A slot is "present" if its query returns a parseable StoredConfig. Count =
    /// highest present slot, clamped to 1...Slot.maxCount. BLE / no device -> 1.
    /// EXPENSIVE: each slot read spins the run loop up to ~500ms (~1.5s for three).
    /// MUST be called off the main thread.
    static func detectedSlotCount() -> Int {
        guard let first = orderedMatches().first, first.device.program == .footswitch else {
            return 1
        }
        let interfaces = orderedMatches()
            .filter { $0.device.program == .footswitch }.map { $0.hidDevice }
        var highest = 1
        for slot in Slot.validRange {
            let present = interfaces.contains { dev in
                readStoredConfig(dev, pedalIndex: slot - 1) != nil
            }
            if present { highest = slot }
        }
        return min(max(highest, 1), Slot.maxCount)
    }
```

- [ ] **Step 4: Build (still red until BLE conforms)**

Run: `swift build`
Expected: FAIL only on `BLEPedalProgrammer` conformance. Proceed to Task 8.

---

## Task 8: BLE programmer conforms to new signatures (Footswitch)

BLE is single-pedal (fixed `pedalIndex = 1`); it ignores `slot:`.

**Files:**
- Modify: `Sources/Footswitch/BLEPedalProgrammer.swift`

- [ ] **Step 1: Implement** — change the two `PedalProgrammer` methods' signatures (keep bodies; they use the fixed `pedalIndex`):

```swift
    func readStoredConfig(slot: Int) -> FootswitchProgram.StoredConfig? {
        do {
            try ensureReady()
            return try queryReadBack()
        } catch { return nil }
    }

    func program(combo: KeyCombo, slot: Int) throws {
        guard let data = BLEProgramPayload.data(combo: combo) else { throw BLEError.writeFailed }
        try ensureReady()
        try writeValue(BLEProgramPayload.header(pedalIndex: pedalIndex))
        try writeValue(data)
        if case .key(let stored)? = try? queryReadBack(), stored == combo { return }
        if case .key(let stored)? = try? queryReadBack(), stored == combo { return }
        queue.sync { teardownLocked() }
        throw BLEError.writeFailed
    }
```

Also update `info()`'s internal `readStoredConfig()` call — it now resolves to the
slot-1 convenience automatically, so no change is needed there.

- [ ] **Step 2: Build the whole package green**

Run: `swift build`
Expected: PASS (SettingsView still reads `rule.action` — if it errors, that is Task 12; if so, temporarily it may already error. To keep this commit green, verify the error set: `rule.action` in SettingsView is fixed in Task 12. If `swift build` is red ONLY on `SettingsView.swift`, proceed to Task 12 before committing Tasks 6–8.)

To keep commits green, defer the Tasks 6–8 commit until SettingsView compiles. Proceed to Task 9 (PedalListener, independent), then Task 12 (SettingsView), then make one green commit. **However** PedalListener (Task 9) and AppDelegate (Task 10) don't touch `rule.action`. The remaining `rule.action` reader is SettingsView only.

- [ ] **Step 3: Decision — order to reach green.** Implement Tasks 9, 10, 11, 12 next; once SettingsView (Task 12) compiles, run `swift build && swift test` and commit the protocol/HID/BLE/listener/appdelegate/menubar/settings changes in logical commits per task where each leaves the tree green. Because Tasks 6–12 are interdependent through the protocol rename, the FIRST green point is after Task 12. Commit Tasks 6,7,8 together at that green point with:

```bash
git add Sources/Footswitch/PedalProgrammer.swift Sources/Footswitch/FootswitchHIDController.swift Sources/Footswitch/BLEPedalProgrammer.swift
git commit -m "feat(io): thread slot through USB programming + detectedSlotCount(); BLE conforms"
```

(Do NOT run this commit until `swift build && swift test` is green after Task 12.)

---

## Task 9: `PedalListener` keycode→slot map, `onFire(slot:)` (Footswitch)

**Files:**
- Modify: `Sources/Footswitch/PedalListener.swift`

- [ ] **Step 1: Implement** — replace the stored properties, `init`, and the fire line in `handle`:

Replace the three property declarations and `init`:

```swift
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let keyCodeToSlot: [UInt16: Int]
    private var debouncers: [UInt16: Debouncer]
    private let onFire: @Sendable (_ slot: Int) -> Void

    /// `triggerKeys` are the keys to catch (already clamped to detected slots by the
    /// caller). Each key's `slot` (1-based) tags its fires. Keys that don't resolve
    /// to a keycode are skipped (that slot simply won't fire). On a fully-empty/
    /// unresolved set, fall back to catching F13 as slot 1 (prior behavior).
    init(triggerKeys: [TriggerKey], debounceMs: Int, onFire: @escaping @Sendable (_ slot: Int) -> Void) {
        var map: [UInt16: Int] = [:]
        for tk in triggerKeys {
            guard let code = Keymap.keyCode(for: tk.key) else { continue }
            // First writer wins per keycode (de-dup): a duplicate key can't map to
            // two slots, so the lower slot (earlier in the list) keeps it.
            if map[code] == nil { map[code] = tk.slot }
        }
        if map.isEmpty { map[0x69] = 1 }   // F13 / slot 1 fallback
        self.keyCodeToSlot = map
        self.debouncers = Dictionary(uniqueKeysWithValues:
            map.keys.map { ($0, Debouncer(intervalMs: debounceMs)) })
        self.onFire = onFire
    }
```

In `handle(type:event:)`, replace the trigger-key block (from `guard triggerKeyCodes.contains` to the end) with:

```swift
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let slot = keyCodeToSlot[keyCode] else {
            return Unmanaged.passUnretained(event)   // pass through everything else
        }
        // A trigger key: debounce that specific key, fire (with its slot), swallow.
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var fired = false
        if var d = debouncers[keyCode] {
            fired = d.shouldFire(atMs: nowMs)
            debouncers[keyCode] = d           // write the mutated struct back
        } else {
            fired = true
        }
        if fired {
            let fire = onFire
            DispatchQueue.main.async { fire(slot) }
        }
        return nil   // swallow the trigger key so it never reaches the focused app
```

Update the class doc comment's first line to: `/// Installs a session event tap, swallows any of the trigger keys, debounces each independently, and invokes onFire(slot:) on the main thread.`

- [ ] **Step 2: Build** — still red on AppDelegate (`onFire` signature) + SettingsView until Tasks 10/12. That's expected.

Run: `swift build`
Expected: FAIL on `AppDelegate.swift` (onFire closure arity) and `SettingsView.swift`. Proceed to Task 10.

---

## Task 10: AppDelegate — slot-aware press, clamped listener, hot-plug (Footswitch)

**Files:**
- Modify: `Sources/Footswitch/AppDelegate.swift`

- [ ] **Step 1: Implement clamped, backgrounded listener build + slot-aware handlePress.** Replace the listener-construction block in `applicationDidFinishLaunching` (the `listener = PedalListener(...)` through `_ = listener.start()`):

```swift
        buildListener()

        // Live hot-plug: when USB HID devices change, re-detect the pedal count
        // and rebuild the listener so a freshly-plugged multi-pedal unit starts
        // catching its extra pedals without a relaunch.
        startDeviceChangeObserver()
    }

    /// (Re)builds the event-tap listener from the current config's trigger keys,
    /// clamped to the number of pedals the connected USB device actually reports,
    /// so single-pedal users never have F14/F15 swallowed. Detection is expensive
    /// (~1.5s worst case) so it runs off-main; the listener is (re)installed back
    /// on the main thread.
    private func buildListener() {
        let allKeys = config.allTriggerKeys
        let debounceMs = config.debounceMs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let slotCount = FootswitchHIDController.detectedSlotCount()
            let clamped = allKeys.filter { $0.slot <= slotCount }
            let keys = clamped.isEmpty ? Array(allKeys.prefix(1)) : clamped
            DispatchQueue.main.async {
                guard let self else { return }
                self.listener = PedalListener(
                    triggerKeys: keys,
                    debounceMs: debounceMs,
                    onFire: { [weak self] slot in
                        MainActor.assumeIsolated { self?.handlePress(slot: slot) }
                    })
                _ = self.listener.start()
            }
        }
    }

    private func handlePress(slot: Int) {
        let bundleID = FrontmostApp.bundleID()
        let action = RuleResolver.resolve(bundleID: bundleID, slot: slot, config: config)
        dispatcher.dispatch(action)
        menuBar.setLastFire(app: FrontmostApp.name(), slot: slot, action: action)
    }
```

- [ ] **Step 2: Add the IOKit device-change observer.** Add these properties to the class (near the other `private var`s) and methods. This uses `IOHIDManager`'s match/remove callbacks to fire `buildListener()` (debounced) on hardware changes:

Add properties:

```swift
    private var hidMonitorManager: IOHIDManager?
    private var rebuildWorkItem: DispatchWorkItem?
```

Add `import IOKit.hid` at the top of the file (alongside `import AppKit`).

Add methods:

```swift
    /// Observes USB HID attach/detach and rebuilds the listener (debounced 600ms
    /// so a burst of interface (un)registrations from one physical (un)plug only
    /// triggers one re-detect).
    private func startDeviceChangeObserver() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.scheduleListenerRebuild() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, cb, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, cb, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidMonitorManager = manager
    }

    private func scheduleListenerRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.buildListener() }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
```

- [ ] **Step 3: Rebuild the listener on config save too.** In `reload(_:)`, after updating `config` and the dispatcher, add a listener rebuild (trigger-key/debounce changes now take effect immediately, superseding the old "next launch" comment). Replace the trailing comment line with:

```swift
        // Trigger keys / debounce changes take effect immediately by rebuilding
        // the listener (clamped to the detected slot count).
        buildListener()
```

- [ ] **Step 4: Build** — still red on SettingsView (`rule.action`) and MenuBar (`setLastFire` arity) until Tasks 11/12.

Run: `swift build`
Expected: FAIL on `MenuBarController.swift` (`setLastFire` arity) and `SettingsView.swift`. Proceed to Task 11.

---

## Task 11: MenuBar shows which pedal fired (Footswitch)

**Files:**
- Modify: `Sources/Footswitch/MenuBarController.swift`
- Modify: `Sources/Footswitch/L10n.swift` (add `menuLastFireSlot`)

- [ ] **Step 1: Add the L10n accessor.** In `L10n.swift`, alongside `menuLastFire`, add:

```swift
    /// %1$@ = app name, %2$@ = pedal label (e.g. "Pedal 2"), %3$@ = action.
    static func menuLastFireSlot(app: String, slot: String, action: String) -> String {
        String(format: t("menu.lastFireSlot",
            "Menu line for the most recent press identifying the pedal. %1$@ app, %2$@ pedal, %3$@ action."),
            app, slot, action)
    }

    /// %@ = pedal number, e.g. "Pedal 2". Reused for menu + settings rows/columns.
    static func deviceSlotLabel(_ number: Int) -> String {
        String(format: t("device.slotLabel", "Label for one pedal slot. %@ is the pedal number."), "\(number)")
    }
```

- [ ] **Step 2: Update `setLastFire`.** In `MenuBarController.swift`, change the signature and body:

```swift
    func setLastFire(app: String?, slot: Int, action: ResolvedAction) {
        let appName = app ?? L10n.appUnknown
        lastFireText = L10n.menuLastFireSlot(
            app: appName, slot: L10n.deviceSlotLabel(slot), action: describe(action))
        rebuildMenu(trusted: PermissionsManager.isTrusted())
    }
```

- [ ] **Step 3: Build** — still red on SettingsView only.

Run: `swift build`
Expected: FAIL on `SettingsView.swift` (`rule.action`). Proceed to Task 12. (L10n keys are added to the en catalog + 30 locales in Task 13; until then `NSLocalizedString` falls back to the key, so the build is unaffected.)

---

## Task 12: Settings UI — per-slot rows, columns, clear affordance (Footswitch)

This is the largest task. It (a) backgrounds slot-count detection and caches it,
(b) renders one config row per detected slot with a per-row Program button,
(c) rebuilds the rules table's shortcut columns to one-per-slot, (d) adds
`updateShortcut(row:slot:combo:)` + `clearShortcut(row:slot:)`, and (e) adds
`onClear` + Delete-to-clear to `ShortcutCaptureView`.

**Files:**
- Modify: `Sources/Footswitch/SettingsView.swift`
- Modify: `Sources/Footswitch/L10n.swift` (add `deviceDetectedSlots`, `settingsColPedalShortcut`)

- [ ] **Step 1: Add L10n accessors.** In `L10n.swift` add:

```swift
    /// %1$@ = device name, %2$@ = pedal count. Shown when >1 pedal detected.
    static func deviceDetectedSlots(name: String, count: Int) -> String {
        String(format: t("device.detectedSlots",
            "Device status with pedal count. %1$@ name, %2$@ count."), name, "\(count)")
    }

    /// %@ = pedal number. Rules-table shortcut column header for one pedal.
    static func settingsColPedalShortcut(_ number: Int) -> String {
        String(format: t("settings.col.pedalShortcut",
            "Rules column header for one pedal's shortcut. %@ is the pedal number."), "\(number)")
    }
```

- [ ] **Step 2: Add a cached slot count + background detection.** In `SettingsViewController`, add a stored property and a helper, and call it. Add near the other `private var`s:

```swift
    /// Cached detected pedal count for this Settings window's lifetime, so column
    /// rebuilds / reloadData don't re-probe. Starts at 1 (safe single-slot layout).
    private var detectedSlotCount = 1
```

In `viewDidLoad()`, after `tableView.reloadData()`, add:

```swift
        detectSlotsAndRebuild()
```

Add the method:

```swift
    /// Probes the pedal count off-main (expensive), then on main updates the cache,
    /// rebuilds the shortcut columns, the per-slot config rows, and reloads.
    private func detectSlotsAndRebuild() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let count = FootswitchHIDController.detectedSlotCount()
            DispatchQueue.main.async {
                guard let self, count != self.detectedSlotCount else {
                    self?.refreshDeviceStatus()
                    return
                }
                self.detectedSlotCount = count
                self.rebuildShortcutColumns()
                self.tableView.reloadData()
                self.refreshDeviceStatus()
            }
        }
    }
```

- [ ] **Step 3: Make `configureTable` build the initial single shortcut column, and add a rebuild.** Replace the `keyCol` block in `configureTable()` with a call:

```swift
        rebuildShortcutColumns()
```

Add the method (single column titled "Shortcut" when count==1, else "Pedal N"
columns with identifiers `shortcut.<slot>`):

```swift
    /// Rebuilds the shortcut column(s): one per detected slot. Identifier encodes
    /// the 1-based slot as "shortcut.<slot>". When count==1 the single column keeps
    /// the legacy "Shortcut" title for an unchanged single-pedal look.
    private func rebuildShortcutColumns() {
        for col in tableView.tableColumns where col.identifier.rawValue.hasPrefix("shortcut") {
            tableView.removeTableColumn(col)
        }
        if detectedSlotCount <= 1 {
            let col = NSTableColumn(identifier: .init("shortcut.1"))
            col.title = L10n.settingsColShortcut
            col.width = 180
            tableView.addTableColumn(col)
        } else {
            for slot in 1...detectedSlotCount {
                let col = NSTableColumn(identifier: .init("shortcut.\(slot)"))
                col.title = L10n.settingsColPedalShortcut(slot)
                col.width = 140
                tableView.addTableColumn(col)
            }
        }
    }
```

- [ ] **Step 4: Per-slot config rows in `refreshDeviceStatus`.** This is a structural change to the device section. Replace the body of `refreshDeviceStatus()` so that, when a `.footswitch` (USB) device is detected and `detectedSlotCount > 1`, it renders one config row per slot; otherwise it renders the single existing row. To keep the diff bounded and reuse the existing per-row verify/program logic, extract the existing single-row logic into a helper parameterized by slot.

Replace `refreshDeviceStatus()` and add `verifyAndRenderRow`:

```swift
    private func refreshDeviceStatus() {
        guard let detected = FootswitchHIDController.detect() else {
            deviceStatusLabel.attributedStringValue = statusLine("⊘", L10n.deviceNone, .secondaryLabelColor)
            infoButton.isHidden = true
            configRow.isHidden = true
            clearExtraSlotRows()
            return
        }
        let isUSB = detected.device.program == .footswitch
        let multi = isUSB && detectedSlotCount > 1
        deviceStatusLabel.attributedStringValue = statusLine(
            "✓",
            multi ? L10n.deviceDetectedSlots(name: detected.device.name, count: detectedSlotCount)
                  : L10n.deviceDetected(name: detected.device.name),
            .systemGreen)
        infoButton.isHidden = false
        configRow.isHidden = false

        let transport: Transport = detected.device.program == .footswitchBLE ? .bluetooth : .usb
        if multi {
            // The first config row (configRow) handles slot 1; extra rows handle 2..N.
            verifyAndRenderRow(slot: 1, transport: transport,
                               label: configStatusLabel, button: programButton)
            renderExtraSlotRows(transport: transport)
        } else {
            clearExtraSlotRows()
            verifyAndRenderRow(slot: 1, transport: transport,
                               label: configStatusLabel, button: programButton)
        }
    }

    /// Verifies one slot off-main and renders status + program button for its row.
    private func verifyAndRenderRow(slot: Int, transport: Transport,
                                    label: NSTextField, button: NSButton) {
        let expected = KeyCombo(modifiers: [], key: keyForSlot(slot, transport: transport))
        label.attributedStringValue = statusLine("…", "", .secondaryLabelColor)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FootswitchHIDController.verifyConfiguration(expected: expected, slot: slot)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .verified:
                    if transport == .bluetooth {
                        label.attributedStringValue =
                            self.statusLine("⚠", L10n.deviceConfigStoredBluetooth, .systemYellow)
                    } else {
                        label.attributedStringValue =
                            self.statusLine("✓", L10n.deviceConfigVerified, .systemGreen)
                    }
                    button.isHidden = true
                case .mismatch:
                    label.attributedStringValue =
                        self.statusLine("⚠", L10n.deviceConfigMismatch, .systemYellow)
                    button.isHidden = false
                    button.isEnabled = true
                case .unreadable:
                    label.attributedStringValue =
                        self.statusLine("✗", L10n.deviceConfigUnreadable, .systemRed)
                    button.isHidden = true
                case .noDevice:
                    button.isHidden = true
                }
            }
        }
    }

    /// The configured trigger key for a slot on a transport (fallback F13).
    private func keyForSlot(_ slot: Int, transport: Transport) -> String {
        baseConfig.triggers.keys(for: transport).first { $0.slot == slot }?.key
            ?? baseConfig.triggers.primary(for: transport).key
    }
```

- [ ] **Step 5: Render/clear the extra (slot 2..N) config rows.** Add storage + builders. Add property:

```swift
    /// Dynamically-created config rows for slots 2..N (slot 1 reuses `configRow`).
    private var extraSlotRows: [NSStackView] = []
```

Add methods:

```swift
    private func renderExtraSlotRows(transport: Transport) {
        clearExtraSlotRows()
        guard detectedSlotCount > 1 else { return }
        for slot in 2...detectedSlotCount {
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 12)
            let button = NSButton(title: L10n.settingsProgramButton,
                                  target: self, action: #selector(programSlotButton(_:)))
            button.bezelStyle = .rounded
            button.tag = slot   // carry the slot to the action
            let prefix = NSTextField(labelWithString: L10n.deviceSlotLabel(slot) + ":")
            prefix.font = .systemFont(ofSize: 12)
            let row = NSStackView(views: [prefix, status, button])
            row.orientation = .horizontal
            row.spacing = 8
            deviceSection.addArrangedSubview(row)
            extraSlotRows.append(row)
            verifyAndRenderRow(slot: slot, transport: transport, label: status, button: button)
        }
    }

    private func clearExtraSlotRows() {
        for row in extraSlotRows {
            deviceSection.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        extraSlotRows.removeAll()
    }
```

- [ ] **Step 6: Per-slot Program buttons.** Replace `programPedal()` with slot-aware variants. The existing slot-1 `programButton` keeps `#selector(programPedal)`; route it through the shared implementation with slot 1:

```swift
    @objc private func programPedal() { programSlot(1, button: programButton) }

    @objc private func programSlotButton(_ sender: NSButton) {
        programSlot(sender.tag, button: sender)
    }

    private func programSlot(_ slot: Int, button: NSButton) {
        guard let transport = currentTransport() else { return }
        let key = keyForSlot(slot, transport: transport)
        let combo = KeyCombo(modifiers: [], key: key)
        button.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                try FootswitchHIDController.program(combo: combo, slot: slot)
                message = transport == .bluetooth
                    ? L10n.alertProgrammedBluetooth(key: key)
                    : L10n.alertProgrammed(key: key)
            } catch {
                message = L10n.alertProgramFailed(error: "\(error)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                button.isEnabled = true
                self.presentInfo(message)
                self.refreshDeviceStatus()
            }
        }
    }
```

- [ ] **Step 7: Slot-aware rule add + table cells.** In `addRule()`, the suggested-shortcut pre-fill must seed slot 1 only. Replace the `action`/`rules.append` lines:

```swift
        let suggested = KnownAppDefaults.suggestedShortcut(forBundleID: bundleID)
        let slots = SlotActions(bySlot: suggested.map { [1: Action.keyCombo($0)] } ?? [:])
        rules.append(Rule(match: bundleID, appName: appName, slots: slots))
```

In `tableView(_:viewFor:row:)`, replace the `case "shortcut":` branch with a
slot-parsing branch (note: the switch is on `tableColumn?.identifier.rawValue`):

```swift
        case let id? where id.hasPrefix("shortcut."):
            let slot = Int(id.dropFirst("shortcut.".count)) ?? 1
            let capture = ShortcutCaptureView()
            if case .keyCombo(let combo)? = rule.slots.action(forSlot: slot), !combo.key.isEmpty {
                capture.combo = combo
            }
            capture.onCapture = { [weak self] combo in
                self?.updateShortcut(row: row, slot: slot, combo: combo)
            }
            capture.onClear = { [weak self] in
                self?.clearShortcut(row: row, slot: slot)
            }
            return capture
```

Remove the now-dead `case "shortcut":` branch (replaced above).

- [ ] **Step 8: Slot-aware mutators.** Replace `updateShortcut(row:combo:)` with:

```swift
    fileprivate func updateShortcut(row: Int, slot: Int, combo: KeyCombo) {
        guard rules.indices.contains(row) else { return }
        rules[row].slots.bySlot[slot] = .keyCombo(combo)
        save()
    }

    fileprivate func clearShortcut(row: Int, slot: Int) {
        guard rules.indices.contains(row) else { return }
        rules[row].slots.bySlot[slot] = nil
        save()
    }
```

- [ ] **Step 9: Add `onClear` + Delete-to-clear to `ShortcutCaptureView`.** Add the callback property next to `onCapture`:

```swift
    var onClear: (() -> Void)?
```

In `handle(_:)`, after the Escape (`0x35`) block, add a Delete/Backspace clear:

```swift
        // Delete/Backspace clears the shortcut (standard macOS convention).
        if event.type == .keyDown, event.keyCode == 0x33 { // Delete
            combo = nil
            stopRecording()
            render()
            onClear?()
            return nil
        }
```

(Place this AFTER the `if event.type == .flagsChanged` early-return and the Escape
check, but BEFORE the `let mods = ...` line, so Delete is intercepted while recording.)

- [ ] **Step 10: Build + full test suite green**

Run: `swift build && swift test`
Expected: PASS (whole package compiles; all core tests green). If green, NOW make the deferred commits.

- [ ] **Step 11: Commit the IO + UI layer (Tasks 6–12)**

```bash
git add Sources/Footswitch/PedalProgrammer.swift Sources/Footswitch/FootswitchHIDController.swift \
        Sources/Footswitch/BLEPedalProgrammer.swift Sources/Footswitch/PedalListener.swift \
        Sources/Footswitch/AppDelegate.swift Sources/Footswitch/MenuBarController.swift \
        Sources/Footswitch/SettingsView.swift Sources/Footswitch/L10n.swift
git commit -m "feat(app): slot-aware listener, hot-plug re-detect, per-slot Settings rows/columns + clear"
```

---

## Task 13: Localization — four new keys across 30 locales

New keys (English authoritative): `menu.lastFireSlot`, `device.slotLabel`,
`device.detectedSlots`, `settings.col.pedalShortcut`.

**Files:**
- Modify: `Sources/Footswitch/Resources/Localizations/*/Localizable.strings` (all 30)

- [ ] **Step 1: Inspect the existing en file format + locale list**

Run: `cat "Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings" | head -20`
Run: `ls Sources/Footswitch/Resources/Localizations/`
Expected: a `"key" = "value";` format with `/* comment */` headers; 30 `.lproj` dirs.

- [ ] **Step 2: Add the four keys to the `en` file** with the authoritative English values:

```
/* Menu line for the most recent press identifying the pedal. %1$@ app, %2$@ pedal, %3$@ action. */
"menu.lastFireSlot" = "%1$@ — %2$@ → %3$@";
/* Label for one pedal slot. %@ is the pedal number. */
"device.slotLabel" = "Pedal %@";
/* Device status with pedal count. %1$@ name, %2$@ count. */
"device.detectedSlots" = "%1$@ (%2$@ pedals)";
/* Rules column header for one pedal's shortcut. %@ is the pedal number. */
"settings.col.pedalShortcut" = "Pedal %@";
```

- [ ] **Step 3: Add the same four keys to all 29 other locales.** For non-English locales, provide a reasonable translation if known; otherwise use the English value as a placeholder (parity test only checks key presence + placeholder arity, not translation quality). The four entries must appear in EVERY `.lproj/Localizable.strings`. The placeholder tokens (`%1$@`, `%2$@`, `%3$@`, `%@`) MUST match the English arity exactly in each locale.

A safe approach to guarantee parity: for each non-en locale, append the same four lines as English (translate later). Use an explicit per-file edit (do not script with `sed` without a backup per the project's tooling rules; prefer the editor). If scripting, back up each file first, append, verify, then delete backups before commit.

- [ ] **Step 4: Run the parity test**

Run: `swift test --filter LocalizationParityTests`
Expected: PASS — all 30 locales carry the four keys with matching placeholder arity.

- [ ] **Step 5: Full build + test**

Run: `swift build && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Footswitch/Resources/Localizations
git commit -m "i18n: add multi-pedal strings (menu/slot/detected/column) across 30 locales"
```

---

## Task 14: Docs — remove the multi-pedal limitation

**Files:**
- Modify: `README.md`
- Modify: `docs/supported-devices.md`

- [ ] **Step 1: Find the limitation text**

Run: `rg -n -i "multi-pedal|multipedal|does not.*support" README.md docs/supported-devices.md`
Expected: the README line stating multi-pedal devices are unsupported.

- [ ] **Step 2: Update README.** Replace the "does not currently support multi-pedal devices" limitation with a short multi-pedal section, e.g.:

```markdown
### Multi-pedal switches

Multi-pedal USB foot switches (e.g. 3-pedal PCsensor page-turners) are supported.
The app detects how many pedals your device has and lets you program each pedal a
distinct key (default F13 / F14 / F15) and assign per-app actions per pedal in
Settings. Single-pedal devices are unchanged. Plugging in a multi-pedal unit while
the app is running is detected live (no relaunch needed).
```

- [ ] **Step 3: Update `docs/supported-devices.md`** with a note that pedal count is detected at runtime (not table-driven) and that multi-pedal USB `.footswitch` units program each pedal independently.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/supported-devices.md
git commit -m "docs: document multi-pedal support; remove the unsupported limitation"
```

---

## Task 15: SwiftLint clean + final verification

**Files:** none (verification only)

- [ ] **Step 1: Run SwiftLint** (default ruleset; no committed config)

Run: `swiftlint --strict` (or `swiftlint` if `--strict` is too aggressive for the existing baseline)
Expected: no NEW violations from the changed files. Fix any introduced violations (line length, force-unwrap, etc.). Note the `SlotKey(intValue:)!` force-unwraps in `SlotActions` are safe (the initializer never returns nil for a valid Int) — if SwiftLint flags them, add a scoped `// swiftlint:disable:next force_unwrapping` matching the codebase's existing inline-disable style.

- [ ] **Step 2: Full build + test once more**

Run: `swift build && swift test`
Expected: PASS.

- [ ] **Step 3: Package smoke check (optional but recommended)**

Run: `scripts/package-app.sh` (if present) to confirm the `.app` still assembles with the new strings.
Expected: builds an `.app` without error.

- [ ] **Step 4: Final commit (only if Step 1 required fixes)**

```bash
git add -A
git commit -m "chore: swiftlint clean for multi-pedal changes"
```

---

## Manual / on-device verification (multi-pedal unit required)

These cannot be automated; run them after the plan completes with a real device:

- [ ] Settings detects the correct pedal count; one config row + one shortcut column per pedal; a single-pedal unit shows the one-row/one-column layout.
- [ ] On a **single-pedal** unit with the new default config, confirm F14 and F15 are NOT swallowed — they reach a focused text field as ordinary keypresses (proves the listener is clamped to detected count; no pass-through regression).
- [ ] Program each slot with a distinct key (slot 1 → F13, slot 2 → F14, slot 3 → F15); read-back verifies each independently. Program a slot to a different value first (e.g. F16), read it back, then to the target — proves the write mutates that specific slot (byte 3 = slot), not slot 1.
- [ ] Add a per-app rule with distinct slot-1/slot-2 actions; press each pedal in that app → the correct action fires; press in an unmapped app → the global default runs for every pedal. The menu's "last fire" line names the pedal that fired.
- [ ] Clear a slot's shortcut (Delete while recording) → the entry is removed and that slot falls back to the global default.
- [ ] Hot-plug: launch the app with a single-pedal unit (or none), then plug in a 3-pedal unit → within ~1s the runtime starts catching pedals 2/3 without relaunch; unplug → it stops catching them.
- [ ] No trigger key leaks as a visible character in any app.

---

## Self-Review notes (author)

- **Spec coverage:** slot model (Task 1), per-slot actions (Tasks 2–3), slot resolution (Task 4), defaults (Task 5), slot-threaded programming + `detectedSlotCount` (Tasks 6–8), multi-key→slot listener (Task 9), clamped/hot-plug AppDelegate (Task 10), menu slot label (Task 11), per-slot Settings rows/columns + clear (Task 12), 30-locale strings (Task 13), docs (Task 14), lint/verify (Task 15). The spec's `triggerKeys:[String]`/0-based-slot proposal is intentionally NOT implemented — superseded by the merged `Triggers`/`TriggerKey.slot` model per the recorded product decision.
- **Divergence from spec, decided with the user:** (1) build on merged model rather than the spec's schema; (2) live hot-plug re-detection (spec left this as an open question / out-of-scope). Both confirmed.
- **Type consistency:** slots are 1-based throughout (`TriggerKey.slot`, `SlotActions.bySlot` keys, `Slot.validRange = 1...3`, resolver `slot:`, listener slot tag, column id `shortcut.<slot>`), converted to 0-based `pedalIndex` only via `slot - 1` at the HID boundary. `program(combo:slot:)`, `readStoredConfig(slot:)`, `verify(expected:slot:)`, `verifyConfiguration(expected:slot:)`, `detectedSlotCount()`, `updateShortcut(row:slot:combo:)`, `clearShortcut(row:slot:)`, `onClear` are used consistently across tasks.
- **Commit-green ordering:** the `Rule.action → slots` rename forces a temporary red window across Tasks 6–12 (protocol rename ripples through HID/BLE/Settings). The plan defers those commits to the first green point (end of Task 12) and is explicit about it. Core commits (Tasks 1–5) each stay green independently.
