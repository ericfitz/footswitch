import AppKit

/// A self-contained, non-resizable About window: icon, name, version+commit,
/// description, copyright, and link buttons (GitHub, report-a-problem, license).
/// Version/commit come from Info.plist; the commit hash is injected at package time.
@MainActor
final class AboutWindowController: NSWindowController {
    private static let repoURL = "https://github.com/ericfitz/footswitch"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = L10n.aboutWindowTitle
        self.init(window: window)
        let content = AboutWindowController.makeContentView()
        window.contentView = content
        wireLinkTargets(in: content)
        window.setContentSize(content.fittingSize)
        window.center()
    }

    /// Point every link button's target at this controller (the static factory
    /// could not reference self).
    private func wireLinkTargets(in view: NSView) {
        for sub in view.subviews {
            if let button = sub as? NSButton { button.target = self }
            wireLinkTargets(in: sub)
        }
    }

    // MARK: - Bundle values

    private static func shortVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static func commitHash() -> String {
        Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String ?? "0000000"
    }

    private static func archString() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine
    }

    // MARK: - Content

    private static func makeContentView() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage ?? NSImage(named: "AppIcon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let name = label("Footswitch", font: .boldSystemFont(ofSize: 18))
        let version = label(
            L10n.aboutVersion(version: shortVersion(), commit: commitHash()),
            font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let desc = label(L10n.aboutDescription, font: .systemFont(ofSize: 12))
        desc.alignment = .center
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 3
        desc.preferredMaxLayoutWidth = 300
        let copyright = label(L10n.aboutCopyright, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

        let links = NSStackView(views: [
            linkButton(L10n.aboutViewOnGitHub, action: #selector(openRepo)),
            linkButton(L10n.aboutReportProblem, action: #selector(openIssue)),
            linkButton(L10n.aboutLicense, action: #selector(openLicense)),
        ])
        links.orientation = .horizontal
        links.spacing = 16
        links.alignment = .centerY

        let stack = NSStackView(views: [icon, name, version, desc, copyright, links])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private static func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        l.alignment = .center
        return l
    }

    /// A borderless, blue link-style button.
    private static func linkButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: nil, action: action)
        b.isBordered = false
        b.bezelStyle = .inline
        b.contentTintColor = .linkColor
        let attr = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: 12),
        ])
        b.attributedTitle = attr
        return b
    }

    // MARK: - Link actions

    @objc private func openRepo() {
        open(Self.repoURL)
    }

    @objc private func openLicense() {
        open("\(Self.repoURL)/blob/main/LICENSE")
    }

    @objc private func openIssue() {
        let body = """
        **Describe the problem:**


        **Environment (auto-filled):**
        - Footswitch version: \(Self.shortVersion()) (\(Self.commitHash()))
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Architecture: \(Self.archString())
        """
        guard var components = URLComponents(string: "\(Self.repoURL)/issues/new") else { return }
        components.queryItems = [
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
