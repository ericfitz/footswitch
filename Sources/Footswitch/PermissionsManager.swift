import AppKit
import ApplicationServices

enum PermissionsManager {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (system dialog) and returns current status.
    @discardableResult
    static func requestTrust() -> Bool {
        // kAXTrustedCheckOptionPrompt is a non-Sendable global `var` in the C headers,
        // which Swift 6 rejects in a concurrency-checked context. Its documented value
        // is the literal string "AXTrustedCheckOptionPrompt".
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
