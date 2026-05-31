import XCTest
@testable import FootswitchCore

final class SmokeTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertEqual(FootswitchCore.marker, "footswitch-core")
    }
}
