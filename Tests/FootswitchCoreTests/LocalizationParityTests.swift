import XCTest

// Force-try is fine in this test: the .strings fixtures are repo files, so a parse
// failure is a real test failure we want surfaced, not handled.
// swiftlint:disable force_try

/// Verifies the hand-managed Localizable.strings files stay structurally in
/// sync: same keys everywhere, and the same number of positional placeholders
/// (%N$@) per key. Reads the source .strings files directly — no .app bundle.
/// Locales are discovered from disk so newly added .lproj folders are covered
/// automatically; `en` is the authoritative reference.
final class LocalizationParityTests: XCTestCase {
    /// Repo root derived from this file's path: Tests/FootswitchCoreTests/<file>.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FootswitchCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private static var localizationsDir: URL {
        repoRoot().appendingPathComponent("Sources/Footswitch/Resources/Localizations")
    }

    /// Every `<locale>.lproj` folder present on disk.
    private static var locales: [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: localizationsDir, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private static func stringsURL(_ locale: String) -> URL {
        localizationsDir
            .appendingPathComponent("\(locale).lproj")
            .appendingPathComponent("Localizable.strings")
    }

    /// Parses a .strings file into [key: value] using PropertyListSerialization
    /// (the .strings old-style plist format is supported by the OpenStep reader).
    private func parse(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        guard let dict = plist as? [String: String] else {
            XCTFail("Not a string dictionary: \(url.path)")
            return [:]
        }
        return dict
    }

    /// Counts positional specifiers like %1$@, %2$@ — returns the highest index.
    private func placeholderArity(_ value: String) -> Int {
        var maxIndex = 0
        let pattern = try! NSRegularExpression(pattern: "%([0-9]+)\\$@")
        let ns = value as NSString
        for m in pattern.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            let idx = Int(ns.substring(with: m.range(at: 1))) ?? 0
            maxIndex = max(maxIndex, idx)
        }
        // Also count bare %@ (each contributes one positional argument).
        let bare = try! NSRegularExpression(pattern: "%@")
        let bareCount = bare.numberOfMatches(in: value, range: NSRange(location: 0, length: ns.length))
        return max(maxIndex, bareCount)
    }

    func testLocaleDiscoveryFoundFiles() {
        // Guard against a broken path silently reducing coverage to zero.
        XCTAssertTrue(Self.locales.contains("en"), "en.lproj not discovered")
        XCTAssertGreaterThanOrEqual(Self.locales.count, 4,
            "expected many localizations, found \(Self.locales.count): \(Self.locales)")
    }

    func testAllLocalesParse() throws {
        for locale in Self.locales {
            let dict = try parse(Self.stringsURL(locale))
            XCTAssertFalse(dict.isEmpty, "\(locale) parsed empty")
        }
    }

    func testKeySetsMatchEnglish() throws {
        let en = Set(try parse(Self.stringsURL("en")).keys)
        for locale in Self.locales where locale != "en" {
            let keys = Set(try parse(Self.stringsURL(locale)).keys)
            XCTAssertEqual(keys, en,
                "\(locale) keys differ from en. Missing: \(en.subtracting(keys)). Extra: \(keys.subtracting(en)).")
        }
    }

    func testPlaceholderArityMatchesEnglish() throws {
        let en = try parse(Self.stringsURL("en"))
        for locale in Self.locales where locale != "en" {
            let dict = try parse(Self.stringsURL(locale))
            for (key, enValue) in en {
                guard let value = dict[key] else { continue } // key-set test covers gaps
                XCTAssertEqual(placeholderArity(value), placeholderArity(enValue),
                    "Placeholder count mismatch for '\(key)' in \(locale).")
            }
        }
    }
}
