# Modifier Trigger Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize, capture, and program modifier+key trigger combos end-to-end, with exact modifier matching in the pedal listener.

**Architecture:** `TriggerKey` gains a tolerant `modifiers` field and a `combo` accessor; a pure `TriggerMatcher` does exact `(keycode + modifier-bits)` lookup for the listener; the #6 capture/reconcile path widens from a bare key string to a `KeyCombo`; resolution/adopt carry combos. The device program/verify paths already round-trip modifiers via `KeyCombo`, so they need no change beyond receiving non-empty combos.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, CoreGraphics event taps. Spec: `docs/superpowers/specs/2026-06-24-modifier-trigger-detection-design.md`.

## Global Constraints

- `swift build`/`swift test` compile the WHOLE package (core + app target). Each task's FINAL commit must build WARNING-FREE and pass all tests. Tasks 1 and 2 are additive and stay green on their own; Task 3 is a coupled breaking change across core + app and is green only at its end.
- **Exact** modifier matching: an event fires a trigger only when its modifiers, masked to the four device modifiers, EQUAL the trigger's modifier set.
- Device modifier mask = `0x20000 | 0x40000 | 0x80000 | 0x100000` (shift, control, option, command — the same bit values `Keymap.flagBits(for:)` produces).
- Canonical modifier order is **control, option, shift, command** (matches `KeyComboFormatter` and `DeviceModifier.modifiers(fromBits:)`), so `KeyCombo` array-equality in `verify` holds across config / device read-back / event flags.
- `TriggerKey.modifiers` encodes only when non-empty so existing `devices[].triggers` stay byte-stable.
- No new localized strings expected; `LocalizationParityTests` must stay green.
- Build/test: `swift build`, `swift test`. No SwiftLint in repo.

---

### Task 1: Core — modifier-aware data layer (`TriggerKey`, `Keymap`, resolution/adopt combos)

All additive: existing String-based helpers stay until Task 3, so the package stays green.

**Files:**
- Modify: `Sources/FootswitchCore/Models/TriggerKey.swift`
- Modify: `Sources/FootswitchCore/Keymap.swift`
- Modify: `Sources/FootswitchCore/Models/Config.swift` (append to the `extension Config` and update `listenerKeys`)
- Modify: `Sources/FootswitchCore/Models/Device.swift` (add `adopting(combo:slot:)`)
- Test: `Tests/FootswitchCoreTests/TriggerKeyModifierTests.swift`

**Interfaces:**
- Consumes: `Modifier`, `KeyCombo`, `Device`, `SupportedDevice`, `Config.defaultTriggerKeys` (existing).
- Produces:
  - `TriggerKey.modifiers: [Modifier]`, `TriggerKey.combo: KeyCombo`, `init(key:slot:modifiers:)` (modifiers defaulted)
  - `Keymap.deviceModifierMask: UInt64`, `Keymap.modifiers(forFlagBits: UInt64) -> [Modifier]`
  - `Config.triggerCombo(in: [Device], forVendorID: Int, productID: Int, slot: Int) -> KeyCombo`
  - `Config.adoptingTriggerCombo(in: [Device], combo: KeyCombo, slot: Int, for: SupportedDevice) -> [Device]`
  - `Device.adopting(combo: KeyCombo, slot: Int) -> Device`
  - `Config.listenerKeys` deduped by `(key, modifiers)` rather than key name

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/FootswitchCoreTests/TriggerKeyModifierTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerKeyModifierTests: XCTestCase {
    func testBareFormDecodesToNoModifiers() throws {
        let json = #"{"key":"F13","slot":1}"#
        let tk = try JSONDecoder().decode(TriggerKey.self, from: Data(json.utf8))
        XCTAssertEqual(tk.modifiers, [])
    }

    func testModifiersRoundTrip() throws {
        let tk = TriggerKey(key: "F13", slot: 1, modifiers: [.control, .shift])
        let decoded = try JSONDecoder().decode(TriggerKey.self, from: JSONEncoder().encode(tk))
        XCTAssertEqual(decoded, tk)
    }

    func testEncodeOmitsEmptyModifiers() throws {
        let tk = TriggerKey(key: "F13", slot: 1)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tk)) as? [String: Any]
        XCTAssertNil(obj?["modifiers"])
    }

    func testComboAccessor() {
        XCTAssertEqual(TriggerKey(key: "F13", slot: 1, modifiers: [.control]).combo,
                       KeyCombo(modifiers: [.control], key: "F13"))
    }

    func testModifiersForFlagBitsCanonicalOrder() {
        // control=0x40000, option=0x80000, shift=0x20000, command=0x100000
        let bits: UInt64 = 0x40000 | 0x20000   // control + shift
        XCTAssertEqual(Keymap.modifiers(forFlagBits: bits), [.control, .shift])
        XCTAssertEqual(Keymap.modifiers(forFlagBits: 0), [])
    }

    func testTriggerComboResolution() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1, modifiers: [.control])])]
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x245A, productID: 0x8276, slot: 1),
                       KeyCombo(modifiers: [.control], key: "F16"))
        // Unknown device → code default (bare F14 for slot 2).
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x1, productID: 0x2, slot: 2),
                       KeyCombo(modifiers: [], key: "F14"))
    }

    func testAdoptComboStoresModifiers() {
        let dev = SupportedDevice(vendorID: 0x245A, productID: 0x8276, program: .footswitchBLE, name: "FS17Pro")
        let out = Config.adoptingTriggerCombo(in: [], combo: KeyCombo(modifiers: [.option], key: "F19"),
                                              slot: 1, for: dev)
        XCTAssertEqual(out.first?.triggers, [TriggerKey(key: "F19", slot: 1, modifiers: [.option])])
    }

    func testListenerKeysKeepsSameKeyDifferentModifiers() {
        let config = Config(
            devices: [Device(vendorId: "0x1", productId: "0x2", program: "footswitch", name: "A",
                             triggers: [TriggerKey(key: "F13", slot: 1),
                                        TriggerKey(key: "F13", slot: 2, modifiers: [.control])])],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        XCTAssertEqual(config.listenerKeys.count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TriggerKeyModifierTests`
Expected: FAIL — missing `modifiers`/`combo`/`Keymap.modifiers`/`triggerCombo`/`adoptingTriggerCombo`.

- [ ] **Step 3: Update `TriggerKey`**

Replace the whole `Sources/FootswitchCore/Models/TriggerKey.swift` with:

```swift
import Foundation

/// One trigger: a key (optionally with modifiers) the pedal emits, paired with the
/// logical button/pedal slot it occupies (1 = first button, ...). The listener fires
/// on the combo; the slot tells the programmer which pedal slot to write.
public struct TriggerKey: Codable, Equatable, Sendable {
    public var key: String
    public var slot: Int
    /// Modifiers the pedal emits with `key` (⌃⌥⇧⌘). Empty = a bare key. Stored in
    /// canonical order (control, option, shift, command); see `Keymap`.
    public var modifiers: [Modifier]

    public init(key: String, slot: Int, modifiers: [Modifier] = []) {
        self.key = key
        self.slot = slot
        self.modifiers = modifiers
    }

    /// This trigger as a `KeyCombo` (for matching, programming, and display).
    public var combo: KeyCombo { KeyCombo(modifiers: modifiers, key: key) }

    private enum CodingKeys: String, CodingKey { case key, slot, modifiers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        slot = try c.decode(Int.self, forKey: .slot)
        // Tolerant: the bare-key form (no `modifiers`) decodes to [].
        modifiers = (try? c.decode([Modifier].self, forKey: .modifiers)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(slot, forKey: .slot)
        // Omit when empty so existing bare-key configs stay byte-stable.
        if !modifiers.isEmpty { try c.encode(modifiers, forKey: .modifiers) }
    }
}
```

- [ ] **Step 4: Add the `Keymap` reverse helper + mask**

Append inside `enum Keymap` in `Sources/FootswitchCore/Keymap.swift` (before its closing brace):

```swift
    /// The four modifier flag bits a foot switch can emit (⌃⌥⇧⌘). Mask a raw
    /// CGEventFlags value with this to drop Caps Lock / fn / numeric-pad bits that
    /// must not affect trigger matching.
    public static let deviceModifierMask: UInt64 = 0x20000 | 0x40000 | 0x80000 | 0x100000

    /// Reverse of `flagBits(for:)`: the `Modifier`s encoded in a CGEventFlags bit
    /// field, in canonical order (control, option, shift, command) so the result
    /// compares equal to config / device-read-back modifier arrays.
    public static func modifiers(forFlagBits bits: UInt64) -> [Modifier] {
        var mods: [Modifier] = []
        if bits & 0x40000  != 0 { mods.append(.control) }
        if bits & 0x80000  != 0 { mods.append(.option) }
        if bits & 0x20000  != 0 { mods.append(.shift) }
        if bits & 0x100000 != 0 { mods.append(.command) }
        return mods
    }
```

- [ ] **Step 5: Add `Device.adopting(combo:slot:)`**

In `Sources/FootswitchCore/Models/Device.swift`, add this method next to the existing `adopting(key:slot:)`:

```swift
    /// Returns a copy with `combo` (key + modifiers) set as the trigger for `slot`:
    /// replaces the slot's existing trigger or appends a new one. Used by the #6
    /// Test-button adopt path once it captures full combos (#10).
    public func adopting(combo: KeyCombo, slot: Int) -> Device {
        var copy = triggers
        let tk = TriggerKey(key: combo.key, slot: slot, modifiers: combo.modifiers)
        if let i = copy.firstIndex(where: { $0.slot == slot }) {
            copy[i] = tk
        } else {
            copy.append(tk)
        }
        var out = self
        out.triggers = copy
        return out
    }
```

- [ ] **Step 6: Add the Config combo resolution/adopt helpers + fix `listenerKeys`**

In `Sources/FootswitchCore/Models/Config.swift`, append to the `extension Config { ... }` block (alongside the existing `triggerKey(in:)`/`adoptingTriggerKey(in:)`):

```swift
    /// Resolves a connected device's slot trigger as a `KeyCombo` (key + modifiers):
    /// the matching entry's non-empty triggers, else `defaultTriggerKeys`.
    public static func triggerCombo(in devices: [Device], forVendorID vid: Int,
                                    productID pid: Int, slot: Int) -> KeyCombo {
        let entry = devices.first {
            $0.resolved().map { $0.vendorID == vid && $0.productID == pid } ?? false
        }
        let keys = entry.flatMap { $0.triggers.isEmpty ? nil : $0.triggers } ?? defaultTriggerKeys
        let tk = keys.first { $0.slot == slot } ?? keys.first ?? defaultTriggerKeys[0]
        return tk.combo
    }

    /// Returns `devices` with `combo` set for `slot` on the entry matching `supported`
    /// (by VID/PID): updates the existing entry via `Device.adopting(combo:slot:)`, or
    /// appends a new entry seeded from `supported`. The combo-carrying #6 adopt path (#10).
    public static func adoptingTriggerCombo(in devices: [Device], combo: KeyCombo, slot: Int,
                                            for supported: SupportedDevice) -> [Device] {
        var copy = devices
        if let i = copy.firstIndex(where: {
            $0.resolved().map { $0.vendorID == supported.vendorID
                              && $0.productID == supported.productID } ?? false
        }) {
            copy[i] = copy[i].adopting(combo: combo, slot: slot)
        } else {
            copy.append(Device(
                vendorId: String(format: "0x%04X", supported.vendorID),
                productId: String(format: "0x%04X", supported.productID),
                program: supported.program.rawValue, name: supported.name,
                triggers: [TriggerKey(key: combo.key, slot: slot, modifiers: combo.modifiers)]))
        }
        return copy
    }
```

Then replace the `listenerKeys` computed property (in the main `struct Config`) so it dedupes by combo (key + modifiers), not key name — otherwise `{F13}` would hide `{⌃F13}`:

```swift
    /// Every trigger key the listener should watch: the union across all device
    /// entries, deduped by combo (key + modifiers), or the code default if none.
    public var listenerKeys: [TriggerKey] {
        var seen = Set<String>()
        var result: [TriggerKey] = []
        for k in devices.flatMap(\.triggers) {
            let sig = k.key.uppercased() + "|" + k.modifiers.map(\.rawValue).sorted().joined(separator: ",")
            if seen.insert(sig).inserted { result.append(k) }
        }
        return result.isEmpty ? Self.defaultTriggerKeys : result
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --filter TriggerKeyModifierTests` then full `swift test`
Expected: PASS (8 new tests; full suite green — additive change). Build warning-free.

- [ ] **Step 8: Commit**

```bash
git add Sources/FootswitchCore/Models/TriggerKey.swift Sources/FootswitchCore/Keymap.swift Sources/FootswitchCore/Models/Config.swift Sources/FootswitchCore/Models/Device.swift Tests/FootswitchCoreTests/TriggerKeyModifierTests.swift
git commit -m "feat: modifier-aware TriggerKey + combo resolution/adopt helpers (#10)"
```

---

### Task 2: Core — `TriggerMatcher` pure match seam

**Files:**
- Create: `Sources/FootswitchCore/TriggerMatcher.swift`
- Test: `Tests/FootswitchCoreTests/TriggerMatcherTests.swift`

**Interfaces:**
- Consumes: `TriggerKey`, `Keymap.keyCode(for:)`, `Keymap.flagBits(for:)` (existing).
- Produces:
  - `struct TriggerMatcher.Key: Hashable { let keyCode: UInt16; let modBits: UInt64 }`
  - `TriggerMatcher(triggerKeys: [TriggerKey])`, `.keys: [Key]`, `.slot(forKeyCode: UInt16, modBits: UInt64) -> Int?`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/FootswitchCoreTests/TriggerMatcherTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerMatcherTests: XCTestCase {
    // F13 = 0x69; control flag = 0x40000.
    func testBareKeyMatchesOnlyWithoutModifiers() {
        let m = TriggerMatcher(triggerKeys: [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
        XCTAssertNil(m.slot(forKeyCode: 0x69, modBits: 0x40000))   // ⌃F13 ≠ {F13}
    }

    func testModifierKeyMatchesExactly() {
        let m = TriggerMatcher(triggerKeys: [TriggerKey(key: "F13", slot: 2, modifiers: [.control])])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0x40000), 2)
        XCTAssertNil(m.slot(forKeyCode: 0x69, modBits: 0))         // bare F13 ≠ {⌃F13}
    }

    func testSameKeyDifferentModifiersCoexist() {
        let m = TriggerMatcher(triggerKeys: [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F13", slot: 2, modifiers: [.control]),
        ])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0x40000), 2)
        XCTAssertEqual(m.keys.count, 2)
    }

    func testUnresolvedKeySkipped_andFallback() {
        // Only an unknown key name → table empty → fall back to bare F13 / slot 1.
        let m = TriggerMatcher(triggerKeys: [TriggerKey(key: "NOPE", slot: 1)])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
    }

    func testFirstWriterWinsPerCombo() {
        let m = TriggerMatcher(triggerKeys: [
            TriggerKey(key: "F13", slot: 1),
            TriggerKey(key: "F13", slot: 3),   // same combo → ignored
        ])
        XCTAssertEqual(m.slot(forKeyCode: 0x69, modBits: 0), 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TriggerMatcherTests`
Expected: FAIL — "cannot find 'TriggerMatcher'".

- [ ] **Step 3: Implement `TriggerMatcher`**

```swift
// Sources/FootswitchCore/TriggerMatcher.swift
import Foundation

/// Pure, IO-free trigger-match table for the pedal listener: maps a (virtual key
/// code + masked modifier bits) to a slot, with EXACT modifier matching. Built from
/// the config's trigger keys; the event-tap glue (`PedalListener`) feeds it the
/// keycode and the masked modifier bits (#10).
public struct TriggerMatcher: Equatable, Sendable {
    /// One resolved trigger: a virtual key code + the modifier flag bits that must be
    /// present EXACTLY for it to fire.
    public struct Key: Hashable, Sendable {
        public let keyCode: UInt16
        public let modBits: UInt64
        public init(keyCode: UInt16, modBits: UInt64) {
            self.keyCode = keyCode
            self.modBits = modBits
        }
    }

    private let table: [Key: Int]

    /// Builds the table from `triggerKeys`: each name → `Keymap.keyCode`, each
    /// modifier set → `Keymap.flagBits`; unresolved names are skipped. First-writer-
    /// wins per `(keyCode, modBits)`. Empty result falls back to bare F13 / slot 1.
    public init(triggerKeys: [TriggerKey]) {
        var map: [Key: Int] = [:]
        for tk in triggerKeys {
            guard let code = Keymap.keyCode(for: tk.key) else { continue }
            let key = Key(keyCode: code, modBits: Keymap.flagBits(for: tk.modifiers))
            if map[key] == nil { map[key] = tk.slot }
        }
        if map.isEmpty { map[Key(keyCode: 0x69, modBits: 0)] = 1 }   // F13 / slot 1
        self.table = map
    }

    /// All distinct match keys (for the listener's per-key debouncers).
    public var keys: [Key] { Array(table.keys) }

    /// The slot to fire for `(keyCode, modBits)`, or nil if it is not a trigger.
    /// `modBits` MUST already be masked to `Keymap.deviceModifierMask`.
    public func slot(forKeyCode keyCode: UInt16, modBits: UInt64) -> Int? {
        table[Key(keyCode: keyCode, modBits: modBits)]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TriggerMatcherTests`
Expected: PASS (5 tests). Full `swift test` green.

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/TriggerMatcher.swift Tests/FootswitchCoreTests/TriggerMatcherTests.swift
git commit -m "feat: pure TriggerMatcher seam for exact modifier matching (#10)"
```

---

### Task 3: Wire combos through capture, listener, and Settings (coupled breaking change)

This changes `CapturedKey`/`TriggerReconciler` payloads from key strings to `KeyCombo`, so the app target (`PedalListener`, `AppDelegate`, `SettingsView`) and the existing core tests must all update together. The package is green only at this task's end. Build/test once after all edits.

**Files:**
- Modify: `Sources/FootswitchCore/TriggerReconciler.swift`
- Modify: `Sources/FootswitchCore/Models/Config.swift` (remove the now-unused String helpers)
- Modify: `Sources/FootswitchCore/Models/Device.swift` (remove now-unused `adopting(key:slot:)`)
- Modify: `Sources/Footswitch/PedalListener.swift`
- Modify: `Sources/Footswitch/AppDelegate.swift`
- Modify: `Sources/Footswitch/SettingsView.swift`
- Modify: `Tests/FootswitchCoreTests/TriggerReconcilerTests.swift`
- Modify: `Tests/FootswitchCoreTests/ConfigAdoptTests.swift`
- Modify: `Tests/FootswitchCoreTests/DeviceTests.swift`

**Interfaces:**
- Consumes: Task 1 (`TriggerKey.combo`, `Keymap.modifiers(forFlagBits:)`, `Config.triggerCombo`, `Config.adoptingTriggerCombo`, `Device.adopting(combo:)`), Task 2 (`TriggerMatcher`), and existing `KeyComboFormatter.display`.
- Produces:
  - `CapturedKey.named(KeyCombo)` + `CapturedKey.from(keyCode: UInt16, modifierBits: UInt64)`
  - `TriggerReconciliation.match(combo:)/.mismatch(captured:expected:)/.unknown(code:expected:)/.noKey` over `KeyCombo`
  - `TriggerReconciler.reconcile(captured:expected: KeyCombo)`
  - `PedalListener.beginCapture(onCapture: @escaping @Sendable (UInt16, UInt64) -> Void)`

- [ ] **Step 1: Rewrite `TriggerReconciler.swift` + its tests**

Replace `Sources/FootswitchCore/TriggerReconciler.swift` with:

```swift
// Sources/FootswitchCore/TriggerReconciler.swift
import Foundation

/// The combo a pedal actually emitted during a Settings "Test", resolved against
/// the app's key table. `named` carries a `KeyCombo` (key + modifiers) that
/// round-trips through programming + the listener; `unknown` carries a raw virtual
/// key code with no name (shown but not adoptable); `none` = nothing captured.
public enum CapturedKey: Equatable, Sendable {
    case named(KeyCombo)
    case unknown(UInt16)
    case none

    /// Resolves a raw virtual key code + masked modifier bits into a `CapturedKey`.
    public static func from(keyCode: UInt16, modifierBits: UInt64) -> CapturedKey {
        guard let name = Keymap.keyName(forCode: keyCode) else { return .unknown(keyCode) }
        return .named(KeyCombo(modifiers: Keymap.modifiers(forFlagBits: modifierBits), key: name))
    }
}

/// The outcome of comparing a captured combo to the configured (expected) trigger
/// combo. `match` is a green confirmation; `mismatch` offers adopt-or-reprogram;
/// `unknown` offers reprogram only; `noKey` is a timeout/cancel no-op.
public enum TriggerReconciliation: Equatable, Sendable {
    case match(combo: KeyCombo)
    case mismatch(captured: KeyCombo, expected: KeyCombo)
    case unknown(code: UInt16, expected: KeyCombo)
    case noKey
}

public enum TriggerReconciler {
    /// Compares a captured combo to the `expected` configured combo: key name is
    /// case-insensitive; modifiers compare as a set (order-independent).
    public static func reconcile(captured: CapturedKey, expected: KeyCombo) -> TriggerReconciliation {
        switch captured {
        case .none:
            return .noKey
        case .unknown(let code):
            return .unknown(code: code, expected: expected)
        case .named(let combo):
            let sameKey = combo.key.compare(expected.key, options: .caseInsensitive) == .orderedSame
            if sameKey && Set(combo.modifiers) == Set(expected.modifiers) {
                return .match(combo: combo)
            }
            return .mismatch(captured: combo, expected: expected)
        }
    }
}
```

Replace `Tests/FootswitchCoreTests/TriggerReconcilerTests.swift` with:

```swift
// Tests/FootswitchCoreTests/TriggerReconcilerTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerReconcilerTests: XCTestCase {
    private func combo(_ key: String, _ mods: [Modifier] = []) -> KeyCombo {
        KeyCombo(modifiers: mods, key: key)
    }

    func testFromKnownKeyCodeWithModifiers() {
        // F13 = 0x69; control flag = 0x40000.
        XCTAssertEqual(CapturedKey.from(keyCode: 0x69, modifierBits: 0x40000),
                       .named(combo("F13", [.control])))
    }

    func testFromUnknownKeyCode() {
        XCTAssertEqual(CapturedKey.from(keyCode: 0x6E, modifierBits: 0), .unknown(0x6E))
    }

    func testReconcileMatchExactCaseInsensitiveModifierSet() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named(combo("f13", [.shift, .control])),
                                        expected: combo("F13", [.control, .shift])),
            .match(combo: combo("f13", [.shift, .control])))
    }

    func testReconcileMismatchOnModifiers() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named(combo("F13")),
                                        expected: combo("F13", [.control])),
            .mismatch(captured: combo("F13"), expected: combo("F13", [.control])))
    }

    func testReconcileUnknown() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .unknown(0x6E), expected: combo("F16")),
            .unknown(code: 0x6E, expected: combo("F16")))
    }

    func testReconcileNoKey() {
        XCTAssertEqual(TriggerReconciler.reconcile(captured: .none, expected: combo("F16")), .noKey)
    }
}
```

- [ ] **Step 2: Update `PedalListener` to match `(keycode + modifiers)` and capture combos**

In `Sources/Footswitch/PedalListener.swift`:

Replace the stored properties `keyCodeToSlot`/`debouncers`/`captureHandler` declarations with:

```swift
    private let matcher: TriggerMatcher
    private var debouncers: [TriggerMatcher.Key: Debouncer]
    private let onFire: @Sendable (_ slot: Int) -> Void

    /// While non-nil, the next keydown is captured (keycode + masked modifier bits,
    /// reported on the main thread) and swallowed instead of the normal slot
    /// dispatch — the Settings "Test" flow. One-shot.
    private var captureHandler: (@Sendable (UInt16, UInt64) -> Void)?

    func beginCapture(onCapture: @escaping @Sendable (UInt16, UInt64) -> Void) { captureHandler = onCapture }
    func endCapture() { captureHandler = nil }
```

Replace the `init` body that built `keyCodeToSlot`/`debouncers` with:

```swift
    init(triggerKeys: [TriggerKey], debounceMs: Int, onFire: @escaping @Sendable (_ slot: Int) -> Void) {
        let matcher = TriggerMatcher(triggerKeys: triggerKeys)
        self.matcher = matcher
        self.debouncers = Dictionary(uniqueKeysWithValues:
            matcher.keys.map { ($0, Debouncer(intervalMs: debounceMs)) })
        self.onFire = onFire
    }
```

Replace the body of `handle(type:event:)` from the `keyCode` line through the end with:

```swift
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modBits = event.flags.rawValue & Keymap.deviceModifierMask
        if let capture = captureHandler {
            captureHandler = nil                          // one-shot
            DispatchQueue.main.async { capture(keyCode, modBits) }
            return nil                                    // swallow; suspend dispatch
        }
        guard let slot = matcher.slot(forKeyCode: keyCode, modBits: modBits) else {
            return Unmanaged.passUnretained(event)        // pass through everything else
        }
        let matchKey = TriggerMatcher.Key(keyCode: keyCode, modBits: modBits)
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var fired = false
        if var d = debouncers[matchKey] {
            fired = d.shouldFire(atMs: nowMs)
            debouncers[matchKey] = d
        } else {
            fired = true
        }
        if fired {
            let fire = onFire
            DispatchQueue.main.async { fire(slot) }
        }
        return nil   // swallow the trigger so it never reaches the focused app
```

(The `import FootswitchCore` at the top already covers `TriggerMatcher`/`Keymap`. The tap-disabled re-enable block at the top of `handle` is unchanged.)

- [ ] **Step 3: Update `AppDelegate.beginCapture` to build the combo**

In `Sources/Footswitch/AppDelegate.swift`, change the `listener.beginCapture` closure inside `beginCapture(timeoutMs:completion:)`:

```swift
        listener.beginCapture { [weak self] keyCode, modBits in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.isCapturing else { return }
                self.finishCapture()
                completion(CapturedKey.from(keyCode: keyCode, modifierBits: modBits))
            }
        }
```

- [ ] **Step 4: Update `SettingsView` to resolve/program/test/adopt with combos**

In `Sources/Footswitch/SettingsView.swift`:

(a) `keyForSlot` returns a `KeyCombo`:

```swift
    /// The configured trigger combo for a slot on the connected `device` (its entry's
    /// trigger, else the code default), from the live `devices` so an adopt shows now.
    private func keyForSlot(_ slot: Int, device: SupportedDevice) -> KeyCombo {
        Config.triggerCombo(in: devices, forVendorID: device.vendorID,
                            productID: device.productID, slot: slot)
    }
```

(b) In `verifyAndRenderRow(...)`, replace the `expected` line — `keyForSlot` is now the full combo, so drop the wrapping:

```swift
        let expected = keyForSlot(slot, device: device)
```

(c) In `programSlot(_:button:)`, replace the `key`/`combo`/message lines:

```swift
        let combo = keyForSlot(slot, device: detected.device)
```
and (in the off-main block) the success message:
```swift
                message = transport == .bluetooth
                    ? L10n.alertProgrammedBluetooth(key: KeyComboFormatter.display(combo))
                    : L10n.alertProgrammed(key: KeyComboFormatter.display(combo))
```

(d) In `startTest(slot:)`, the capture-completion block computes the expected combo and reconciles:

```swift
            let expected = self.keyForSlot(slot, device: device)
            let outcome = TriggerReconciler.reconcile(captured: captured, expected: expected)
            self.presentTestOutcome(outcome, slot: slot, device: device)
```

(e) Replace `presentTestOutcome(...)`'s `switch` cases to use combo displays:

```swift
        switch outcome {
        case .match(let combo):
            alert.informativeText = L10n.testMatch(key: KeyComboFormatter.display(combo))
            alert.addButton(withTitle: L10n.alertOK)
            runOutcome(alert) { _ in }
        case .mismatch(let captured, let expected):
            alert.informativeText = L10n.testMismatch(
                captured: KeyComboFormatter.display(captured),
                expected: KeyComboFormatter.display(expected))
            alert.addButton(withTitle: L10n.testUseKey(key: KeyComboFormatter.display(captured)))     // first
            alert.addButton(withTitle: L10n.testReprogram(key: KeyComboFormatter.display(expected)))  // second
            alert.addButton(withTitle: L10n.alertCancel)                                              // third
            runOutcome(alert) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    self?.adopt(combo: captured, slot: slot, device: device)
                } else if resp == .alertSecondButtonReturn {
                    self?.reprogram(slot: slot)
                }
            }
        case .unknown(let code, let expected):
            alert.informativeText = L10n.testUnknown(
                code: String(format: "0x%02X", code),
                expected: KeyComboFormatter.display(expected))
            alert.addButton(withTitle: L10n.testReprogram(key: KeyComboFormatter.display(expected)))  // first
            alert.addButton(withTitle: L10n.alertCancel)                                              // second
            runOutcome(alert) { [weak self] resp in
                if resp == .alertFirstButtonReturn { self?.reprogram(slot: slot) }
            }
        case .noKey:
            alert.informativeText = L10n.testNoKey
            alert.addButton(withTitle: L10n.alertOK)
            runOutcome(alert) { _ in }
        }
```

(The `if case .match = outcome { blePowerCyclePendingSlots.remove(slot) }` line at the top of `presentTestOutcome` is unchanged — it still matches `.match` regardless of its associated value.)

(f) Replace `adopt(...)` to take a combo:

```swift
    private func adopt(combo: KeyCombo, slot: Int, device: SupportedDevice) {
        devices = Config.adoptingTriggerCombo(in: devices, combo: combo, slot: slot, for: device)
        // Config now matches what the pedal emits — there is no pending power-cycle (#12).
        blePowerCyclePendingSlots.remove(slot)
        save()
        refreshDeviceStatus()
    }
```

- [ ] **Step 5: Remove the now-unused String helpers + update their tests**

(a) In `Sources/FootswitchCore/Models/Config.swift`, delete the static `triggerKey(in devices:forVendorID:productID:slot:) -> String` and `adoptingTriggerKey(in devices:key:slot:for:) -> [Device]` methods (replaced by the combo versions from Task 1). Keep the instance `triggerKey(forVendorID:productID:slot:)` and `triggerKeys(forVendorID:productID:)` (still used by `ConfigCodingTests`).

(b) In `Sources/FootswitchCore/Models/Device.swift`, delete `adopting(key:slot:)` (replaced by `adopting(combo:slot:)`).

(c) In `Tests/FootswitchCoreTests/ConfigAdoptTests.swift`, replace the body with the combo-based equivalents:

```swift
// Tests/FootswitchCoreTests/ConfigAdoptTests.swift
import XCTest
@testable import FootswitchCore

final class ConfigAdoptTests: XCTestCase {
    private let fs17proBLE = SupportedDevice(vendorID: 0x245A, productID: 0x8276,
                                             program: .footswitchBLE, name: "FS17Pro")

    func testResolveComboEntryThenDefault() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1, modifiers: [.control])])]
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x245A, productID: 0x8276, slot: 1),
                       KeyCombo(modifiers: [.control], key: "F16"))
        XCTAssertEqual(Config.triggerCombo(in: devices, forVendorID: 0x1, productID: 0x2, slot: 2),
                       KeyCombo(modifiers: [], key: "F14"))
    }

    func testAdoptComboUpdatesExistingEntry() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1)])]
        let out = Config.adoptingTriggerCombo(in: devices, combo: KeyCombo(modifiers: [.option], key: "F19"),
                                              slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1, modifiers: [.option])])
    }

    func testAdoptComboSeedsEntryWhenDeviceHasNone() {
        let out = Config.adoptingTriggerCombo(in: [], combo: KeyCombo(modifiers: [.control], key: "F19"),
                                              slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].resolved()?.vendorID, 0x245A)
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1, modifiers: [.control])])
    }

    func testAdoptComboRoundTripsThroughConfigCoding() throws {
        var config = Config.default
        config.devices = Config.adoptingTriggerCombo(in: config.devices,
                                                     combo: KeyCombo(modifiers: [.shift], key: "F19"),
                                                     slot: 1, for: fs17proBLE)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.triggerCombo(forVendorID: 0x245A, productID: 0x8276, slot: 1),
                       KeyCombo(modifiers: [.shift], key: "F19"))
    }
}
```

Note: `testAdoptComboRoundTripsThroughConfigCoding` uses an instance `triggerCombo(forVendorID:productID:slot:)`. Add that instance convenience to `Config` (next to the instance `triggerKey(forVendorID:...)`):

```swift
    /// The configured trigger combo for a connected device's slot (else the code
    /// default).
    public func triggerCombo(forVendorID vid: Int, productID pid: Int, slot: Int) -> KeyCombo {
        Self.triggerCombo(in: devices, forVendorID: vid, productID: pid, slot: slot)
    }
```

(d) In `Tests/FootswitchCoreTests/DeviceTests.swift`, replace the `testAdoptReplacesAndAppends` test with the combo form:

```swift
    func testAdoptComboReplacesAndAppends() {
        let base = Device(vendorId: "0x1", productId: "0x2", program: "footswitch",
                          name: "X", triggers: [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(base.adopting(combo: KeyCombo(modifiers: [.control], key: "F19"), slot: 1).triggers,
                       [TriggerKey(key: "F19", slot: 1, modifiers: [.control])])
        XCTAssertEqual(base.adopting(combo: KeyCombo(modifiers: [], key: "F14"), slot: 2).triggers,
                       [TriggerKey(key: "F13", slot: 1), TriggerKey(key: "F14", slot: 2)])
    }
```

- [ ] **Step 6: Build + test the whole package**

Run: `touch Sources/Footswitch/SettingsView.swift Sources/Footswitch/AppDelegate.swift Sources/Footswitch/PedalListener.swift && swift build 2>&1 | grep -iE 'warning|deprecat|error'`
Expected: prints NOTHING (warning-free).

Run: `swift test`
Expected: all pass — `TriggerKeyModifierTests`, `TriggerMatcherTests`, `TriggerReconcilerTests`, `ConfigAdoptTests`, `DeviceTests`, `ConfigCodingTests`, `LocalizationParityTests`, and the rest.

Confirm no stragglers: `rg -n "adopting\(key:|adoptingTriggerKey\(in:|Config\.triggerKey\(in:|CapturedKey\.from\(keyCode: [a-z]+\)$" Sources Tests` should return nothing.

- [ ] **Step 7: Commit**

```bash
git add Sources/FootswitchCore/TriggerReconciler.swift Sources/FootswitchCore/Models/Config.swift Sources/FootswitchCore/Models/Device.swift Sources/Footswitch/PedalListener.swift Sources/Footswitch/AppDelegate.swift Sources/Footswitch/SettingsView.swift Tests/FootswitchCoreTests/TriggerReconcilerTests.swift Tests/FootswitchCoreTests/ConfigAdoptTests.swift Tests/FootswitchCoreTests/DeviceTests.swift
git commit -m "feat: combo capture/reconcile + exact-modifier listener match (#10)"
```

---

### Task 4: Full build, test, and verification

**Files:** none (verification + final commit if anything was touched).

- [ ] **Step 1: Full clean build**

Run: `touch Sources/Footswitch/*.swift Sources/FootswitchCore/**/*.swift && swift build 2>&1 | grep -iE 'warning|deprecat|error'`
Expected: nothing (warning-free).

- [ ] **Step 2: Full test suite + parity**

Run: `swift test`
Expected: all pass, including `LocalizationParityTests` (no new strings added).

- [ ] **Step 3: Manual hardware verification (requires pedals)**

With a foot switch connected:
1. Program a slot to a modifier combo (e.g. `⌃F19`) via config or the Program button; confirm the device row verifies (✓) and a press fires the action.
2. With a different button/pedal sharing a keycode but a different modifier, confirm each fires its own slot.
3. Test capture: press a pedal that emits `⌃F19`; confirm the outcome shows the full combo (`⌃F19`) and **Use** adopts the combo (the row then verifies against `⌃F19`).
4. Confirm a bare-key trigger still fires on a bare press.

- [ ] **Step 4: Final commit (only if files changed during verification)**

```bash
git add -A
git commit -m "chore: modifier trigger detection verification fixups (#10)"
```

---

## Self-Review

**Spec coverage:**
- `TriggerKey.modifiers` tolerant + byte-stable, `combo` → Task 1. ✓
- Exact `(keycode + modifiers)` listener match via pure seam → Tasks 2 (matcher) + 3 (PedalListener wiring). ✓
- Mask to the four device modifiers → Task 1 (`deviceModifierMask`), used in Task 3 (`event.flags.rawValue & mask`). ✓
- Test capture records the full combo; reconcile compares combos → Task 3 (`CapturedKey.from(keyCode:modifierBits:)`, `reconcile`). ✓
- Resolution/adopt carry combos → Task 1 (`triggerCombo`/`adoptingTriggerCombo`/`Device.adopting(combo:)`), Task 3 (Settings switch + cleanup). ✓
- Programming + verify carry modifiers for free → Task 3 (`programSlot` passes the full combo to the unchanged program/verify path). ✓
- Display via `KeyComboFormatter.display`; no new L10n → Task 3 + Task 4 parity check. ✓
- Canonical modifier order (control, option, shift, command) consistent across `Keymap.modifiers(forFlagBits:)`, `KeyComboFormatter`, `DeviceModifier.modifiers(fromBits:)` → Task 1. ✓
- Back-compat (bare configs decode to `[]`, exact-match on bare key; byte-stable encode) → Task 1 codable. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the only delegated step (Task 4 Step 3) is hardware-dependent manual verification, explicitly scoped. ✓

**Type consistency:** `TriggerKey(key:slot:modifiers:)`, `TriggerKey.combo`, `Keymap.deviceModifierMask`/`modifiers(forFlagBits:)`, `TriggerMatcher`/`.Key`/`.slot(forKeyCode:modBits:)`, `CapturedKey.named(KeyCombo)`/`from(keyCode:modifierBits:)`, `TriggerReconciliation.match(combo:)`, `reconcile(captured:expected:KeyCombo)`, `Config.triggerCombo`/`adoptingTriggerCombo`/instance `triggerCombo`, `Device.adopting(combo:slot:)`, `PedalListener.beginCapture(onCapture:(UInt16,UInt64))` are consistent across tasks. ✓

**Build ordering:** Tasks 1–2 additive and green; Task 3 is the coupled breaking change (core enum payload + app wiring + test updates) green only at its end, per the header constraint.
