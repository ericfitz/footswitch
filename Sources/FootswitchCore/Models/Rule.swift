import Foundation

public struct Rule: Codable, Equatable, Sendable {
    public var match: String     // frontmost app bundle ID
    public var appName: String   // display only
    public var action: Action

    public init(match: String, appName: String, action: Action) {
        self.match = match
        self.appName = appName
        self.action = action
    }
}
