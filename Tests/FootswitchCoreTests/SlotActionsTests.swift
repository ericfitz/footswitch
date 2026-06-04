import XCTest
@testable import FootswitchCore

final class SlotActionsTests: XCTestCase {
    func testAccessorReturnsConfiguredSlotAndNilOtherwise() {
        let combo = Action.keyCombo(KeyCombo(modifiers: [.command], key: "D"))
        let slots = SlotActions(bySlot: [1: combo])
        XCTAssertEqual(slots.action(forSlot: 1), combo)
        XCTAssertNil(slots.action(forSlot: 2))
    }

    func testRoundTripsCodableWithStringKeys() throws {
        let slots = SlotActions(bySlot: [
            1: .keyCombo(KeyCombo(modifiers: [.command], key: "A")),
            2: .dictation,
        ])
        let data = try JSONEncoder().encode(slots)
        let decoded = try JSONDecoder().decode(SlotActions.self, from: data)
        XCTAssertEqual(decoded, slots)
        // Keys are emitted as stringified slot indices.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["1"])
        XCTAssertNotNil(object?["2"])
    }

    func testEmptyRoundTrips() throws {
        let empty = SlotActions(bySlot: [:])
        let decoded = try JSONDecoder().decode(
            SlotActions.self, from: try JSONEncoder().encode(empty))
        XCTAssertEqual(decoded, empty)
    }
}
