import XCTest
@testable import FootswitchCore

/// Covers the keycode + Carbon/Cocoa modifier-mask translation that turns a
/// `com.apple.symbolichotkeys` Dictation entry into a usable resolution (#15).
final class DictationHotkeyTests: XCTestCase {
    // Cocoa modifier bits (== Keymap flag bits): shift 1<<17, control 1<<18,
    // option 1<<19, command 1<<20.
    private let shift = 0x20000
    private let control = 0x40000
    private let option = 0x80000
    private let command = 0x100000
    private let fn = 0x800000
    private let capsLock = 0x10000

    func testDisabledEntryIsAbsent() {
        // The classic ⌃⌥⌘D combo, but the user switched the shortcut off.
        let params = [0x64, 0x02, control | option | command]
        XCTAssertEqual(DictationHotkey.resolve(enabled: false, parameters: params), .absent)
    }

    func testMissingOrShortParametersAreAbsent() {
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: nil), .absent)
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: []), .absent)
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: [0x64, 0x02]), .absent)
    }

    func testDefaultControlOptionCommandD() {
        // D = 0x02; mask = ⌃⌥⌘. Canonical modifier order is control, option, command.
        let params = [0x64, 0x02, control | option | command]
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: params),
                       .combo(KeyCombo(modifiers: [.control, .option, .command], key: "D")))
    }

    func testCommandShiftSpace() {
        // Space = 0x31; mask = ⌘⇧. Canonical order puts shift before command.
        let params = [0x20, 0x31, command | shift]
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: params),
                       .combo(KeyCombo(modifiers: [.shift, .command], key: "Space")))
    }

    func testFunctionKeyWithoutModifiersIsSynthesizable() {
        // F5 = 0x60 with no modifiers — a valid single-key dictation hotkey.
        let params = [0xFFFF, 0x60, 0]
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: params),
                       .combo(KeyCombo(modifiers: [], key: "F5")))
    }

    func testCapsLockAndFnBitsAreStripped() {
        // Stray Caps Lock / fn bits must not leak into the combo (we can't send
        // them anyway). Only ⌘ survives here.
        let params = [0x64, 0x02, command | fn | capsLock]
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: params),
                       .combo(KeyCombo(modifiers: [.command], key: "D")))
    }

    func testDoublePressIsUnsynthesizable() {
        // "Press Control twice": keyCode is the 0xFFFF sentinel — no key to send.
        let params = [0xFFFF, 0xFFFF, control]
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: params), .unsynthesizable)
    }

    func testUnknownKeycodeIsUnsynthesizable() {
        // A real keycode we have no name for can't be turned into a keystroke.
        let params = [0x00, 0x99, command]
        XCTAssertEqual(DictationHotkey.resolve(enabled: true, parameters: params), .unsynthesizable)
    }
}
