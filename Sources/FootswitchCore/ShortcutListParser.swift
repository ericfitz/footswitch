import Foundation

/// Pure parser for the output of `shortcuts list --show-identifiers`, which prints
/// one shortcut per line in the form `Name (UUID)`. Kept in Core (no IO) so it is
/// unit-testable without spawning a process; the app target runs the CLI and feeds
/// the captured stdout here.
public enum ShortcutListParser {
    /// Parses stdout into `ShortcutRef`s, sorted by name (case-insensitive).
    /// A line's trailing `(<identifier>)` is the UUID; everything before it (minus
    /// the separating space) is the name — so names may themselves contain
    /// parentheses, only the LAST parenthesized group is treated as the identifier.
    /// Lines without a trailing `(...)` group, or with an empty name/identifier,
    /// are skipped.
    public static func parse(_ stdout: String) -> [ShortcutRef] {
        var refs: [ShortcutRef] = []
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.hasSuffix(")"),
                  let open = line.range(of: "(", options: .backwards) else { continue }
            let identifier = String(line[line.index(after: open.lowerBound)..<line.index(before: line.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            let name = String(line[line.startIndex..<open.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            guard !identifier.isEmpty, !name.isEmpty else { continue }
            refs.append(ShortcutRef(identifier: identifier, name: name))
        }
        return refs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
