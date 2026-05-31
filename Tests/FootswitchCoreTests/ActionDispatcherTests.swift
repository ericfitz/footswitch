import XCTest
@testable import FootswitchCore

final class MockEventPoster: EventPosting {
    struct Posted: Equatable { let keyCode: UInt16; let flagBits: UInt64 }
    var posted: [Posted] = []
    func postKeyStroke(keyCode: UInt16, flagBits: UInt64) {
        posted.append(Posted(keyCode: keyCode, flagBits: flagBits))
    }
}

final class ActionDispatcherTests: XCTestCase {
    private func makeDispatcher(_ poster: MockEventPoster,
                                dictation: KeyCombo = KeyCombo(modifiers: [.control, .option, .command], key: "D"))
        -> ActionDispatcher {
        ActionDispatcher(poster: poster, dictationShortcut: dictation)
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
}
