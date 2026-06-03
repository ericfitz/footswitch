import CoreGraphics
import Foundation
import FootswitchCore

/// Installs a session event tap, swallows any of the trigger keys, debounces each
/// independently, and invokes onFire (with the matched virtual keycode) on the main
/// thread. Re-enables itself if macOS disables it.
final class PedalListener {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let triggerKeyCodes: Set<UInt16>
    private var debouncers: [UInt16: Debouncer]
    private let onFire: @Sendable (UInt16) -> Void

    init(triggerKeys: [TriggerKey], debounceMs: Int, onFire: @escaping @Sendable (UInt16) -> Void) {
        var codes = triggerKeys.compactMap { Keymap.keyCode(for: $0.key) }
        if codes.isEmpty { codes = [0x69] }   // fall back to F13, preserving prior behavior
        self.triggerKeyCodes = Set(codes)
        self.debouncers = Dictionary(uniqueKeysWithValues:
            Set(codes).map { ($0, Debouncer(intervalMs: debounceMs)) })
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
        guard triggerKeyCodes.contains(keyCode) else {
            return Unmanaged.passUnretained(event)   // pass through everything else
        }
        // A trigger key: debounce that specific key, fire (with the matched code), swallow.
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var fired = false
        if var d = debouncers[keyCode] {
            fired = d.shouldFire(atMs: nowMs)
            debouncers[keyCode] = d           // write the mutated struct back
        } else {
            fired = true
        }
        if fired {
            let fire = onFire
            DispatchQueue.main.async { fire(keyCode) }
        }
        return nil   // swallow the trigger key so it never reaches the focused app
    }
}
