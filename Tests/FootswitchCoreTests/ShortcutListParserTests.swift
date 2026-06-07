import XCTest
@testable import FootswitchCore

final class ShortcutListParserTests: XCTestCase {

    func testParsesSimpleLines() {
        let out = """
        Make PDF (11111111-2222-3333-4444-555555555555)
        Resize Image (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE)
        """
        let refs = ShortcutListParser.parse(out)
        XCTAssertEqual(refs.count, 2)
        // Sorted by name: "Make PDF" before "Resize Image".
        XCTAssertEqual(refs[0].name, "Make PDF")
        XCTAssertEqual(refs[0].identifier, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(refs[1].name, "Resize Image")
    }

    func testNameContainingParenthesesKeepsOnlyTrailingIdentifier() {
        let out = "Convert (HEIC) to JPEG (99999999-0000-1111-2222-333333333333)"
        let refs = ShortcutListParser.parse(out)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].name, "Convert (HEIC) to JPEG")
        XCTAssertEqual(refs[0].identifier, "99999999-0000-1111-2222-333333333333")
    }

    func testSkipsMalformedLines() {
        let out = """
        Good Shortcut (UUID-1)

        No identifier here
        ()
        Another Good (UUID-2)
        """
        // Malformed lines dropped; results sorted by name ("Another Good" first).
        let refs = ShortcutListParser.parse(out)
        XCTAssertEqual(refs.map(\.name), ["Another Good", "Good Shortcut"])
        XCTAssertEqual(refs.map(\.identifier), ["UUID-2", "UUID-1"])
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(ShortcutListParser.parse("").isEmpty)
        XCTAssertTrue(ShortcutListParser.parse("\n\n").isEmpty)
    }

    func testSortIsCaseInsensitive() {
        let out = """
        zebra (U1)
        Apple (U2)
        """
        XCTAssertEqual(ShortcutListParser.parse(out).map(\.name), ["Apple", "zebra"])
    }
}
