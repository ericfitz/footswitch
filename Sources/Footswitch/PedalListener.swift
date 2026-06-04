import CoreGraphics
import Foundation
import FootswitchCore

/// Installs a session event tap, swallows any of the trigger keys, debounces each
/// independently, and invokes onFire(slot:) on the main thread. Re-enables itself if
/// macOS disables it.
final class PedalListener {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let keyCodeToSlot: [UInt16: Int]
    private var debouncers: [UInt16: Debouncer]
    private let onFire: @Sendable (_ slot: Int) -> Void

    /// `triggerKeys` are the keys to catch (already clamped to detected slots by the
    /// caller). Each key's `slot` (1-based) tags its fires. Keys that don't resolve
    /// to a keycode are skipped (that slot simply won't fire). On a fully-empty/
    /// unresolved set, fall back to catching F13 as slot 1 (prior behavior).
    init(triggerKeys: [TriggerKey], debounceMs: Int, onFire: @escaping @Sendable (_ slot: Int) -> Void) {
        var map: [UInt16: Int] = [:]
        for tk in triggerKeys {
            guard let code = Keymap.keyCode(for: tk.key) else { continue }
            // First writer wins per keycode (de-dup): a duplicate key can't map to
            // two slots, so the first one in the list (USB before Bluetooth) keeps it.
            if map[code] == nil { map[code] = tk.slot }
        }
        if map.isEmpty { map[0x69] = 1 }   // F13 / slot 1 fallback
        self.keyCodeToSlot = map
        self.debouncers = Dictionary(uniqueKeysWithValues:
            map.keys.map { ($0, Debouncer(intervalMs: debounceMs)) })
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
        guard let slot = keyCodeToSlot[keyCode] else {
            return Unmanaged.passUnretained(event)   // pass through everything else
        }
        // A trigger key: debounce that specific key, fire (with its slot), swallow.
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
            DispatchQueue.main.async { fire(slot) }
        }
        return nil   // swallow the trigger key so it never reaches the focused app
    }
}
