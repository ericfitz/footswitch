import Foundation
import FootswitchCore

/// Enumerates installed Shortcuts.app shortcuts by running
/// `/usr/bin/shortcuts list --show-identifiers` and parsing its output with
/// `ShortcutListParser`. Synchronous and on-demand (only when the user opens the
/// picker — never on the press hot path); returns `[]` on any failure (CLI
/// missing, no shortcuts, or the Automation prompt declined). Callers cache the
/// result for the Settings window's lifetime so cell building doesn't re-spawn.
enum ShortcutCatalog {
    static func installed() -> [ShortcutRef] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list", "--show-identifiers"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return ShortcutListParser.parse(String(decoding: data, as: UTF8.self))
    }
}
