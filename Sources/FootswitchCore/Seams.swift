import Foundation

/// Posts a synthesized keystroke (keyDown+keyUp) with the given modifier flag bits.
public protocol EventPosting: AnyObject {
    func postKeyStroke(keyCode: UInt16, flagBits: UInt64)
}

/// Runs a Shortcuts.app shortcut, fire-and-forget. Kept as a seam so FootswitchCore
/// stays IO-free and testable; the live implementation (which spawns
/// `/usr/bin/shortcuts`) lives in the app target.
public protocol ShortcutRunning: AnyObject {
    func run(_ ref: ShortcutRef)
}
