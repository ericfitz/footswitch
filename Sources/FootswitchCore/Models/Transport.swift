import Foundation

/// The connection a foot switch is currently using. The FS17Pro stores its key
/// configuration independently per transport, so trigger keys and programming are
/// keyed by transport.
public enum Transport: String, Codable, Equatable, Sendable, CaseIterable {
    case usb
    case bluetooth
}
