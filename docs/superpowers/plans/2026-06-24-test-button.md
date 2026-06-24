# Test Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-slot "Test" action in Settings that captures the key a pedal actually emits, compares it to config, and lets the user adopt the emitted key into config or reprogram the device.

**Architecture:** A transient *capture mode* on the existing `PedalListener` event tap grabs the next keydown and reports it (suspending normal dispatch). `AppDelegate` coordinates arming, a timeout, and deferral of listener rebuilds during capture, exposing two closures to the Settings window. The compare/decide logic is an IO-free core type (`TriggerReconciler` + `CapturedKey`), unit-tested; the Settings UI presents the armed state and outcome via sheets and adopts the captured key onto the **connected device's entry** via the pure `Config.adoptingTriggerKey(in:key:slot:for:)` helper (the #9 per-device model).

**Tech Stack:** Swift 6, AppKit, CoreGraphics event taps, Swift Package Manager. Spec: `docs/superpowers/specs/2026-06-24-test-button-design.md`.

> **PREREQUISITE — #9 first:** This plan is coordinated with the #9 per-device design (`docs/superpowers/specs/2026-06-24-per-device-trigger-config-design.md`), which **removes global `Config.triggers`** in favor of per-`Device` trigger lists. **#9 must be implemented before this plan.** This plan therefore builds on #9's `Device` model, `Config.defaultTriggerKeys`, `Config.triggerKey(in:forVendorID:productID:slot:)`, `Device.adopting`, and the per-device `SettingsView.keyForSlot(_:device:)` / `programSlot` that resolve via `FootswitchHIDController.detect()`. There is no global `triggers` and no `currentTransport()` helper. The reconciliation core (`TriggerReconciler`, `CapturedKey`) is independent of all this.

## Global Constraints

- Swift 6 strict concurrency; UI types are `@MainActor`. Cross-thread callbacks hop to main via `DispatchQueue.main.async`, matching existing `PedalListener.onFire`.
- Settings has **no Save button** — every mutation calls `onSave(config)`, which routes to `AppDelegate.reload` (persists + rebuilds the listener).
- Adopted/trigger key names must be **Keymap-recognized** (`Keymap.keyName(forCode:)` / `Keymap.keyCode(for:)`) so they round-trip through the listener and programming.
- Trigger config is **per-device** (#9): each `Device` entry owns its `[TriggerKey]`. Adopt mutates the **connected device's** entry (found by VID/PID, created if absent); there is no global `triggers` and no per-transport split.
- Modifier/combo capture is **out of scope** (deferred to issue #10): capture records a single keycode and ignores modifier flags.
- New user-facing strings must be added across **all 30 locales** with matching keys and placeholder arity; `LocalizationParityTests` must stay green.
- Build/test commands: `swift build` and `swift test`. There is no SwiftLint config in this repo.

---

### Task 1: Core — `CapturedKey` + `TriggerReconciler`

**Files:**
- Create: `Sources/FootswitchCore/TriggerReconciler.swift`
- Test: `Tests/FootswitchCoreTests/TriggerReconcilerTests.swift`

**Interfaces:**
- Consumes: `Keymap.keyName(forCode:)` (existing).
- Produces:
  - `enum CapturedKey: Equatable, Sendable { case named(String); case unknown(UInt16); case none; static func from(keyCode: UInt16) -> CapturedKey }`
  - `enum TriggerReconciliation: Equatable, Sendable { case match(key: String); case mismatch(captured: String, expected: String); case unknown(code: UInt16, expected: String); case noKey }`
  - `enum TriggerReconciler { static func reconcile(captured: CapturedKey, expected: String) -> TriggerReconciliation }`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/FootswitchCoreTests/TriggerReconcilerTests.swift
import XCTest
@testable import FootswitchCore

final class TriggerReconcilerTests: XCTestCase {
    func testFromKnownKeyCode() {
        XCTAssertEqual(CapturedKey.from(keyCode: 0x69), .named("F13"))
    }

    func testFromUnknownKeyCode() {
        // 0x6E has no entry in Keymap.table.
        XCTAssertEqual(CapturedKey.from(keyCode: 0x6E), .unknown(0x6E))
    }

    func testReconcileMatchIsCaseInsensitive() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named("f13"), expected: "F13"),
            .match(key: "f13"))
    }

    func testReconcileMismatch() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .named("F19"), expected: "F16"),
            .mismatch(captured: "F19", expected: "F16"))
    }

    func testReconcileUnknown() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .unknown(0x6E), expected: "F16"),
            .unknown(code: 0x6E, expected: "F16"))
    }

    func testReconcileNoKey() {
        XCTAssertEqual(
            TriggerReconciler.reconcile(captured: .none, expected: "F16"),
            .noKey)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TriggerReconcilerTests`
Expected: FAIL — "cannot find 'CapturedKey' / 'TriggerReconciler' in scope".

- [ ] **Step 3: Write the implementation**

```swift
// Sources/FootswitchCore/TriggerReconciler.swift
import Foundation

/// The key a pedal actually emitted during a Settings "Test", resolved against the
/// app's key table. `named` carries a Keymap-recognized name (round-trips through
/// programming + the listener); `unknown` carries a raw virtual key code we have no
/// name for (can be shown but not adopted); `none` means nothing was captured
/// (timeout or cancel).
public enum CapturedKey: Equatable, Sendable {
    case named(String)
    case unknown(UInt16)
    case none

    /// Resolves a raw macOS virtual key code into a `CapturedKey` via `Keymap`.
    public static func from(keyCode: UInt16) -> CapturedKey {
        if let name = Keymap.keyName(forCode: keyCode) { return .named(name) }
        return .unknown(keyCode)
    }
}

/// The outcome of comparing a captured key to the configured (expected) trigger key.
/// Drives the Settings UI: `match` is a green confirmation; `mismatch` offers
/// adopt-or-reprogram; `unknown` offers reprogram only (no name to adopt); `noKey`
/// is a timeout/cancel no-op.
public enum TriggerReconciliation: Equatable, Sendable {
    case match(key: String)
    case mismatch(captured: String, expected: String)
    case unknown(code: UInt16, expected: String)
    case noKey
}

public enum TriggerReconciler {
    /// Compares a captured key to the `expected` configured key name
    /// (case-insensitive, matching how `Keymap` resolves names).
    public static func reconcile(captured: CapturedKey, expected: String) -> TriggerReconciliation {
        switch captured {
        case .none:
            return .noKey
        case .unknown(let code):
            return .unknown(code: code, expected: expected)
        case .named(let name):
            if name.compare(expected, options: .caseInsensitive) == .orderedSame {
                return .match(key: name)
            }
            return .mismatch(captured: name, expected: expected)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TriggerReconcilerTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/TriggerReconciler.swift Tests/FootswitchCoreTests/TriggerReconcilerTests.swift
git commit -m "feat: core capture/reconcile types for Test button (#6)"
```

---

### Task 2: Core — per-device adopt + resolve helpers

> Builds on #9: uses `Device`, `Config.devices`, `Config.defaultTriggerKeys`, `Device.adopting`, `SupportedDevice`. #9 must be implemented first.

**Files:**
- Modify: `Sources/FootswitchCore/Models/Config.swift` (append extension)
- Test: `Tests/FootswitchCoreTests/ConfigAdoptTests.swift`

**Interfaces:**
- Consumes: `Device`, `Config.devices`, `Config.defaultTriggerKeys`, `Device.adopting(key:slot:)`, `SupportedDevice` (all from #9).
- Produces two pure statics on `Config`:
  - `static func triggerKey(in devices: [Device], forVendorID: Int, productID: Int, slot: Int) -> String`
  - `static func adoptingTriggerKey(in devices: [Device], key: String, slot: Int, for supported: SupportedDevice) -> [Device]`

These statics operate on a `[Device]` so the Settings UI can resolve/mutate its live working array without rebuilding a whole `Config`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/FootswitchCoreTests/ConfigAdoptTests.swift
import XCTest
@testable import FootswitchCore

final class ConfigAdoptTests: XCTestCase {
    private let fs17proBLE = SupportedDevice(vendorID: 0x245A, productID: 0x8276,
                                             program: .footswitchBLE, name: "FS17Pro")

    func testResolveEntryThenDefault() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1)])]
        XCTAssertEqual(Config.triggerKey(in: devices, forVendorID: 0x245A, productID: 0x8276, slot: 1), "F16")
        // Unknown device → code default for the slot.
        XCTAssertEqual(Config.triggerKey(in: devices, forVendorID: 0x1111, productID: 0x2222, slot: 2), "F14")
    }

    func testAdoptUpdatesExistingEntry() {
        let devices = [Device(vendorId: "0x245A", productId: "0x8276",
                              program: "footswitchBLE", name: "FS17Pro",
                              triggers: [TriggerKey(key: "F16", slot: 1)])]
        let out = Config.adoptingTriggerKey(in: devices, key: "F19", slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1)])
    }

    func testAdoptSeedsEntryWhenConnectedDeviceHasNone() {
        let out = Config.adoptingTriggerKey(in: [], key: "F19", slot: 1, for: fs17proBLE)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].resolved()?.vendorID, 0x245A)
        XCTAssertEqual(out[0].program, "footswitchBLE")
        XCTAssertEqual(out[0].triggers, [TriggerKey(key: "F19", slot: 1)])
    }

    func testAdoptRoundTripsThroughConfigCoding() throws {
        var config = Config.default
        config.devices = Config.adoptingTriggerKey(in: config.devices, key: "F19", slot: 1, for: fs17proBLE)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded.triggerKey(forVendorID: 0x245A, productID: 0x8276, slot: 1), "F19")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigAdoptTests`
Expected: FAIL — "type 'Config' has no member 'adoptingTriggerKey'".

- [ ] **Step 3: Write the implementation**

Append to `Sources/FootswitchCore/Models/Config.swift`:

```swift
extension Config {
    /// Resolves a connected device's slot key from a `devices` array: the matching
    /// entry's non-empty triggers, else `defaultTriggerKeys`. Mirrors the instance
    /// `triggerKey(forVendorID:productID:slot:)` but works on a bare array so the
    /// Settings UI can resolve its live working copy.
    public static func triggerKey(in devices: [Device], forVendorID vid: Int,
                                  productID pid: Int, slot: Int) -> String {
        let entry = devices.first {
            $0.resolved().map { $0.vendorID == vid && $0.productID == pid } ?? false
        }
        let keys = (entry.map { !$0.triggers.isEmpty } ?? false) ? entry!.triggers : defaultTriggerKeys
        return keys.first { $0.slot == slot }?.key
            ?? keys.first?.key
            ?? defaultTriggerKeys[0].key
    }

    /// Returns `devices` with `key` set for `slot` on the entry matching `supported`
    /// (by VID/PID): updates the existing entry via `Device.adopting`, or appends a
    /// new entry seeded from `supported` when none exists yet (e.g. a fresh config
    /// whose connected device has no entry). Used by the #6 Test-button adopt path.
    public static func adoptingTriggerKey(in devices: [Device], key: String, slot: Int,
                                          for supported: SupportedDevice) -> [Device] {
        var copy = devices
        if let i = copy.firstIndex(where: {
            $0.resolved().map { $0.vendorID == supported.vendorID
                              && $0.productID == supported.productID } ?? false
        }) {
            copy[i] = copy[i].adopting(key: key, slot: slot)
        } else {
            copy.append(Device(
                vendorId: String(format: "0x%04X", supported.vendorID),
                productId: String(format: "0x%04X", supported.productID),
                program: supported.program.rawValue, name: supported.name,
                triggers: [TriggerKey(key: key, slot: slot)]))
        }
        return copy
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfigAdoptTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/FootswitchCore/Models/Config.swift Tests/FootswitchCoreTests/ConfigAdoptTests.swift
git commit -m "feat: per-device adopt/resolve helpers for Test button (#6)"
```

---

### Task 3: App — `PedalListener` capture mode

**Files:**
- Modify: `Sources/Footswitch/PedalListener.swift`

**Interfaces:**
- Produces: `func beginCapture(onCapture: @escaping (UInt16) -> Void)` and `func endCapture()` on `PedalListener`. When armed, the next keydown is reported (on main) and swallowed; normal slot dispatch is suspended for that event.

This is event-tap glue with no unit test; verify by build. The capture branch sits after the tap-disabled re-enable and before the slot lookup.

- [ ] **Step 1: Add the capture state + methods**

Insert after the `onFire` stored property (around line 13):

```swift
    /// While non-nil, the next keydown of any key is captured (reported via this
    /// handler on the main thread) and swallowed, instead of the normal slot
    /// dispatch — used by the Settings "Test" flow to learn what the pedal really
    /// emits. One-shot: cleared after a capture or via `endCapture()`.
    private var captureHandler: ((UInt16) -> Void)?

    /// Arms one-shot capture of the next keydown. Replaces any prior arming.
    func beginCapture(onCapture: @escaping (UInt16) -> Void) { captureHandler = onCapture }

    /// Disarms capture without firing (cancel/timeout from the caller).
    func endCapture() { captureHandler = nil }
```

- [ ] **Step 2: Add the capture branch in `handle(type:event:)`**

Replace the body from the `keyCode` line through the slot guard (current lines 72-75) with:

```swift
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if let capture = captureHandler {
            captureHandler = nil                  // one-shot
            DispatchQueue.main.async { capture(keyCode) }
            return nil                            // swallow; suspend normal dispatch
        }
        guard let slot = keyCodeToSlot[keyCode] else {
            return Unmanaged.passUnretained(event)   // pass through everything else
        }
```

(The tap-disabled re-enable block above stays unchanged; the rest of `handle` — debounce + fire + `return nil` — stays unchanged.)

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/Footswitch/PedalListener.swift
git commit -m "feat: one-shot capture mode on PedalListener (#6)"
```

---

### Task 4: App — `AppDelegate` capture coordination + window wiring

**Files:**
- Modify: `Sources/Footswitch/AppDelegate.swift`
- Modify: `Sources/Footswitch/SettingsView.swift` (factory signature only)

**Interfaces:**
- Consumes: `PedalListener.beginCapture/endCapture` (Task 3), `CapturedKey.from(keyCode:)` (Task 1).
- Produces: `SettingsWindowFactory.make(store:onSave:beginCapture:cancelCapture:)` where
  `beginCapture: (_ timeoutMs: Int, _ completion: @escaping (CapturedKey) -> Void) -> Void`
  and `cancelCapture: () -> Void`.

- [ ] **Step 1: Add capture state to `AppDelegate`**

Insert after `private var rebuildWorkItem: DispatchWorkItem?` (line 23):

```swift
    private var isCapturing = false
    private var pendingRebuildAfterCapture = false
    private var captureTimeoutWork: DispatchWorkItem?
```

- [ ] **Step 2: Add capture methods to `AppDelegate`**

Insert after `handlePress(slot:)` (after line 90):

```swift
    /// Arms the live listener to capture the next keydown for the Settings "Test"
    /// flow, with a timeout. `completion` runs on the main thread with the resolved
    /// `CapturedKey` (or `.none` on timeout). Listener rebuilds requested during
    /// capture are deferred so the capturing listener isn't swapped out mid-test.
    private func beginCapture(timeoutMs: Int, completion: @escaping (CapturedKey) -> Void) {
        captureTimeoutWork?.cancel()
        isCapturing = true
        listener.beginCapture { [weak self] keyCode in
            guard let self else { return }
            self.finishCapture()
            completion(CapturedKey.from(keyCode: keyCode))
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturing else { return }
            self.finishCapture()
            completion(.none)
        }
        captureTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: work)
    }

    /// Cancels an in-flight capture without invoking the completion (the UI that
    /// asked to cancel already knows). Safe to call when not capturing.
    private func cancelCapture() {
        guard isCapturing else { return }
        finishCapture()
    }

    private func finishCapture() {
        isCapturing = false
        captureTimeoutWork?.cancel()
        captureTimeoutWork = nil
        listener?.endCapture()
        if pendingRebuildAfterCapture {
            pendingRebuildAfterCapture = false
            buildListener()
        }
    }
```

- [ ] **Step 3: Defer rebuilds during capture**

In `scheduleListenerRebuild()`, replace the work item body (current lines 113-119) with:

```swift
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isCapturing {
                // Don't swap out the capturing listener or clear the test UI mid-test;
                // run the rebuild when capture finishes.
                self.pendingRebuildAfterCapture = true
                return
            }
            self.buildListener()
            NotificationCenter.default.post(name: .footswitchDeviceChanged, object: nil)
        }
```

- [ ] **Step 4: Pass the capture closures when creating the Settings window**

In `showSettings()`, replace the `SettingsWindowFactory.make(...)` call (lines 126-128) with:

```swift
            settingsWindow = SettingsWindowFactory.make(
                store: store,
                onSave: { [weak self] newConfig in self?.reload(newConfig) },
                beginCapture: { [weak self] timeoutMs, completion in
                    self?.beginCapture(timeoutMs: timeoutMs, completion: completion)
                },
                cancelCapture: { [weak self] in self?.cancelCapture() })
```

- [ ] **Step 5: Update the factory signature**

In `Sources/Footswitch/SettingsView.swift`, replace `SettingsWindowFactory.make` (lines 10-19) with:

```swift
    @MainActor
    static func make(store: ConfigStore,
                     onSave: @escaping (Config) -> Void,
                     beginCapture: @escaping (_ timeoutMs: Int, _ completion: @escaping (CapturedKey) -> Void) -> Void,
                     cancelCapture: @escaping () -> Void) -> NSWindow {
        let config = (try? store.load()) ?? .default
        let controller = SettingsViewController(config: config, onSave: onSave,
                                                beginCapture: beginCapture, cancelCapture: cancelCapture)
        let window = NSWindow(contentViewController: controller)
        window.title = L10n.settingsWindowTitle
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 460))
        return window
    }
```

(The `SettingsViewController` initializer is updated in Task 5; the project will not build until then — that is expected. Build at the end of Task 5.)

- [ ] **Step 6: Commit**

```bash
git add Sources/Footswitch/AppDelegate.swift Sources/Footswitch/SettingsView.swift
git commit -m "feat: AppDelegate capture coordination + window wiring (#6)"
```

---

### Task 5: App — Settings device state + adopt save path

> Builds on #9's `SettingsView`, where `keyForSlot(_ slot:device:)` resolves from `baseConfig` and there is no global `triggers`. This task gives the controller a **live `devices` array** so an adopted key is reflected immediately.

**Files:**
- Modify: `Sources/Footswitch/SettingsView.swift`

**Interfaces:**
- Consumes: factory closures from Task 4; `Config.triggerKey(in:forVendorID:productID:slot:)` (Task 2).
- Produces: `SettingsViewController.init(config:onSave:beginCapture:cancelCapture:)`; stored `devices`, `beginCaptureFn`, `cancelCaptureFn`; `save()` persists `devices`; `keyForSlot(_:device:)` reads the live `devices`.

- [ ] **Step 1: Add stored properties**

After `private let onSave: (Config) -> Void`, add:

```swift
    private var devices: [Device]
    private let beginCaptureFn: (_ timeoutMs: Int, _ completion: @escaping (CapturedKey) -> Void) -> Void
    private let cancelCaptureFn: () -> Void
```

- [ ] **Step 2: Update the initializer**

Replace the (#9) initializer with:

```swift
    init(config: Config,
         onSave: @escaping (Config) -> Void,
         beginCapture: @escaping (_ timeoutMs: Int, _ completion: @escaping (CapturedKey) -> Void) -> Void,
         cancelCapture: @escaping () -> Void) {
        self.baseConfig = config
        self.rules = config.rules
        self.defaultAction = config.defaultAction
        self.devices = config.devices
        self.onSave = onSave
        self.beginCaptureFn = beginCapture
        self.cancelCaptureFn = cancelCapture
        super.init(nibName: nil, bundle: nil)
    }
```

- [ ] **Step 3: Persist devices on save**

Replace `save()` with:

```swift
    private func save() {
        var config = baseConfig
        config.rules = rules
        config.defaultAction = defaultAction
        config.devices = devices
        onSave(config)
    }
```

- [ ] **Step 4: Read the live device state in `keyForSlot`**

Replace the (#9) `keyForSlot(_:device:)` with one that reads the controller's live `devices` (so an adopted key shows immediately) instead of `baseConfig`:

```swift
    /// The configured trigger key for a slot on the connected `device` (its entry's
    /// keys, else the code default), read from the live `devices` so an adopted key
    /// is reflected immediately.
    private func keyForSlot(_ slot: Int, device: SupportedDevice) -> String {
        Config.triggerKey(in: devices, forVendorID: device.vendorID,
                          productID: device.productID, slot: slot)
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds (factory + controller now agree).

- [ ] **Step 6: Commit**

```bash
git add Sources/Footswitch/SettingsView.swift
git commit -m "feat: Settings holds live devices + adopt-aware save (#6)"
```

---

### Task 6: App — Test button UI + interaction

**Files:**
- Modify: `Sources/Footswitch/SettingsView.swift`

**Interfaces:**
- Consumes: `beginCaptureFn`, `cancelCaptureFn`, `devices`, `keyForSlot(_:device:)`, `programSlot`, `refreshDeviceStatus`, `FootswitchHIDController.detect()`, `TriggerReconciler.reconcile`, `Config.adoptingTriggerKey(in:key:slot:for:)`; new L10n accessors from Task 7.
- Produces: a `[Test]` button on slot 1 and each extra slot row; armed-state sheet; outcome sheet with adopt / reprogram.

> Note: while the armed sheet is up, the window is sheet-blocked, so other buttons can't be clicked — no separate enable/disable bookkeeping is needed. The global capture swallows the keydown, so pressing **Escape** is captured as a key (it won't dismiss the sheet); the user cancels with the mouse. This is an accepted minor limitation.

- [ ] **Step 1: Add the slot-1 Test button property**

After `private var programButton: NSButton!` (line 44), add:

```swift
    private var testButton: NSButton!
    private var activeTestSlot: Int?
```

- [ ] **Step 2: Add the Test button to the slot-1 config row**

In `buildUI()`, replace the `configRow` construction (lines 146-151) with:

```swift
        programButton = NSButton(title: L10n.settingsProgramButton,
                                 target: self, action: #selector(programPedal))
        programButton.bezelStyle = .rounded
        testButton = NSButton(title: L10n.settingsTestButton,
                              target: self, action: #selector(testPedal))
        testButton.bezelStyle = .rounded
        configRow = NSStackView(views: [configStatusLabel, programButton, testButton])
        configRow.orientation = .horizontal
        configRow.spacing = 12
```

- [ ] **Step 3: Add a Test button to each extra slot row**

In the (#9) `renderExtraSlotRows(device:)`, replace the row assembly with (note the trailing call uses the #9 `device:` signature):

```swift
            let button = NSButton(title: L10n.settingsProgramButton,
                                  target: self, action: #selector(programSlotButton(_:)))
            button.bezelStyle = .rounded
            button.tag = slot
            let test = NSButton(title: L10n.settingsTestButton,
                                target: self, action: #selector(testSlotButton(_:)))
            test.bezelStyle = .rounded
            test.tag = slot
            let prefix = NSTextField(labelWithString: L10n.deviceSlotLabel(slot) + ":")
            prefix.font = .systemFont(ofSize: 12)
            let row = NSStackView(views: [prefix, status, button, test])
            row.orientation = .horizontal
            row.spacing = 8
            deviceSection.addArrangedSubview(row)
            extraSlotRows.append(row)
            verifyAndRenderRow(slot: slot, device: device, label: status, button: button)
```

- [ ] **Step 4: Make `programSlot` accept an optional button**

Replace the `programSlot(_:button:)` signature line (line 440) and its `button.isEnabled = false` line (line 449), and the re-enable line (line 462):

```swift
    private func programSlot(_ slot: Int, button: NSButton?) {
```
```swift
        button?.isEnabled = false
```
```swift
                button?.isEnabled = true
```

(The two existing callers — `programPedal()` and `programSlotButton(_:)` — still pass non-nil and keep working.)

- [ ] **Step 5: Add the test action handlers + flow**

Insert after `programSlot(_:button:)` (after line 467):

```swift
    @objc private func testPedal() { startTest(slot: 1) }

    @objc private func testSlotButton(_ sender: NSButton) { startTest(slot: sender.tag) }

    /// Arms capture for `slot`, shows a cancelable "press the pedal" sheet, and on
    /// completion presents the reconciliation outcome. Gated on a connected device
    /// (resolved via detect()); no-ops otherwise (matches the Program button).
    private func startTest(slot: Int) {
        guard activeTestSlot == nil,
              let detected = FootswitchHIDController.detect(),
              let window = view.window else { return }
        let device = detected.device
        activeTestSlot = slot

        let armed = NSAlert()
        armed.messageText = L10n.alertTestTitle
        armed.informativeText = L10n.testPrompt(slot: slot)
        armed.addButton(withTitle: L10n.alertCancel)
        armed.beginSheetModal(for: window) { [weak self] _ in
            // Sheet dismissed. If still armed, it was a user Cancel — stop capture.
            guard let self, self.activeTestSlot == slot else { return }
            self.activeTestSlot = nil
            self.cancelCaptureFn()
            self.refreshDeviceStatus()
        }

        beginCaptureFn(15_000) { [weak self] captured in
            guard let self, self.activeTestSlot == slot else { return }
            self.activeTestSlot = nil
            // Dismiss the armed sheet before showing the result.
            if let sheet = self.view.window?.attachedSheet {
                self.view.window?.endSheet(sheet)
            }
            let expected = self.keyForSlot(slot, device: device)
            let outcome = TriggerReconciler.reconcile(captured: captured, expected: expected)
            self.presentTestOutcome(outcome, slot: slot, device: device)
        }
    }

    private func presentTestOutcome(_ outcome: TriggerReconciliation, slot: Int,
                                    device: SupportedDevice) {
        refreshDeviceStatus()   // restore the normal row UI under the outcome sheet
        let alert = NSAlert()
        alert.messageText = L10n.alertTestTitle
        switch outcome {
        case .match(let key):
            alert.informativeText = L10n.testMatch(key: key)
            alert.addButton(withTitle: L10n.alertOK)
            runOutcome(alert) { _ in }
        case .mismatch(let captured, let expected):
            alert.informativeText = L10n.testMismatch(captured: captured, expected: expected)
            alert.addButton(withTitle: L10n.testUseKey(key: captured))     // first
            alert.addButton(withTitle: L10n.testReprogram(key: expected))  // second
            alert.addButton(withTitle: L10n.alertCancel)                   // third
            runOutcome(alert) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    self?.adopt(key: captured, slot: slot, device: device)
                } else if resp == .alertSecondButtonReturn {
                    self?.reprogram(slot: slot)
                }
            }
        case .unknown(let code, let expected):
            alert.informativeText = L10n.testUnknown(
                code: String(format: "0x%02X", code), expected: expected)
            alert.addButton(withTitle: L10n.testReprogram(key: expected))  // first
            alert.addButton(withTitle: L10n.alertCancel)                   // second
            runOutcome(alert) { [weak self] resp in
                if resp == .alertFirstButtonReturn { self?.reprogram(slot: slot) }
            }
        case .noKey:
            alert.informativeText = L10n.testNoKey
            alert.addButton(withTitle: L10n.alertOK)
            runOutcome(alert) { _ in }
        }
    }

    /// Adopts the emitted key onto the connected device's entry (find-or-create),
    /// persists, and re-verifies. Save routes to AppDelegate.reload, which rebuilds
    /// the listener from `Config.listenerKeys` so the new key is caught immediately —
    /// no reprogramming, no power-cycle.
    private func adopt(key: String, slot: Int, device: SupportedDevice) {
        devices = Config.adoptingTriggerKey(in: devices, key: key, slot: slot, for: device)
        save()
        refreshDeviceStatus()
    }

    private func reprogram(slot: Int) {
        programSlot(slot, button: slot == 1 ? programButton : nil)
    }

    private func runOutcome(_ alert: NSAlert,
                            handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. (L10n accessors are added in Task 7; if building this task before Task 7, temporarily expect "cannot find 'L10n.settingsTestButton'" — do Task 7 first or together. Recommended order: do Task 7 before this build.)

- [ ] **Step 7: Commit**

```bash
git add Sources/Footswitch/SettingsView.swift
git commit -m "feat: per-slot Test button UI + adopt/reprogram flow (#6)"
```

---

### Task 7: Localization — new strings across all 30 locales

**Files:**
- Modify: `Sources/Footswitch/L10n.swift`
- Modify: `Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings`
- Modify: the other 29 `Sources/Footswitch/Resources/Localizations/*.lproj/Localizable.strings`
- Test: `Tests/FootswitchCoreTests/LocalizationParityTests.swift` (existing — must stay green)

**Interfaces:**
- Produces L10n accessors consumed by Task 6: `settingsTestButton`, `alertTestTitle`, `testPrompt(slot:)`, `testMatch(key:)`, `testMismatch(captured:expected:)`, `testUnknown(code:expected:)`, `testNoKey`, `testUseKey(key:)`, `testReprogram(key:)`, `alertCancel`.

- [ ] **Step 1: Add the L10n accessors**

Insert into `L10n.swift` before the `// About` section (before line 121):

```swift
    // Pedal test (issue #6)
    static var settingsTestButton: String { t("settings.testButton", "Button: test what key the pedal emits.") }
    static var alertTestTitle: String { t("alert.test.title", "Test-pedal alert title.") }
    /// %@ = pedal number.
    static func testPrompt(slot: Int) -> String {
        String(format: t("test.prompt", "Armed prompt while waiting for a pedal press. %@ = pedal number."), "\(slot)")
    }
    /// %@ = key name.
    static func testMatch(key: String) -> String {
        String(format: t("test.match", "Result: emitted key matches config. %@ = key."), key)
    }
    /// %1$@ = emitted key, %2$@ = expected key.
    static func testMismatch(captured: String, expected: String) -> String {
        String(format: t("test.mismatch", "Result: emitted key differs. %1$@ emitted, %2$@ expected."), captured, expected)
    }
    /// %1$@ = raw key code, %2$@ = expected key.
    static func testUnknown(code: String, expected: String) -> String {
        String(format: t("test.unknown", "Result: emitted an unrecognized key. %1$@ code, %2$@ expected."), code, expected)
    }
    static var testNoKey: String { t("test.noKey", "Result: nothing captured (timeout/cancel).") }
    /// %@ = key to adopt.
    static func testUseKey(key: String) -> String {
        String(format: t("test.useKey", "Button: adopt the emitted key into config. %@ = key."), key)
    }
    /// %@ = expected key to program.
    static func testReprogram(key: String) -> String {
        String(format: t("test.reprogram", "Button: reprogram device to the configured key. %@ = key."), key)
    }
    static var alertCancel: String { t("alert.cancel", "Generic Cancel button.") }
```

- [ ] **Step 2: Add the English strings (authoritative)**

Append to `Sources/Footswitch/Resources/Localizations/en.lproj/Localizable.strings`:

```
/* Button: test what key the pedal emits. */
"settings.testButton" = "Test";

/* Test-pedal alert title. */
"alert.test.title" = "Test pedal";

/* Armed prompt while waiting for a pedal press. %@ = pedal number. */
"test.prompt" = "Press pedal %@ now…";

/* Result: emitted key matches config. %@ = key. */
"test.match" = "Pedal emits %@ — matches your configuration.";

/* Result: emitted key differs. %1$@ emitted, %2$@ expected. */
"test.mismatch" = "Pedal emits %1$@, but your configuration expects %2$@.";

/* Result: emitted an unrecognized key. %1$@ code, %2$@ expected. */
"test.unknown" = "Pedal emits an unrecognized key (%1$@). Your configuration expects %2$@.";

/* Result: nothing captured (timeout/cancel). */
"test.noKey" = "No key detected — is the pedal connected and pressed?";

/* Button: adopt the emitted key into config. %@ = key. */
"test.useKey" = "Use %@";

/* Button: reprogram device to the configured key. %@ = key. */
"test.reprogram" = "Reprogram to %@";

/* Generic Cancel button. */
"alert.cancel" = "Cancel";
```

- [ ] **Step 3: Propagate the 10 keys to the other 29 locales**

Add the same 10 keys (same `/* comment */` headers, same placeholder arity) to every other `*.lproj/Localizable.strings`, with translated values. Use the `loc:backfill` skill to translate from `en` (it reads the project i18n layout and fills missing keys), then spot-check that placeholders (`%@`, `%1$@`, `%2$@`) are preserved verbatim in each value.

Reference — locales to cover (29 besides `en`): ar, cs, da, de, el, en-GB, es, es-419, fr, fr-CA, he, id, it, ja, ko, nb, nl, pl, pt-BR, pt-PT, ru, sv, th, tr, uk, vi, zh-HK, zh-Hans, zh-Hant.

- [ ] **Step 4: Run the parity test**

Run: `swift test --filter LocalizationParityTests`
Expected: PASS — same keys and placeholder arity across all 30 locales.

- [ ] **Step 5: Commit**

```bash
git add Sources/Footswitch/L10n.swift Sources/Footswitch/Resources/Localizations
git commit -m "i18n: Test-button strings across all 30 locales (#6)"
```

---

### Task 8: Full build, test, and manual verification

**Files:** none (verification + final commit if anything was touched).

- [ ] **Step 1: Full build**

Run: `swift build`
Expected: Build succeeds, no warnings introduced.

- [ ] **Step 2: Full test suite**

Run: `swift test`
Expected: All tests pass, including `TriggerReconcilerTests`, `ConfigAdoptTests`, and `LocalizationParityTests`.

- [ ] **Step 3: Manual smoke test (requires a real pedal)**

Run the app (`swift run` or the packaged build). With a foot switch connected:
1. Open Settings. Confirm each detected slot row shows a **Test** button.
2. Click **Test**, press the pedal. Confirm:
   - matching key → "Pedal emits F… — matches" with an OK button;
   - different key → mismatch sheet with **Use …**, **Reprogram to …**, **Cancel**;
   - **Use** updates the row to verified against the new key without reprogramming;
   - **Cancel** in the armed sheet ends the test cleanly.
3. With no key pressed for 15s, confirm the "No key detected" result.
4. (BLE) After programming over Bluetooth without power-cycling, confirm Test reports the still-old emitted key and **Use** adopts it so presses work immediately.

- [ ] **Step 4: Final commit (only if files changed during verification)**

```bash
git add -A
git commit -m "chore: Test-button verification fixups (#6)"
```

---

## Self-Review

**Spec coverage:**
- Per-slot Test button → Task 6 (slot 1 + extra rows). ✓
- Capture mechanism = capture mode on PedalListener, 15s timeout, swallow, suspend dispatch → Tasks 3, 4. ✓
- Reconciliation match | mismatch | unknown | noKey → Task 1; UI presentation → Task 6. ✓
- Adopt onto the connected device's entry (find-or-create), rebuild listener → Tasks 2, 5, 6 (`Config.adoptingTriggerKey` + `save` → `reload` → `listenerKeys`). ✓
- Reprogram reuses existing program path with BLE power-cycle alert → Task 6 `reprogram` → existing `programSlot`. ✓
- Unknown key: show raw code, disable adopt, allow reprogram → Task 6 `.unknown` case. ✓
- Timeout / no-device gating → Task 4 timeout; Task 6 `FootswitchHIDController.detect()` guard + Test visible only when `configRow` shown. ✓
- Modifier/combo deferred to #10 → captured as single keycode, flags ignored (Task 3). ✓
- L10n across 30 locales + parity green → Task 7. ✓
- IO-free core unit-tested → Tasks 1, 2. ✓

**Edge cases from spec:**
- Collision warning ("F19 is also slot 1's key"): the spec calls this a *non-blocking* warning. This plan adopts without the extra inline warning to keep scope tight; the listener's existing "first writer wins per keycode" dedup still prevents misbehavior. If the warning is desired, it is a follow-up — note it at review rather than expanding this plan.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the only delegated step (Task 7 Step 3 translation) names a concrete tool (`loc:backfill`) and the exact key set/locales. ✓

**Type consistency:** `CapturedKey`, `TriggerReconciliation`, `TriggerReconciler.reconcile`, `Config.triggerKey(in:...)` / `Config.adoptingTriggerKey(in:...)`, `keyForSlot(_:device:)`, `beginCapture`/`cancelCapture`/`endCapture`, and the factory/init signatures match across Tasks 1–7 (and with the #9 `Device` model). ✓

> **Known limitation (documented in Task 6):** while armed, the global capture swallows Escape, so the armed sheet is cancel-by-mouse only. Combo capture is deferred to #10.
