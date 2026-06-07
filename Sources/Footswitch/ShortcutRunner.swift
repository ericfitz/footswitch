import Foundation
import FootswitchCore

/// Runs a Shortcuts.app shortcut by spawning `/usr/bin/shortcuts run <id>`,
/// fire-and-forget and off the main thread so a long-running shortcut never
/// blocks the pedal. This is the only code in the app that spawns a process.
///
/// Lifetime note: `terminationHandler` is assigned BEFORE `run()` and captures the
/// `Process` strongly so it stays alive until it exits (otherwise it could be
/// deallocated mid-flight and the handler might never fire). A non-zero exit
/// (e.g. the shortcut was deleted) is logged; a pedal press never pops a modal.
final class ShortcutRunner: ShortcutRunning {
    func run(_ ref: ShortcutRef) {
        // Prefer the stable UUID; fall back to the name for hand-edited configs.
        let arg = ref.identifier.isEmpty ? ref.name : ref.identifier
        guard !arg.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", arg]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                NSLog("Footswitch: 'shortcuts run \(arg)' exited \(proc.terminationStatus) "
                    + "(shortcut missing or failed)")
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
            } catch {
                NSLog("Footswitch: could not run /usr/bin/shortcuts: \(error)")
            }
        }
    }
}
