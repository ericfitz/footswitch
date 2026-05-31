import Foundation

/// Posts a synthesized keystroke (keyDown+keyUp) with the given modifier flag bits.
public protocol EventPosting: AnyObject {
    func postKeyStroke(keyCode: UInt16, flagBits: UInt64)
}

/// Toggles hardware mute on the system default audio input device.
public protocol InputMuting: AnyObject {
    func toggleInputMute()
}
