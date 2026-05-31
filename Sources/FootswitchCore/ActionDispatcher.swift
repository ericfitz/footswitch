import Foundation

public final class ActionDispatcher {
    private let poster: EventPosting
    private let muter: InputMuting
    private let dictationShortcut: KeyCombo

    public init(poster: EventPosting, muter: InputMuting, dictationShortcut: KeyCombo) {
        self.poster = poster
        self.muter = muter
        self.dictationShortcut = dictationShortcut
    }

    public func dispatch(_ action: ResolvedAction) {
        switch action {
        case .keyCombo(let combo):
            postCombo(combo)
        case .dictation:
            postCombo(dictationShortcut)
        case .muteInput:
            muter.toggleInputMute()
        case .none:
            break
        }
    }

    private func postCombo(_ combo: KeyCombo) {
        guard let code = Keymap.keyCode(for: combo.key) else { return }
        poster.postKeyStroke(keyCode: code, flagBits: Keymap.flagBits(for: combo.modifiers))
    }
}
