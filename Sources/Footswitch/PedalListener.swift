import CoreGraphics
import Foundation
import FootswitchCore

/// Installs a session event tap, swallows the trigger key, debounces, and
/// invokes onFire on the main thread. Re-enables itself if macOS disables it.
final class PedalListener {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let triggerKeyCode: UInt16
    private var debouncer: Debouncer
    private let onFire: @Sendable () -> Void

    init(triggerKey: String, debounceMs: Int, onFire: @escaping @Sendable () -> Void) {
        self.triggerKeyCode = Keymap.keyCode(for: triggerKey) ?? 0x69 // default F13
        self.debouncer = Debouncer(intervalMs: debounceMs)
        self.onFire = onFire
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let listener = Unmanaged<PedalListener>.fromOpaque(refcon!).takeUnretainedValue()
            return listener.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == triggerKeyCode else {
            return Unmanaged.passUnretained(event)   // pass through everything else
        }
        // Our trigger key: debounce and fire, then swallow.
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        if debouncer.shouldFire(atMs: nowMs) {
            let fire = onFire
            DispatchQueue.main.async { fire() }
        }
        return nil   // swallow F13 so it never reaches the focused app
    }
}
