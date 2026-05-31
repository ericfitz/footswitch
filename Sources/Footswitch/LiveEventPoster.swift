import CoreGraphics
import FootswitchCore

final class LiveEventPoster: EventPosting {
    func postKeyStroke(keyCode: UInt16, flagBits: UInt64) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let flags = CGEventFlags(rawValue: flagBits)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cgSessionEventTap)
        }
    }
}
