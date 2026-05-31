import XCTest
@testable import FootswitchCore

final class MockEventPoster: EventPosting {
    struct Posted: Equatable { let keyCode: UInt16; let flagBits: UInt64 }
    var posted: [Posted] = []
    func postKeyStroke(keyCode: UInt16, flagBits: UInt64) {
        posted.append(Posted(keyCode: keyCode, flagBits: flagBits))
    }
}

final class MockInputMuter: InputMuting {
    var toggleCount = 0
    func toggleInputMute() { toggleCount += 1 }
}

final class ActionDispatcherTests: XCTestCase {
    private func makeDispatcher(_ poster: MockEventPoster, _ muter: MockInputMuter,
                                dictation: KeyCombo = KeyCombo(modifiers: [.control, .option, .command], key: "D"))
        -> ActionDispatcher {
        ActionDispatcher(poster: poster, muter: muter, dictationShortcut: dictation)
    }

    func testKeyComboPostsCorrectStroke() {
        let poster = MockEventPoster(); let muter = MockInputMuter()
        makeDispatcher(poster, muter).dispatch(.keyCombo(KeyCombo(modifiers: [.command], key: "D")))
        XCTAssertEqual(poster.posted, [.init(keyCode: 0x02, flagBits: 0x100000)])
        XCTAssertEqual(muter.toggleCount, 0)
    }

    func testDictationPostsConfiguredShortcut() {
        let poster = MockEventPoster(); let muter = MockInputMuter()
        makeDispatcher(poster, muter).dispatch(.dictation)
        XCTAssertEqual(poster.posted,
            [.init(keyCode: 0x02, flagBits: 0x040000 | 0x080000 | 0x100000)])
    }

    func testMuteInputTogglesMuter() {
        let poster = MockEventPoster(); let muter = MockInputMuter()
        makeDispatcher(poster, muter).dispatch(.muteInput)
        XCTAssertEqual(muter.toggleCount, 1)
        XCTAssertTrue(poster.posted.isEmpty)
    }

    func testNoneDoesNothing() {
        let poster = MockEventPoster(); let muter = MockInputMuter()
        makeDispatcher(poster, muter).dispatch(.none)
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertEqual(muter.toggleCount, 0)
    }

    func testUnknownKeyNamePostsNothing() {
        let poster = MockEventPoster(); let muter = MockInputMuter()
        makeDispatcher(poster, muter).dispatch(.keyCombo(KeyCombo(modifiers: [.command], key: "NotAKey")))
        XCTAssertTrue(poster.posted.isEmpty)
    }
}
