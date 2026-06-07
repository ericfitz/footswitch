import XCTest
@testable import FootswitchCore

final class RuleResolverTests: XCTestCase {
    private func makeConfig(rules: [Rule], def: DefaultAction = .dictation) -> Config {
        var c = Config.default
        c.defaultAction = def
        c.rules = rules
        return c
    }

    func testExactMatchWins() {
        let vsCode = Rule(match: "com.microsoft.VSCode", appName: "VS Code",
                          action: .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
        let config = makeConfig(rules: [vsCode])
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.microsoft.VSCode", config: config),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "D")))
    }

    func testFallsBackToDefault() {
        let config = makeConfig(rules: [], def: .dictation)
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.apple.Safari", config: config), .dictation)
    }

    func testNilBundleIDUsesDefault() {
        let config = makeConfig(rules: [], def: .dictation)
        XCTAssertEqual(RuleResolver.resolve(bundleID: nil, config: config), .dictation)
    }

    func testNoneDefaultResolves() {
        XCTAssertEqual(RuleResolver.resolve(bundleID: "x", config: makeConfig(rules: [], def: .none)), ResolvedAction.none)
    }

    func testMatchedRuleWinsOverDefault() {
        let r = Rule(match: "com.x.app", appName: "X", action: .keyCombo(KeyCombo(modifiers: [.command], key: "M")))
        let config = makeConfig(rules: [r], def: .none)
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", config: config),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "M")))
    }

    func testFirstMatchingRuleWinsOnDuplicates() {
        let a = Rule(match: "com.x.app", appName: "A", action: .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
        let b = Rule(match: "com.x.app", appName: "B", action: .keyCombo(KeyCombo(modifiers: [.command], key: "B")))
        let config = makeConfig(rules: [a, b])
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", config: config),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
    }

    func testSlotAwareResolvesPerSlotAction() {
        let r = Rule(match: "com.x.app", appName: "X", slots: SlotActions(bySlot: [
            1: .keyCombo(KeyCombo(modifiers: [.command], key: "A")),
            2: .keyCombo(KeyCombo(modifiers: [.command], key: "B")),
        ]))
        let config = makeConfig(rules: [r], def: .dictation)
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", slot: 1, config: config),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", slot: 2, config: config),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "B")))
    }

    func testSlotWithNoActionFallsBackToGlobalDefault() {
        let r = Rule(match: "com.x.app", appName: "X",
                     slots: SlotActions(bySlot: [1: .keyCombo(KeyCombo(modifiers: [.command], key: "A"))]))
        let config = makeConfig(rules: [r], def: .dictation)
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", slot: 2, config: config), .dictation)
    }

    func testWrapperUsesSlot1() {
        let r = Rule(match: "com.x.app", appName: "X",
                     slots: SlotActions(bySlot: [1: .keyCombo(KeyCombo(modifiers: [.command], key: "A"))]))
        let config = makeConfig(rules: [r])
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.x.app", config: config),
                       .keyCombo(KeyCombo(modifiers: [.command], key: "A")))
    }

    // MARK: shortcut action (issue #3)

    func testMatchedShortcutRuleResolvesToShortcut() {
        let ref = ShortcutRef(identifier: "UUID-1", name: "My SC")
        let r = Rule(match: "com.notes.app", appName: "Notes", action: .shortcut(ref))
        let config = makeConfig(rules: [r])
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.notes.app", config: config),
                       .shortcut(ref))
    }

    func testShortcutRuleDoesNotAffectDefaultPath() {
        // A shortcut rule for one app leaves an unmatched app on the default.
        let r = Rule(match: "com.notes.app", appName: "Notes",
                     action: .shortcut(ShortcutRef(identifier: "U", name: "N")))
        let config = makeConfig(rules: [r], def: .dictation)
        XCTAssertEqual(RuleResolver.resolve(bundleID: "com.apple.Safari", config: config), .dictation)
    }
}
