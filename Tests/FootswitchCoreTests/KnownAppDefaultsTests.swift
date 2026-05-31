import XCTest
@testable import FootswitchCore

final class KnownAppDefaultsTests: XCTestCase {
    func testKnownWithShortcut() {
        XCTAssertEqual(KnownAppDefaults.suggestedShortcut(forBundleID: "us.zoom.xos"),
                       KeyCombo(modifiers: [.command, .shift], key: "A"))
        XCTAssertTrue(KnownAppDefaults.isKnown(bundleID: "us.zoom.xos"))
    }
    func testKnownButBlank() {
        XCTAssertNil(KnownAppDefaults.suggestedShortcut(forBundleID: "com.apple.FaceTime"))
        XCTAssertTrue(KnownAppDefaults.isKnown(bundleID: "com.apple.FaceTime"))
        XCTAssertTrue(KnownAppDefaults.isKnown(bundleID: "com.microsoft.VSCode"))
    }
    func testTeamsBothIds() {
        XCTAssertEqual(KnownAppDefaults.suggestedShortcut(forBundleID: "com.microsoft.teams2"),
                       KeyCombo(modifiers: [.command, .shift], key: "M"))
        XCTAssertEqual(KnownAppDefaults.suggestedShortcut(forBundleID: "com.microsoft.teams"),
                       KeyCombo(modifiers: [.command, .shift], key: "M"))
    }
    func testChrome() {
        XCTAssertEqual(KnownAppDefaults.suggestedShortcut(forBundleID: "com.google.Chrome"),
                       KeyCombo(modifiers: [.command], key: "D"))
    }
    func testUnknown() {
        XCTAssertNil(KnownAppDefaults.suggestedShortcut(forBundleID: "com.example.nope"))
        XCTAssertFalse(KnownAppDefaults.isKnown(bundleID: "com.example.nope"))
    }
}
