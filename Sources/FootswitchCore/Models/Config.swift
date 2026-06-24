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
    private static func migrateLegacy(container c: KeyedDecodingContainer<CodingKeys>) -> [Device] {
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
        let keys = entry.flatMap { $0.triggers.isEmpty ? nil : $0.triggers } ?? defaultTriggerKeys
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
}
