import XCTest
@testable import FootswitchCore

final class MockEventPoster: EventPosting {
    struct Posted: Equatable { let keyCode: UInt16; let flagBits: UInt64 }
    var posted: [Posted] = []
    func postKeyStroke(keyCode: UInt16, flagBits: UInt64) {
        posted.append(Posted(keyCode: keyCode, flagBits: flagBits))
    }
}

final class MockShortcutRunner: ShortcutRunning {
    var ran: [ShortcutRef] = []
    func run(_ ref: ShortcutRef) { ran.append(ref) }
}

final class ActionDispatcherTests: XCTestCase {
    private func makeDispatcher(_ poster: MockEventPoster,
                                dictation: KeyCombo = KeyCombo(modifiers: [.control, .option, .command], key: "D"),
                                runner: ShortcutRunning? = nil)
        -> ActionDispatcher {
        ActionDispatcher(poster: poster, dictationShortcut: dictation, shortcutRunner: runner)
    }

    func testKeyComboPostsCorrectStroke() {
        let poster = MockEventPoster()
        makeDispatcher(poster).dispatch(.keyCombo(KeyCombo(modifiers: [.command], key: "D")))
        XCTAssertEqual(poster.posted, [.init(keyCode: 0x02, flagBits: 0x100000)])
    }

    func testDictationPostsConfiguredShortcut() {
        let poster = MockEventPoster()
        makeDispatcher(poster).dispatch(.dictation)
        XCTAssertEqual(poster.posted,
            [.init(keyCode: 0x02, flagBits: 0x040000 | 0x080000 | 0x100000)])
    }

    func testNoneDoesNothing() {
        let poster = MockEventPoster()
        makeDispatcher(poster).dispatch(.none)
        XCTAssertTrue(poster.posted.isEmpty)
    }

    func testUnknownKeyNamePostsNothing() {
        let poster = MockEventPoster()
        makeDispatcher(poster).dispatch(.keyCombo(KeyCombo(modifiers: [.command], key: "NotAKey")))
        XCTAssertTrue(poster.posted.isEmpty)
    }

    // MARK: shortcut dispatch (issue #3)

    func testShortcutCallsRunnerOnce() {
        let poster = MockEventPoster()
        let runner = MockShortcutRunner()
        let ref = ShortcutRef(identifier: "UUID-1", name: "My SC")
        makeDispatcher(poster, runner: runner).dispatch(.shortcut(ref))
        XCTAssertEqual(runner.ran, [ref])
        XCTAssertTrue(poster.posted.isEmpty)  // never posts a keystroke
    }

    func testShortcutWithNilRunnerIsNoOp() {
        let poster = MockEventPoster()
        // No runner supplied — .shortcut must be a silent no-op, like .none.
        makeDispatcher(poster).dispatch(.shortcut(ShortcutRef(identifier: "X", name: "Y")))
        XCTAssertTrue(poster.posted.isEmpty)
    }

    func testKeyComboAndDictationNeverCallRunner() {
        let poster = MockEventPoster()
        let runner = MockShortcutRunner()
        let d = makeDispatcher(poster, runner: runner)
        d.dispatch(.keyCombo(KeyCombo(modifiers: [.command], key: "D")))
        d.dispatch(.dictation)
        XCTAssertTrue(runner.ran.isEmpty)
    }
}
