import Foundation

public final class ActionDispatcher {
    private let poster: EventPosting
    private let dictationShortcut: KeyCombo
    private let shortcutRunner: ShortcutRunning?

    public init(poster: EventPosting, dictationShortcut: KeyCombo,
                shortcutRunner: ShortcutRunning? = nil) {
        self.poster = poster
        self.dictationShortcut = dictationShortcut
        self.shortcutRunner = shortcutRunner
    }

    public func dispatch(_ action: ResolvedAction) {
        switch action {
        case .keyCombo(let combo):
            postCombo(combo)
        case .dictation:
            postCombo(dictationShortcut)
        case .shortcut(let ref):
            // A nil runner makes this a no-op (e.g. in unit tests), like .none.
            shortcutRunner?.run(ref)
        case .none:
            break
        }
    }

    private func postCombo(_ combo: KeyCombo) {
        guard let code = Keymap.keyCode(for: combo.key) else { return }
        poster.postKeyStroke(keyCode: code, flagBits: Keymap.flagBits(for: combo.modifiers))
    }
}
