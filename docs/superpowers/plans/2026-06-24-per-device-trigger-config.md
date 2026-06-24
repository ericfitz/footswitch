# Per-Device Trigger Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the global per-transport `Config.triggers` and the `customDevices` array with a single `devices` section where each recognized foot switch owns its trigger keys, migrating existing configs losslessly.

**Architecture:** A new `Device` model (identity + `[TriggerKey]`) replaces `CustomDevice` as the config table entry. `Config.devices` replaces `triggers`/`customDevices`; resolution maps a connected VID/PID to its entry's keys or a code-level default. Legacy configs migrate on decode by seeding every built-in + custom device from the old global triggers. Runtime dispatch stays `keycode → slot` — per-device routing is out of scope.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit (Settings UI). Spec: `docs/superpowers/specs/2026-06-24-per-device-trigger-config-design.md`.

## Global Constraints

- `FootswitchCore` is a separate module from the `Footswitch` app target. Core tasks (1–4) build and test via `swift test --filter <name>` without the app target; the **app target will not build until Task 6** — that is expected.
- `Triggers` and `CustomDevice` types are **retained for legacy decode only** (migration reads them). Do not delete them.
- VID/PID are hex strings in JSON ("0x245A" or bare "245A"); seeded entries are formatted `0x%04X` uppercase.
- Transport is **derived** from the program family (`.footswitchBLE` → Bluetooth, all else → USB), never stored.
- Code-level default trigger set: `[F13/slot1, F14/slot2, F15/slot3]` (the historical `Config.default`), clamped to detected slots by the existing `buildListener`.
- The encoder **always** writes `devices` (even when empty) so a config saved by this app version is never re-migrated; only configs with **no** `devices` key (written by older versions) migrate.
- Runtime dispatch path (`keycode → slot → RuleResolver`) is unchanged.
- Build/test: `swift build`, `swift test`. No SwiftLint in this repo.

---

### Task 1: Core — `Device` model + `Program.transport`

**Files:**
- Create: `Sources/FootswitchCore/Models/Device.swift`
- Modify: `Sources/FootswitchCore/FootswitchDevice.swift` (append `Program.transport`)
- Test: `Tests/FootswitchCoreTests/DeviceTests.swift`

**Interfaces:**
- Consumes: `TriggerKey`, `SupportedDevice`, `SupportedDevice.Program`, `Transport` (existing).
- Produces:
  - `struct Device: Codable, Equatable, Sendable { var vendorId/productId/program/name: String; var triggers: [TriggerKey]; func resolved() -> SupportedDevice?; func adopting(key: String, slot: Int) -> Device; static func parseID(_:) -> Int? }`
  - `extension SupportedDevice.Program { var transport: Transport }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/FootswitchCoreTests/DeviceTests.swift
import XCTest
@testable import FootswitchCore

final class DeviceTests: XCTestCase {
    func testResolvedValidatesIdentity() {
        let d = Device(vendorId: "0x245A", productId: "8276",
                       program: "footswitchBLE", name: "FS17Pro")
        let r = d.resolved()
        XCTAssertEqual(r?.vendorID, 0x245A)
        XCTAssertEqual(r?.productID, 0x8276)
        XCTAssertEqual(r?.program, .footswitchBLE)
    }

    func testResolvedRejectsMalformed() {
        XCTAssertNil(Device(vendorId: "zz", productId: "1", program: "footswitch", name: "x").resolved())
        XCTAssertNil(Device(vendorId: "1", productId: "2", program: "nope", name: "x").resolved())
        XCTAssertNil(Device(vendorId: "1", productId: "2", program: "footswitch", name: "  ").resolved())
    }

    func testProgramTransport() {
        XCTAssertEqual(SupportedDevice.Program.footswitchBLE.transport, .bluetooth)
        XCTAssertEqual(SupportedDevice.Program.footswitch.transport, .usb)
        XCTAssertEqual(SupportedDevice.Program.scythe.transport, .usb)
    }

    func testTriggersOptionalOnDecode() throws {
        let json = #"{"vendorId":"0x1","productId":"0x2","program":"footswitch","name":"X"}"#
        let d = try JSONDecoder().decode(Device.self, from: Data(json.utf8))
        XCTAssertEqual(d.triggers, [])
    }

    func testEncodeOmitsEmptyTriggers() throws {
        let d = Device(vendorId: "0x1", productId: "0x2", program: "footswitch", name: "X")
        let obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(d)) as? [String: Any]
        XCTAssertNil(obj?["triggers"])
    }

    func testAdoptReplacesAndAppends() {
        let base = Device(vendorId: "0x1", productId: "0x2", program: "footswitch",
                          name: "X", triggers: [TriggerKey(key: "F13", slot: 1)])
        XCTAssertEqual(base.adopting(key: "F19", slot: 1).triggers,
                       [TriggerKey(key: "F19", slot: 1)])
        XCTAssertEqual(base.adopting(key: "F14", slot: 2).triggers,
                       [TriggerKey(key: "F13", slot: 1), TriggerKey(key: "F14", slot: 2)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DeviceTests`
Expected: FAIL — "cannot find 'Device'" / "no member 'transport'".

- [ ] **Step 3: Add `Program.transport`**

Append to `Sources/FootswitchCore/FootswitchDevice.swift`:

```swift
public extension SupportedDevice.Program {
    /// The transport this protocol family implies. Only `.footswitchBLE` is
    /// Bluetooth; the rest are USB HID. Used wherever transport must be derived
    /// from a matched device (programming path, config-verify, BLE messaging).
    var transport: Transport { self == .footswitchBLE ? .bluetooth : .usb }
}
```

- [ ] **Step 4: Create the `Device` model**

```swift
// Sources/FootswitchCore/Models/Device.swift
import Foundation

/// One recognized foot switch and its trigger keys. Replaces `CustomDevice` as the
/// config device-table entry (GitHub issue #9; supersedes the #4 customDevices
/// array): carries device identity AND this device's keys. VID/PID are hex strings
/// ("0x245A" or bare "245A"); `program` names a protocol family; `triggers` is this
/// device's flat key list (empty ⇒ the resolver's code default applies). Transport
/// is implied by `program`, not stored.
public struct Device: Codable, Equatable, Sendable {
    public var vendorId: String
    public var productId: String
    public var program: String
    public var name: String
    public var triggers: [TriggerKey]

    public init(vendorId: String, productId: String, program: String,
                name: String, triggers: [TriggerKey] = []) {
        self.vendorId = vendorId
        self.productId = productId
        self.program = program
        self.name = name
        self.triggers = triggers
    }

    private enum CodingKeys: String, CodingKey {
        case vendorId, productId, program, name, triggers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vendorId = try c.decode(String.self, forKey: .vendorId)
        productId = try c.decode(String.self, forKey: .productId)
        program = try c.decode(String.self, forKey: .program)
        name = try c.decode(String.self, forKey: .name)
        // Optional: absent ⇒ empty (device uses the resolver's code default).
        triggers = (try? c.decode([TriggerKey].self, forKey: .triggers)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vendorId, forKey: .vendorId)
        try c.encode(productId, forKey: .productId)
        try c.encode(program, forKey: .program)
        try c.encode(name, forKey: .name)
        if !triggers.isEmpty { try c.encode(triggers, forKey: .triggers) }
    }

    /// Parses a hex ("0x245A", "245a") string into a 16-bit USB ID, or nil. The
    /// `0x`/`0X` prefix is optional; bare strings are hex (the USB convention).
    static func parseID(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let body = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X")
            ? String(trimmed.dropFirst(2)) : trimmed
        guard !body.isEmpty, let value = Int(body, radix: 16),
              (0x0000...0xFFFF).contains(value) else { return nil }
        return value
    }

    /// Validates identity and converts to a `SupportedDevice`, or nil for malformed
    /// VID/PID, unknown program family, or blank name. Triggers are not part of the
    /// identity. Callers skip invalid entries rather than fail the whole load.
    public func resolved() -> SupportedDevice? {
        guard let vid = Self.parseID(vendorId),
              let pid = Self.parseID(productId),
              let prog = SupportedDevice.Program(rawValue: program) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        return SupportedDevice(vendorID: vid, productID: pid, program: prog, name: trimmedName)
    }

    /// Returns a copy with `key` set as the trigger for `slot`: replaces the slot's
    /// existing key (slot preserved) or appends `TriggerKey(key:slot:)`. The #6 Test
    /// button's adopt path uses this under the per-device model.
    public func adopting(key: String, slot: Int) -> Device {
        var copy = triggers
        if let i = copy.firstIndex(where: { $0.slot == slot }) {
            copy[i].key = key
        } else {
            copy.append(TriggerKey(key: key, slot: slot))
        }
        var out = self
        out.triggers = copy
        return out
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter DeviceTests`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/FootswitchCore/Models/Device.swift Sources/FootswitchCore/FootswitchDevice.swift Tests/FootswitchCoreTests/DeviceTests.swift
git commit -m "feat: Device model + Program.transport for per-device config (#9)"
```

---

### Task 2: Core — `SupportedDevices.match(devices:)`

**Files:**
- Modify: `Sources/FootswitchCore/FootswitchDevice.swift`
- Test: `Tests/FootswitchCoreTests/SupportedDevicesMatchTests.swift`

**Interfaces:**
- Replaces `match(vendorID:productID:custom: [CustomDevice])` with
  `match(vendorID:productID:devices: [Device]) -> SupportedDevice?` (entries first, then built-ins).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/FootswitchCoreTests/SupportedDevicesMatchTests.swift
import XCTest
@testable import FootswitchCore

final class SupportedDevicesMatchTests: XCTestCase {
    func testBuiltInStillMatchesWithEmptyDevices() {
        let m = SupportedDevices.match(vendorID: 0x0c45, productID: 0x7403, devices: [])
        XCTAssertEqual(m?.program, .footswitch)
    }

    func testDeviceEntryExtendsTable() {
        let custom = Device(vendorId: "0xAAAA", productId: "0xBBBB",
                            program: "footswitch", name: "Clone")
        let m = SupportedDevices.match(vendorID: 0xAAAA, productID: 0xBBBB, devices: [custom])
        XCTAssertEqual(m?.name, "Clone")
    }

    func testDeviceEntryOverridesBuiltIn() {
        let override = Device(vendorId: "0x0c45", productId: "0x7403",
                              program: "footswitch", name: "My Override")
        let m = SupportedDevices.match(vendorID: 0x0c45, productID: 0x7403, devices: [override])
        XCTAssertEqual(m?.name, "My Override")
    }

    func testMalformedEntrySkipped() {
        let bad = Device(vendorId: "zz", productId: "zz", program: "nope", name: "")
        let m = SupportedDevices.match(vendorID: 0x0c45, productID: 0x7403, devices: [bad])
        XCTAssertEqual(m?.name, "PCsensor FootSwitch") // falls through to built-in
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SupportedDevicesMatchTests`
Expected: FAIL — "extra argument 'devices'" / missing overload.

- [ ] **Step 3: Replace the `custom:` overload**

In `Sources/FootswitchCore/FootswitchDevice.swift`, replace the `match(vendorID:productID:custom:)` method with:

```swift
    /// Matches against configured `devices` first (so an entry can override or
    /// extend the built-in table), then the built-ins. Invalid entries (malformed
    /// VID/PID, unknown program family) are skipped via `resolved()`. Adding a
    /// same-protocol pedal is thus a config change, not a code change (issues #4/#9).
    public static func match(vendorID: Int, productID: Int,
                             devices: [Device]) -> SupportedDevice? {
        for entry in devices {
            if let dev = entry.resolved(), dev.vendorID == vendorID, dev.productID == productID {
                return dev
            }
        }
        return match(vendorID: vendorID, productID: productID)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SupportedDevicesMatchTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/FootswitchDevice.swift Tests/FootswitchCoreTests/SupportedDevicesMatchTests.swift
git commit -m "feat: SupportedDevices.match(devices:) for per-device table (#9)"
```

---

### Task 3: Core — `Config` rewrite, migration, resolution

**Files:**
- Modify: `Sources/FootswitchCore/Models/Config.swift` (full rewrite)
- Replace: `Tests/FootswitchCoreTests/ConfigCodingTests.swift` (rewrite for the new shape)

**Interfaces:**
- Consumes: `Device` (Task 1), `Triggers`/`CustomDevice` (legacy decode), `SupportedDevices.all`.
- Produces on `Config`:
  - `var devices: [Device]` (replaces `triggers` + `customDevices`; `allTriggerKeys` removed)
  - `init(devices:dictationShortcut:debounceMs:defaultAction:rules:)`
  - `static let defaultTriggerKeys: [TriggerKey]`
  - `func device(forVendorID:productID:) -> Device?`
  - `func triggerKeys(forVendorID:productID:) -> [TriggerKey]`
  - `func triggerKey(forVendorID:productID:slot:) -> String`
  - `var listenerKeys: [TriggerKey]`

- [ ] **Step 1: Rewrite `Config.swift`**

Replace the entire file with:

```swift
// Sources/FootswitchCore/Models/Config.swift
import Foundation

public struct Config: Codable, Equatable, Sendable {
    /// Recognized foot switches and their trigger keys (GitHub issue #9). Replaces
    /// the global per-transport `triggers` and the #4 `customDevices` array. A
    /// connected device's keys come from its matching entry; an entry-less or
    /// unknown device falls back to `Config.defaultTriggerKeys`.
    public var devices: [Device]
    public var dictationShortcut: KeyCombo
    public var debounceMs: Int
    public var defaultAction: DefaultAction
    public var rules: [Rule]

    /// The historical default trigger set, applied when a connected device has no
    /// entry (or an empty `triggers`). Clamped to detected slots by the listener.
    public static let defaultTriggerKeys: [TriggerKey] = [
        TriggerKey(key: "F13", slot: 1),
        TriggerKey(key: "F14", slot: 2),
        TriggerKey(key: "F15", slot: 3),
    ]

    public init(devices: [Device], dictationShortcut: KeyCombo, debounceMs: Int,
                defaultAction: DefaultAction, rules: [Rule]) {
        self.devices = devices
        self.dictationShortcut = dictationShortcut
        self.debounceMs = debounceMs
        self.defaultAction = defaultAction
        self.rules = rules
    }

    // MARK: Resolution

    /// The configured device entry matching a connected VID/PID, if any.
    public func device(forVendorID vid: Int, productID pid: Int) -> Device? {
        devices.first { $0.resolved().map { $0.vendorID == vid && $0.productID == pid } ?? false }
    }

    /// The trigger keys for a connected device: its entry's non-empty `triggers`,
    /// else the code default.
    public func triggerKeys(forVendorID vid: Int, productID pid: Int) -> [TriggerKey] {
        if let d = device(forVendorID: vid, productID: pid), !d.triggers.isEmpty {
            return d.triggers
        }
        return Self.defaultTriggerKeys
    }

    /// The configured key name for a connected device's slot (else the code-default
    /// key for that slot, else the first default key).
    public func triggerKey(forVendorID vid: Int, productID pid: Int, slot: Int) -> String {
        let keys = triggerKeys(forVendorID: vid, productID: pid)
        return keys.first { $0.slot == slot }?.key
            ?? keys.first?.key
            ?? Self.defaultTriggerKeys[0].key
    }

    /// Every trigger key the listener should watch: the union across all device
    /// entries (deduped by key name), or the code default if none are configured.
    public var listenerKeys: [TriggerKey] {
        var seen = Set<String>()
        var result: [TriggerKey] = []
        for k in devices.flatMap(\.triggers) where seen.insert(k.key).inserted {
            result.append(k)
        }
        return result.isEmpty ? Self.defaultTriggerKeys : result
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case devices                                   // current
        case triggerKey, triggerKeys, triggers, customDevices  // legacy (read-only)
        case dictationShortcut, debounceMs, defaultAction, rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dictationShortcut = try c.decode(KeyCombo.self, forKey: .dictationShortcut)
        debounceMs = try c.decode(Int.self, forKey: .debounceMs)
        defaultAction = (try? c.decode(DefaultAction.self, forKey: .defaultAction)) ?? .dictation
        rules = try c.decode([Rule].self, forKey: .rules)

        if c.contains(.devices) {
            // Current shape: a config written by this app version (the encoder always
            // emits `devices`). Decode directly; a malformed array decodes to empty.
            devices = (try? c.decode([Device].self, forKey: .devices)) ?? []
        } else {
            // Legacy shape (older app version): migrate the old global triggers (+
            // customDevices) into a per-device table, seeding every built-in + custom
            // device so no trigger config is lost.
            devices = Self.migrateLegacy(container: c)
        }
    }

    // The encoder ALWAYS writes `devices` (even when empty) so a config we saved is
    // never re-migrated on reload — only configs lacking the key (older versions)
    // migrate. Legacy keys are read-only and never written.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(devices, forKey: .devices)
        try c.encode(dictationShortcut, forKey: .dictationShortcut)
        try c.encode(debounceMs, forKey: .debounceMs)
        try c.encode(defaultAction, forKey: .defaultAction)
        try c.encode(rules, forKey: .rules)
    }

    public static let `default` = Config(
        devices: [],
        dictationShortcut: KeyCombo(modifiers: [.control, .option, .command], key: "D"),
        debounceMs: 250,
        defaultAction: .dictation,
        rules: []
    )

    // MARK: Legacy migration

    /// Builds the per-device table from a legacy config's global triggers and
    /// `customDevices`. Seeds an entry for every built-in `SupportedDevices.all`
    /// device plus each custom entry (custom first so overrides win; deduped by
    /// VID/PID), assigning trigger keys by the device's transport (USB families get
    /// the old `triggers.usb`, `.footswitchBLE` gets `triggers.bluetooth`). Lossless.
    static func migrateLegacy(container c: KeyedDecodingContainer<CodingKeys>) -> [Device] {
        let legacy = legacyTriggers(container: c)
        let customs = (try? c.decode([CustomDevice].self, forKey: .customDevices)) ?? []

        func hex(_ v: Int) -> String { String(format: "0x%04X", v) }
        func keys(for prog: SupportedDevice.Program) -> [TriggerKey] {
            prog.transport == .bluetooth ? legacy.bt : legacy.usb
        }

        var result: [Device] = []
        var seen = Set<String>()
        for cd in customs {
            guard let dev = cd.resolved() else { continue }
            let id = "\(dev.vendorID):\(dev.productID)"
            guard seen.insert(id).inserted else { continue }
            result.append(Device(vendorId: hex(dev.vendorID), productId: hex(dev.productID),
                                 program: dev.program.rawValue, name: dev.name,
                                 triggers: keys(for: dev.program)))
        }
        for dev in SupportedDevices.all {
            let id = "\(dev.vendorID):\(dev.productID)"
            guard seen.insert(id).inserted else { continue }
            result.append(Device(vendorId: hex(dev.vendorID), productId: hex(dev.productID),
                                 program: dev.program.rawValue, name: dev.name,
                                 triggers: keys(for: dev.program)))
        }
        return result
    }

    /// Decodes legacy global triggers in the three historical shapes, newest first,
    /// as per-transport lists. Empty/absent ⇒ the code default (USB) / F13 (BLE).
    private static func legacyTriggers(container c: KeyedDecodingContainer<CodingKeys>)
        -> (usb: [TriggerKey], bt: [TriggerKey]) {
        if let t = try? c.decode(Triggers.self, forKey: .triggers), !t.allKeys.isEmpty {
            return (t.usb, t.bluetooth)
        }
        if let keys = try? c.decode([TriggerKey].self, forKey: .triggerKeys), !keys.isEmpty {
            return (keys, keys)
        }
        if let legacy = try? c.decode(String.self, forKey: .triggerKey) {
            let k = [TriggerKey(key: legacy, slot: 1)]
            return (k, k)
        }
        return (defaultTriggerKeys, [TriggerKey(key: "F13", slot: 1)])
    }
}
```

- [ ] **Step 2: Replace `ConfigCodingTests.swift`**

Replace the entire file with:

```swift
// Tests/FootswitchCoreTests/ConfigCodingTests.swift
import XCTest
@testable import FootswitchCore

final class ConfigCodingTests: XCTestCase {
    // MARK: New shape

    func testNewDevicesShapeRoundTrips() throws {
        let config = Config(
            devices: [Device(vendorId: "0x245A", productId: "0x8276",
                             program: "footswitchBLE", name: "FS17Pro",
                             triggers: [TriggerKey(key: "F16", slot: 1)])],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testDefaultRoundTripsWithEmptyDevices() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(Config.default))
        XCTAssertEqual(decoded, Config.default)
        XCTAssertEqual(decoded.devices, [])
    }

    func testEncoderWritesDevicesNotLegacyKeys() throws {
        let obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(Config.default)) as? [String: Any]
        XCTAssertNotNil(obj?["devices"])
        XCTAssertNil(obj?["triggers"])
        XCTAssertNil(obj?["triggerKeys"])
        XCTAssertNil(obj?["customDevices"])
    }

    // MARK: Resolution

    func testResolutionEntryVsDefault() {
        let config = Config(
            devices: [Device(vendorId: "0x245A", productId: "0x8276",
                             program: "footswitchBLE", name: "FS17Pro",
                             triggers: [TriggerKey(key: "F16", slot: 1)])],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        XCTAssertEqual(config.triggerKey(forVendorID: 0x245A, productID: 0x8276, slot: 1), "F16")
        // Unknown device → code default.
        XCTAssertEqual(config.triggerKey(forVendorID: 0x1111, productID: 0x2222, slot: 2), "F14")
    }

    func testListenerKeysUnionAndFallback() {
        let config = Config(
            devices: [
                Device(vendorId: "0x1", productId: "0x2", program: "footswitch",
                       name: "A", triggers: [TriggerKey(key: "F13", slot: 1)]),
                Device(vendorId: "0x3", productId: "0x4", program: "footswitchBLE",
                       name: "B", triggers: [TriggerKey(key: "F13", slot: 1),
                                             TriggerKey(key: "F16", slot: 2)]),
            ],
            dictationShortcut: KeyCombo(modifiers: [.command], key: "D"),
            debounceMs: 250, defaultAction: .dictation, rules: [])
        XCTAssertEqual(config.listenerKeys,
                       [TriggerKey(key: "F13", slot: 1), TriggerKey(key: "F16", slot: 2)])
        XCTAssertEqual(Config.default.listenerKeys, Config.defaultTriggerKeys)
    }

    // MARK: Legacy migration (lossless)

    func testMigratesLegacyTriggersIntoSeededDevices() throws {
        let json = """
        {
          "triggers": {
            "usb": [ {"key":"F13","slot":1}, {"key":"F14","slot":2}, {"key":"F15","slot":3} ],
            "bluetooth": [ {"key":"F16","slot":1} ]
          },
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs": 250, "defaultAction": { "type":"dictation" }, "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.devices.count, 10) // all built-ins seeded
        // FS17Pro BLE gets the bluetooth keys.
        XCTAssertEqual(config.triggerKeys(forVendorID: 0x245A, productID: 0x8276),
                       [TriggerKey(key: "F16", slot: 1)])
        // A USB built-in gets the usb keys.
        XCTAssertEqual(config.triggerKeys(forVendorID: 0x0c45, productID: 0x7403),
                       [TriggerKey(key: "F13", slot: 1),
                        TriggerKey(key: "F14", slot: 2),
                        TriggerKey(key: "F15", slot: 3)])
    }

    func testMigratesInterimTriggerKeysToAllDevices() throws {
        let json = """
        { "triggerKeys": [ {"key":"F19","slot":1} ],
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        // Interim flat list applied to both transports → every device gets F19.
        XCTAssertEqual(config.triggerKey(forVendorID: 0x245A, productID: 0x8276, slot: 1), "F19")
        XCTAssertEqual(config.triggerKey(forVendorID: 0x0c45, productID: 0x7403, slot: 1), "F19")
    }

    func testMigratesLegacyStringTriggerKey() throws {
        let json = """
        { "triggerKey":"F13",
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.triggerKey(forVendorID: 0x0c45, productID: 0x7403, slot: 1), "F13")
    }

    func testMigrationCustomDeviceOverridesBuiltIn() throws {
        let json = """
        { "triggerKey":"F13",
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [],
          "customDevices": [
            { "vendorId":"0x0c45", "productId":"0x7403", "program":"footswitch", "name":"My Clone" }
          ] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        // Custom entry replaces the built-in on the same VID/PID (no duplicate).
        XCTAssertEqual(config.devices.count, 10)
        XCTAssertEqual(config.device(forVendorID: 0x0c45, productID: 0x7403)?.name, "My Clone")
    }

    func testMigrationIsByteStableOnReencode() throws {
        let json = """
        { "triggers": { "usb":[{"key":"F13","slot":1}], "bluetooth":[{"key":"F16","slot":1}] },
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250, "defaultAction": { "type":"dictation" }, "rules": [] }
        """
        let first = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let second = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(first, second)
    }

    // MARK: defaultAction migration (unchanged behavior)

    func testLegacyKeyComboDefaultMigratesToDictation() throws {
        let json = """
        { "triggerKey":"F13",
          "dictationShortcut": { "modifiers":["cmd"], "key":"D" },
          "debounceMs":250,
          "defaultAction": { "type":"keyCombo", "modifiers":["cmd"], "key":"D" },
          "rules": [] }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.defaultAction, .dictation)
    }
}
```

- [ ] **Step 3: Run the core test suite**

Run: `swift test`
Expected: PASS — `ConfigCodingTests`, `DeviceTests`, `SupportedDevicesMatchTests`, `RuleResolverTests` (its `makeConfig` uses `Config.default`, unaffected), and all other core tests. (The app target is not built by `swift test`.)

- [ ] **Step 4: Commit**

```bash
git add Sources/FootswitchCore/Models/Config.swift Tests/FootswitchCoreTests/ConfigCodingTests.swift
git commit -m "feat: Config.devices replacing triggers/customDevices + migration (#9)"
```

---

### Task 4: App — detection + listener wiring

**Files:**
- Modify: `Sources/Footswitch/FootswitchHIDController.swift`
- Modify: `Sources/Footswitch/AppDelegate.swift`

**Interfaces:**
- Consumes: `Config.devices`, `Config.listenerKeys`, `SupportedDevices.match(devices:)`.
- Produces: `FootswitchHIDController.registeredDevices: [Device]`.

> The app target does not build until Task 6 (Settings still references the removed `triggers`). Do not run `swift build` to completion until then.

- [ ] **Step 1: Rename the registry in `FootswitchHIDController`**

Replace the `registeredCustomDevices` declaration (line ~19) with:

```swift
    /// User/config device-table entries merged with the built-in table during
    /// detection (issues #4/#9). Set by AppDelegate on launch/reload from
    /// `Config.devices`. Kept process-wide so the static detection API needn't
    /// thread a Config through every call.
    nonisolated(unsafe) static var registeredDevices: [Device] = []
```

- [ ] **Step 2: Use it in `matches()`**

In `matches()` (line ~112), replace the `SupportedDevices.match(...)` call with:

```swift
                  let match = SupportedDevices.match(vendorID: vid, productID: pid,
                                                     devices: registeredDevices) else { return nil }
```

- [ ] **Step 3: Wire `AppDelegate` to set the registry + build from `listenerKeys`**

In `AppDelegate.swift`:
- Line ~28 (`applicationDidFinishLaunching`): replace
  `FootswitchHIDController.registeredCustomDevices = config.customDevices` with
  `FootswitchHIDController.registeredDevices = config.devices`
- Line ~47: replace `installListener(triggerKeys: Array(config.allTriggerKeys.prefix(1)))` with
  `installListener(triggerKeys: Array(config.listenerKeys.prefix(1)))`
- Line ~62 (`buildListener`): replace `let allKeys = config.allTriggerKeys` with
  `let allKeys = config.listenerKeys`
- Line ~146 (`reload`): replace
  `FootswitchHIDController.registeredCustomDevices = newConfig.customDevices` with
  `FootswitchHIDController.registeredDevices = newConfig.devices`

- [ ] **Step 4: Commit (intermediate; app target not yet building)**

```bash
git add Sources/Footswitch/FootswitchHIDController.swift Sources/Footswitch/AppDelegate.swift
git commit -m "feat: detection + listener use Config.devices/listenerKeys (#9)"
```

---

### Task 5: App — Settings resolves against the connected device

**Files:**
- Modify: `Sources/Footswitch/SettingsView.swift`

**Interfaces:**
- Consumes: `Config.triggerKey(forVendorID:productID:slot:)`, `SupportedDevice.program.transport`, `FootswitchHIDController.detect()`.
- Produces: `keyForSlot(_ slot: Int, device: SupportedDevice)`; `verifyAndRenderRow` and `renderExtraSlotRows` take the matched `SupportedDevice`; `programSlot` resolves the device from `detect()`.

- [ ] **Step 1: Replace `keyForSlot`**

Replace `keyForSlot(_:transport:)` (lines ~367-370) with:

```swift
    /// The configured trigger key for a slot on the connected `device` (its entry's
    /// keys, else the code default), resolved from config by VID/PID.
    private func keyForSlot(_ slot: Int, device: SupportedDevice) -> String {
        baseConfig.triggerKey(forVendorID: device.vendorID, productID: device.productID, slot: slot)
    }
```

- [ ] **Step 2: Thread the device through `verifyAndRenderRow`**

Replace the `verifyAndRenderRow` signature + the `expected`/`transport` lines (top of the method, lines ~332-334) with:

```swift
    /// Verifies one slot off-main and renders status + program button for its row.
    private func verifyAndRenderRow(slot: Int, device: SupportedDevice,
                                    label: NSTextField, button: NSButton) {
        let transport = device.program.transport
        let expected = KeyCombo(modifiers: [], key: keyForSlot(slot, device: device))
```

(The rest of the method body — `verifyConfiguration`, the `.verified`/`.mismatch`/`.unreadable`/`.noDevice` switch using `transport` — is unchanged.)

- [ ] **Step 3: Update `refreshDeviceStatus` call sites**

In `refreshDeviceStatus()` (lines ~319-328), replace the `transport` local and the three calls:

```swift
        if multi {
            verifyAndRenderRow(slot: 1, device: detected.device,
                               label: configStatusLabel, button: programButton)
            renderExtraSlotRows(device: detected.device)
        } else {
            clearExtraSlotRows()
            verifyAndRenderRow(slot: 1, device: detected.device,
                               label: configStatusLabel, button: programButton)
        }
```

(Delete the now-unused `let transport: Transport = ...` line at ~319.)

- [ ] **Step 4: Update `renderExtraSlotRows`**

Replace its signature (line ~372) and the inner verify call (line ~389):

```swift
    private func renderExtraSlotRows(device: SupportedDevice) {
```
```swift
            verifyAndRenderRow(slot: slot, device: device, label: status, button: button)
```

- [ ] **Step 5: Resolve the device in `programSlot`**

Replace the guard + key lines in `programSlot(_:button:)` (lines ~446-448) with:

```swift
        guard let detected = FootswitchHIDController.detect() else { return }
        let transport = detected.device.program.transport
        let key = keyForSlot(slot, device: detected.device)
```

(The rest — `combo`, off-main `program`, success/BLE alert, refresh — is unchanged.)

- [ ] **Step 6: Remove the now-unused `currentTransport()`**

Delete the `currentTransport()` method (lines ~291-299); its only caller was `programSlot`, now updated. (Verify no other references remain: `rg -n "currentTransport" Sources/Footswitch`.)

- [ ] **Step 7: Build the whole project**

Run: `swift build`
Expected: Build succeeds (app target now consistent with the new core API).

- [ ] **Step 8: Commit**

```bash
git add Sources/Footswitch/SettingsView.swift
git commit -m "feat: Settings resolves trigger keys per connected device (#9)"
```

---

### Task 6: Full build, test, and verification

**Files:** none (verification + final commit if needed).

- [ ] **Step 1: Full build**

Run: `swift build`
Expected: Build succeeds, no new warnings (watch for an "unused `currentTransport`" or leftover `triggers` reference — fix if present).

- [ ] **Step 2: Full test suite**

Run: `swift test`
Expected: All tests pass, including `DeviceTests`, `SupportedDevicesMatchTests`, `ConfigCodingTests`, `CustomDeviceTests` (legacy type retained), and `LocalizationParityTests` (no new strings expected).

- [ ] **Step 3: Migration smoke test (real config)**

Back up and inspect a real config migration:
```bash
cp ~/.footswitch/config.json /tmp/config.pre9.json   # if one exists
```
Run the app once (`swift run`), then confirm `~/.footswitch/config.json` now has a `devices` array (no `triggers`/`customDevices`) and your previous keys are preserved on the matching device. Delete the backup after confirming.

- [ ] **Step 4: Manual multi-device verification (real pedals)**

With a foot switch connected: open Settings, confirm the device row, per-slot verify status, and Program button behave as before (now resolved from `devices`). If you have an FS17Pro, confirm USB and Bluetooth each resolve their own entry's keys.

- [ ] **Step 5: Final commit (only if files changed during verification)**

```bash
git add -A
git commit -m "chore: per-device trigger config verification fixups (#9)"
```

---

## Self-Review

**Spec coverage:**
- `Device` model (identity + `[TriggerKey]`), replaces `CustomDevice` role → Task 1. ✓
- Transport derived from program family → Task 1 (`Program.transport`). ✓
- `Config.devices` replaces `triggers` + `customDevices`; `Triggers` removed from Config → Task 3. ✓
- Resolution: connected entry → code default; listener union; clamp via existing buildListener → Task 3 (helpers) + Task 4 (`listenerKeys`). ✓
- Lossless migration seeding all built-ins + customs, by transport family, custom-overrides-builtin, byte-stable → Task 3 (`migrateLegacy` + tests). ✓
- Encoder always writes `devices` so saved configs aren't re-migrated → Task 3. ✓
- Detection uses `devices` (`registeredDevices`, `match(devices:)`) → Tasks 2, 4. ✓
- UI resolves per connected device; device table otherwise hand-editable → Task 5. ✓
- `Device.adopting` ready for the #6 coupling → Task 1. ✓
- No new localized strings (config-only editing) → confirmed in Task 6 Step 2. ✓
- Runtime stays keycode→slot (no `RuleResolver`/dispatch change) → no task touches it. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; verification steps name exact commands. ✓

**Type consistency:** `Device(vendorId:productId:program:name:triggers:)`, `resolved()`, `adopting(key:slot:)`, `Program.transport`, `match(vendorID:productID:devices:)`, `Config.devices`/`triggerKey(forVendorID:productID:slot:)`/`listenerKeys`/`defaultTriggerKeys`, `registeredDevices`, `keyForSlot(_:device:)`, `verifyAndRenderRow(slot:device:label:button:)`, `renderExtraSlotRows(device:)` are consistent across Tasks 1–5. ✓

**Build-ordering note:** the app target is intentionally non-building between Tasks 3 and 5 (a core API change rippling into app consumers); core tests stay green throughout via `swift test`, and the full build is restored in Task 5 Step 7. This mirrors the constraint called out in the header.

> **#6 coupling:** when implementing the #6 Test-button plan after this, retarget its adopt path to `Device.adopting(key:slot:)` on the connected device entry and its `keyForSlot` to `Config.triggerKey(forVendorID:productID:slot:)` — both provided here. The #6 plan carries a pointer note.
