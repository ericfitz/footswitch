import AppKit
import FootswitchCore

// MARK: - Live key-capture view
//
// An AppKit control that records a keyboard shortcut. Click to enter recording
// mode, then press a combo. A modifier is required unless the key is a function
// key (F1-F20). The captured key is stored as a Keymap-recognized name so it
// round-trips through ActionDispatcher.

@MainActor
final class ShortcutCaptureView: NSView {
    var combo: KeyCombo? { didSet { render() } }
    var onCapture: ((KeyCombo) -> Void)?
    var onClear: (() -> Void)?

    private var recording = false { didSet { render() } }
    private let label = NSTextField(labelWithString: "")
    // While recording we install a local event monitor. NSTableView and the
    // window's key-equivalent routing would otherwise swallow Command-combos
    // before they reach this view's keyDown — the monitor sees them first.
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // Tear down the event monitor if the cell is recycled or the window closes
    // while still recording (deinit can't touch @MainActor state under Swift 6).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, recording { stopRecording() }
    }

    // A click anywhere in the cell toggles recording. We override hitTest so the
    // click lands on us (not a subview) and handle it in mouseDown.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            guard let self else { return ev }
            return self.handle(ev)
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    // Returns nil to swallow the event (consumed by the recorder) or the event to
    // let it pass through normally.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .flagsChanged {
            // Show the modifiers building up live; don't commit yet.
            renderLive(modifiers(from: event.modifierFlags))
            return nil
        }

        // .keyDown
        // Escape cancels without changing the stored combo.
        if event.keyCode == 0x35 { // Escape
            stopRecording()
            render()
            return nil
        }

        // Delete/Backspace clears the shortcut (standard macOS convention).
        if event.type == .keyDown, event.keyCode == 0x33 { // Delete
            combo = nil
            stopRecording()
            render()
            onClear?()
            return nil
        }

        let mods = modifiers(from: event.modifierFlags)
        guard let keyName = Keymap.keyName(forCode: event.keyCode) else {
            flashHint(L10n.captureUnsupportedKey)
            return nil
        }
        let isFunctionKey = keyName.uppercased().hasPrefix("F") && keyName.count >= 2
            && Int(keyName.dropFirst()) != nil

        // Require at least one modifier unless it's a function key.
        guard !mods.isEmpty || isFunctionKey else {
            flashHint(L10n.captureAddModifier)
            return nil
        }

        let captured = KeyCombo(modifiers: mods, key: keyName)
        combo = captured
        stopRecording()
        render()
        onCapture?(captured)
        return nil
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> [Modifier] {
        var result: [Modifier] = []
        if flags.contains(.control) { result.append(.control) }
        if flags.contains(.option) { result.append(.option) }
        if flags.contains(.shift) { result.append(.shift) }
        if flags.contains(.command) { result.append(.command) }
        return result
    }

    private func flashHint(_ text: String) {
        label.stringValue = text
        label.textColor = .systemRed
    }

    // During recording, echo just-the-modifiers (e.g. "⌘⇧") so the user sees
    // capture is live before they press the final key.
    private func renderLive(_ mods: [Modifier]) {
        guard recording else { return }
        let glyphs = mods.isEmpty ? L10n.capturePressShortcut
            : KeyComboFormatter.display(KeyCombo(modifiers: mods, key: "")).trimmingCharacters(in: .whitespaces)
        label.stringValue = glyphs.isEmpty ? L10n.capturePressShortcut : glyphs
        label.textColor = .secondaryLabelColor
        styleBorder()
    }

    private func styleBorder() {
        layer?.borderWidth = recording ? 2 : 1
        layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.cornerRadius = 5
    }

    private func render() {
        styleBorder()
        label.textColor = .labelColor
        if recording {
            label.stringValue = L10n.capturePressShortcut
            label.textColor = .secondaryLabelColor
        } else if let combo, !combo.key.isEmpty {
            label.stringValue = KeyComboFormatter.display(combo)
        } else {
            label.stringValue = L10n.captureClickToSet
            label.textColor = .secondaryLabelColor
        }
    }
}
