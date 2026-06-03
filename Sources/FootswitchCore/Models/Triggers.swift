import Foundation

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

    /// The trigger keys for a specific transport.
    public func keys(for transport: Transport) -> [TriggerKey] {
        switch transport {
        case .usb: return usb
        case .bluetooth: return bluetooth
        }
    }

    /// The primary (first) trigger key for a transport, or a F13/slot-1 fallback.
    /// Only `.key` is load-bearing for programming today: the programmers map the
    /// connected transport to a hardcoded pedal index (USB 0 / BLE 1), so `.slot`
    /// is carried for the future multi-button feature but not yet honored here.
    public func primary(for transport: Transport) -> TriggerKey {
        keys(for: transport).first ?? TriggerKey(key: "F13", slot: 1)
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
