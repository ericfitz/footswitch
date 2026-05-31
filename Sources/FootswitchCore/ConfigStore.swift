import Foundation

public final class ConfigStore {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Default directory is ~/.footswitch ; injectable for tests.
    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".footswitch", isDirectory: true)
    }

    /// Loads config, creating the directory + default file if absent.
    public func load() throws -> Config {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let config = Config.default
            try save(config)
            return config
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
