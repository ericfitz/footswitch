import Foundation

/// Retained only for legacy config decode/migration (issue #9); not part of the live config model.
///
/// Trigger keys grouped by transport. The FS17Pro (and similar) keeps a separate
/// key configuration for USB vs Bluetooth, so we store a list per transport. The
/// pedal listener watches the UNION across transports (any of them fires); the
/// programmer writes only the keys for the transport currently connected.
public struct Triggers: Codable, Equatable, Sendable {
    public var usb: [TriggerKey]
    public var bluetooth: [TriggerKey]

    public init(usb: [TriggerKey], bluetooth: [TriggerKey]) {
        self.usb = usb
        self.bluetooth = bluetooth
    }

    /// All trigger keys across every transport, de-duplicated by key name (the
    /// listener only needs each distinct keycode once). Used to build the listener.
    public var allKeys: [TriggerKey] {
        var seen = Set<String>()
        var result: [TriggerKey] = []
        for k in usb + bluetooth where seen.insert(k.key).inserted {
            result.append(k)
        }
        return result
    }
}
