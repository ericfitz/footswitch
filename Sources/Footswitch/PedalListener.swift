import CoreGraphics
import Foundation
import FootswitchCore

/// Installs a session event tap, swallows any of the trigger keys, debounces each
/// independently, and invokes onFire(slot:) on the main thread. Re-enables itself if
/// macOS disables it.
final class PedalListener {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let matcher: TriggerMatcher
    private var debouncers: [TriggerMatcher.Key: Debouncer]
    private let onFire: @Sendable (_ slot: Int) -> Void

    /// While non-nil, the next keydown is captured (keycode + masked modifier bits,
    /// reported on the main thread) and swallowed instead of the normal slot
    /// dispatch — the Settings "Test" flow. One-shot.
    private var captureHandler: (@Sendable (UInt16, UInt64) -> Void)?

    func beginCapture(onCapture: @escaping @Sendable (UInt16, UInt64) -> Void) { captureHandler = onCapture }
    func endCapture() { captureHandler = nil }

    init(triggerKeys: [TriggerKey], debounceMs: Int, onFire: @escaping @Sendable (_ slot: Int) -> Void) {
        let matcher = TriggerMatcher(triggerKeys: triggerKeys)
        self.matcher = matcher
        self.debouncers = Dictionary(uniqueKeysWithValues:
            matcher.keys.map { ($0, Debouncer(intervalMs: debounceMs)) })
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

    /// Disables the event tap and removes its run-loop source so the listener stops
    /// swallowing keys. Required before discarding a listener on rebuild (hot-plug /
    /// config save) — otherwise the old tap lingers and keeps eating its keys.
    /// Must be called on the same run loop `start()` ran on (the main thread).
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modBits = event.flags.rawValue & Keymap.deviceModifierMask
        if let capture = captureHandler {
            captureHandler = nil                          // one-shot
            DispatchQueue.main.async { capture(keyCode, modBits) }
            return nil                                    // swallow; suspend dispatch
        }
        guard let slot = matcher.slot(forKeyCode: keyCode, modBits: modBits) else {
            return Unmanaged.passUnretained(event)        // pass through everything else
        }
        let matchKey = TriggerMatcher.Key(keyCode: keyCode, modBits: modBits)
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var fired = false
        if var d = debouncers[matchKey] {
            fired = d.shouldFire(atMs: nowMs)
            debouncers[matchKey] = d
        } else {
            fired = true
        }
        if fired {
            let fire = onFire
            DispatchQueue.main.async { fire(slot) }
        }
        return nil   // swallow the trigger so it never reaches the focused app
    }
}
