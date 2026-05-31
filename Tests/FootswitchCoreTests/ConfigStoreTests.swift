import XCTest
@testable import FootswitchCore

final class ConfigStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fsw-test-\(UUID().uuidString)", isDirectory: true)
    }

    func testLoadCreatesDefaultWhenMissing() throws {
        let dir = tempDir()
        let store = ConfigStore(directory: dir)
        let config = try store.load()
        XCTAssertEqual(config, .default)
        // File now exists on disk.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("config.json").path))
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveThenLoadRoundTrips() throws {
        let dir = tempDir()
        let store = ConfigStore(directory: dir)
        var config = Config.default
        config.rules = [Rule(match: "com.x.app", appName: "X",
                             action: .keyCombo(KeyCombo(modifiers: [.command], key: "K")))]
        try store.save(config)
        let loaded = try store.load()
        XCTAssertEqual(loaded, config)
        try? FileManager.default.removeItem(at: dir)
    }

    func testMalformedJSONThrows() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("config.json"))
        let store = ConfigStore(directory: dir)
        XCTAssertThrowsError(try store.load())
        try? FileManager.default.removeItem(at: dir)
    }
}
