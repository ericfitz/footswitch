import XCTest
@testable import FootswitchCore

final class DebouncerTests: XCTestCase {
    func testFirstPressAlwaysFires() {
        var d = Debouncer(intervalMs: 250)
        XCTAssertTrue(d.shouldFire(atMs: 1_000))
    }

    func testRepeatWithinIntervalSkips() {
        var d = Debouncer(intervalMs: 250)
        _ = d.shouldFire(atMs: 1_000)
        XCTAssertFalse(d.shouldFire(atMs: 1_100)) // 100ms later < 250ms
    }

    func testPressAfterIntervalFires() {
        var d = Debouncer(intervalMs: 250)
        _ = d.shouldFire(atMs: 1_000)
        XCTAssertTrue(d.shouldFire(atMs: 1_300)) // 300ms later > 250ms
    }

    func testBoundaryIsInclusiveSkip() {
        var d = Debouncer(intervalMs: 250)
        _ = d.shouldFire(atMs: 1_000)
        XCTAssertFalse(d.shouldFire(atMs: 1_250)) // exactly interval -> still skip
        XCTAssertTrue(d.shouldFire(atMs: 1_251))
    }
}
