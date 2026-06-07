import Foundation

/// A user-supplied device-table entry, letting a same-protocol foot switch be
/// recognized by editing config instead of changing code (GitHub issue #4).
///
/// VID/PID are stored as hex strings in JSON (e.g. `"0x245A"`) to match the
/// `ioreg`/USB convention users see; `program` names an existing protocol family.
/// `resolved()` validates and converts to a `SupportedDevice`, returning nil for
/// malformed IDs or an unknown program family — callers skip (and may log)
/// invalid entries rather than failing the whole config load.
public struct CustomDevice: Codable, Equatable, Sendable {
    public var vendorId: String
    public var productId: String
    public var program: String
    public var name: String

    public init(vendorId: String, productId: String, program: String, name: String) {
        self.vendorId = vendorId
        self.productId = productId
        self.program = program
        self.name = name
    }

    /// Parses a hex (`"0x245A"`, `"245a"`) or decimal-looking string into a USB ID.
    /// Returns nil if it isn't a valid 16-bit unsigned value. The `0x`/`0X` prefix
    /// is optional; bare strings are interpreted as **hex** (the USB convention),
    /// so "100" parses as 0x100, matching how the built-in table is written.
    static func parseID(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let body = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X")
            ? String(trimmed.dropFirst(2))
            : trimmed
        guard !body.isEmpty, let value = Int(body, radix: 16),
              (0x0000...0xFFFF).contains(value) else { return nil }
        return value
    }

    /// Validates the entry and converts it to a `SupportedDevice`, or nil if the
    /// VID/PID are malformed, the program family is unknown, or the name is blank.
    public func resolved() -> SupportedDevice? {
        guard let vid = Self.parseID(vendorId),
              let pid = Self.parseID(productId),
              let prog = SupportedDevice.Program(rawValue: program) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        return SupportedDevice(vendorID: vid, productID: pid, program: prog, name: trimmedName)
    }
}
