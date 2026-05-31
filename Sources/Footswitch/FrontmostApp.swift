import AppKit

enum FrontmostApp {
    static func bundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    static func name() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
