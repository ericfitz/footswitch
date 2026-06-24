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
