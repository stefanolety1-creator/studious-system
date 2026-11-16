import XCTest
@testable import MsngrCore

final class ContactGroupTests: XCTestCase {

    // MARK: - System Group Builders Tests

    func test_contactGroup_systemOnlineAndOfflineBuilders() {
        let onlineMembers: Set<String> = ["alice@crosstalk.im", "bob@escargot.chat"]
        let onlineGroup = ContactGroup.online(contactIds: onlineMembers)

        XCTAssertEqual(onlineGroup.id, "system.online")
        XCTAssertEqual(onlineGroup.name, "Online")
        XCTAssertTrue(onlineGroup.isSystemGroup)
        XCTAssertFalse(onlineGroup.isCircle)
        XCTAssertTrue(onlineGroup.isExpanded)
        XCTAssertEqual(onlineGroup.orderIndex, 0)
        XCTAssertEqual(onlineGroup.contactIds, onlineMembers)

        let offlineMembers: Set<String> = ["charlie@crosstalk.im"]
        let offlineGroup = ContactGroup.offline(contactIds: offlineMembers)

        XCTAssertEqual(offlineGroup.id, "system.offline")
        XCTAssertEqual(offlineGroup.name, "Offline")
        XCTAssertTrue(offlineGroup.isSystemGroup)
        XCTAssertFalse(offlineGroup.isCircle)
        XCTAssertTrue(offlineGroup.isExpanded)
        XCTAssertEqual(offlineGroup.orderIndex, 1)
        XCTAssertEqual(offlineGroup.contactIds, offlineMembers)
    }

    // MARK: - Expansion State Toggle Tests

    func test_contactGroup_expansionStateToggle() {
        var group = ContactGroup(
            id: "grp-friends",
            name: "Friends & Family",
            contactIds: ["alice@crosstalk.im"],
            isExpanded: true,
            orderIndex: 2
        )

        XCTAssertTrue(group.isExpanded, "Initial group state should be expanded")

        // Collapse group
        group.isExpanded = false
        XCTAssertFalse(group.isExpanded, "Group state must collapse to false")
        XCTAssertEqual(group.id, "grp-friends")
        XCTAssertEqual(group.name, "Friends & Family")
        XCTAssertEqual(group.contactIds.count, 1)

        // Expand group again
        group.isExpanded.toggle()
        XCTAssertTrue(group.isExpanded, "Group state must re-expand to true")
    }

    // MARK: - Member Set Operations Tests

    func test_contactGroup_memberSetOperations() throws {
        var group = ContactGroup(
            id: "grp-coworkers",
            name: "Coworkers",
            contactIds: ["alice@crosstalk.im"]
        )

        // Add member
        let (inserted, _) = group.contactIds.insert("bob@crosstalk.im")
        XCTAssertTrue(inserted, "Inserting a new contact ID should succeed")
        XCTAssertEqual(group.contactIds.count, 2)
        XCTAssertTrue(group.contactIds.contains("bob@crosstalk.im"))

        // Duplicate insert should not increase count
        let (dupInserted, _) = group.contactIds.insert("alice@crosstalk.im")
        XCTAssertFalse(dupInserted, "Duplicate contact ID insertion should return false")
        XCTAssertEqual(group.contactIds.count, 2)

        // Remove member
        let removed = group.contactIds.remove("alice@crosstalk.im")
        XCTAssertEqual(removed, "alice@crosstalk.im")
        XCTAssertEqual(group.contactIds.count, 1)
        XCTAssertFalse(group.contactIds.contains("alice@crosstalk.im"))

        // Set operations: union with new contacts
        let newTeamMembers: Set<String> = ["carol@crosstalk.im", "dave@escargot.chat"]
        group.contactIds.formUnion(newTeamMembers)
        XCTAssertEqual(group.contactIds.count, 3)
        XCTAssertTrue(group.contactIds.contains("carol@crosstalk.im"))
        XCTAssertTrue(group.contactIds.contains("dave@escargot.chat"))

        // Codable roundtrip test
        let encoder = JSONEncoder()
        let data = try encoder.encode(group)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ContactGroup.self, from: data)

        XCTAssertEqual(group.id, decoded.id)
        XCTAssertEqual(group.name, decoded.name)
        XCTAssertEqual(group.contactIds, decoded.contactIds)
        XCTAssertEqual(group.isExpanded, decoded.isExpanded)
        XCTAssertEqual(group.orderIndex, decoded.orderIndex)
    }
}
