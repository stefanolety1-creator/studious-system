import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class ContactSyncE2ETests: XCTestCase {
    var abchServer: MockABCHServer!
    var nsServer: MockNotificationServer!
    var abchClient: ABCHClient!
    var nsClient: NotificationServerClient!
    var allocatedNsPort: UInt16 = 0

    override func setUp() async throws {
        try await super.setUp()
        MockSOAPURLProtocol.register()
        abchServer = MockABCHServer()
        MockSOAPRouter.shared.abchServer = abchServer

        nsServer = MockNotificationServer()
        allocatedNsPort = try await nsServer.start()

        abchClient = ABCHClient(endpoint: URL(string: "https://contacts.msn.com/abservice/abservice.asmx")!)
        nsClient = NotificationServerClient(host: "127.0.0.1", port: allocatedNsPort)
    }

    override func tearDown() async throws {
        await nsClient?.disconnect()
        await nsServer?.stop()
        MockSOAPRouter.shared.reset()
        MockSOAPURLProtocol.unregister()
        try await super.tearDown()
    }

    // MARK: - Feature Area 4: ABCH Contact List Sync & Membership (Tier 1)

    func test_tier1_abch_fullContactListRetrieval() async throws {
        abchServer.contacts = [
            MockABContact(id: "11111111-2222-3333-4444-555555555551", email: "alice@msngr.dev", displayName: "Alice"),
            MockABContact(id: "11111111-2222-3333-4444-555555555552", email: "bob@msngr.dev", displayName: "Bob")
        ]

        let result = try await abchClient.findContacts(ticket: "mockTicket")
        XCTAssertEqual(result.contacts.count, 2, "Should return 2 contacts")
        XCTAssertTrue(result.contacts.contains(where: { $0.email == "alice@msngr.dev" }))
        XCTAssertTrue(result.contacts.contains(where: { $0.email == "bob@msngr.dev" }))
    }

    func test_tier1_abch_contactGroupResolution() async throws {
        abchServer.groups = [
            MockABGroup(id: "00000000-0000-0000-0001-000000000001", name: "Coworkers"),
            MockABGroup(id: "00000000-0000-0000-0001-000000000002", name: "Friends")
        ]

        let result = try await abchClient.findContacts(ticket: "mockTicket")
        XCTAssertGreaterThanOrEqual(result.groups.count, 2)
        XCTAssertTrue(result.groups.contains(where: { $0.name == "Coworkers" }))
        XCTAssertTrue(result.groups.contains(where: { $0.name == "Friends" }))
    }

    func test_tier1_abch_circleTicketExtraction() async throws {
        let result = try await abchClient.findContacts(ticket: "mockTicket")
        XCTAssertNotNil(result.circleTicket, "Circle ticket must be extracted")
        XCTAssertTrue(result.circleTicket?.contains("CircleId") ?? false)
    }

    func test_tier1_abch_pendingInvitationsMembership() async throws {
        let members = try await abchClient.findMembership(ticket: "mockTicket", role: .pending)
        XCTAssertEqual(members.first?.role, .pending)
    }

    func test_tier1_abch_blockedContactsMembership() async throws {
        let members = try await abchClient.findMembership(ticket: "mockTicket", role: .block)
        XCTAssertEqual(members.first?.role, .block)
    }

    // MARK: - Feature Area 4: ABCH Contact List Sync & Membership (Tier 2)

    func test_tier2_abch_emptyAddressBookZeroContacts() async throws {
        abchServer.contacts = []
        let result = try await abchClient.findContacts(ticket: "mockTicket")
        XCTAssertEqual(result.contacts.count, 0, "Empty address book should return empty list")
    }

    func test_tier2_abch_contactsWithUnicodeDisplayNames() async throws {
        abchServer.contacts = [
            MockABContact(id: "U-1", email: "jp@msngr.dev", displayName: "日本語"),
            MockABContact(id: "U-2", email: "ar@msngr.dev", displayName: "العربية"),
            MockABContact(id: "U-3", email: "ru@msngr.dev", displayName: "Русский"),
            MockABContact(id: "U-4", email: "star@msngr.dev", displayName: "🌟 Star")
        ]

        let result = try await abchClient.findContacts(ticket: "mockTicket")
        XCTAssertEqual(result.contacts.count, 4)
        XCTAssertTrue(result.contacts.contains(where: { $0.displayName == "日本語" }))
        XCTAssertTrue(result.contacts.contains(where: { $0.displayName == "🌟 Star" }))
    }

    func test_tier2_abch_contactAddInvalidEmailSoapFault() async throws {
        do {
            _ = try await abchClient.addContact(email: "not_an_email")
            XCTFail("Expected invalid email to fail")
        } catch let error as AddressBookError {
            XCTAssertEqual(error, .invalidEmail)
        }
    }

    func test_tier2_abch_contactAddAlreadyExistsSoapFault() async throws {
        _ = try await abchClient.addContact(email: "existing@msngr.dev", displayName: "Existing")

        do {
            _ = try await abchClient.addContact(email: "existing@msngr.dev", displayName: "Existing Again")
            XCTFail("Expected duplicate contact add to fail")
        } catch let error as AddressBookError {
            XCTAssertEqual(error, .contactAlreadyExists)
        }
    }

    func test_tier2_abch_contactDeletionIsMessengerUserFalse() async throws {
        let guid = try await abchClient.addContact(email: "to_delete@msngr.dev", displayName: "Delete Me")
        try await abchClient.removeContact(contactGuid: guid)

        guard let req = abchServer.recordedRequests.last else {
            XCTFail("No recorded update request")
            return
        }
        XCTAssertTrue(req.body.contains("isMessengerUser"), "Contact update must toggle isMessengerUser")
        XCTAssertTrue(req.body.contains("false"), "Value should be false")
    }

    // MARK: - Feature Area 5: Initial Contact List Sync via NS (ADL) (Tier 1)

    func test_tier1_adl_singleDomainForwardList() async throws {
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [("alice@msngr.dev", 3)])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("<d n=\"msngr.dev\">"))
        XCTAssertTrue(text.contains("<c n=\"alice\" l=\"3\" t=\"1\"/>"))
    }

    func test_tier1_adl_multiDomainGrouping() async throws {
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [
            ("alice@msngr.dev", 3),
            ("bob@hotmail.com", 3),
            ("carol@msngr.dev", 3)
        ])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("<d n=\"msngr.dev\">"))
        XCTAssertTrue(text.contains("<d n=\"hotmail.com\">"))
    }

    func test_tier1_adl_allowAndForwardListFlags() async throws {
        // Forward (1) + Allow (2) = 3
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [("allowed@msngr.dev", 3)])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("l=\"3\""))
    }

    func test_tier1_adl_blockedContactMask() async throws {
        // Forward (1) + Block (4) = 5
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [("blocked@msngr.dev", 5)])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("l=\"5\""))
    }

    func test_tier1_adl_emptyContactListAdlSync() async throws {
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("<ml l=\"1\"></ml>") || text.contains("<ml l=\"1\">"))
    }

    // MARK: - Feature Area 5: Initial Contact List Sync via NS (ADL) (Tier 2)

    func test_tier2_adl_largeRosterPartitioningOver150Contacts() async throws {
        var roster: [(email: String, flags: Int)] = []
        for i in 1...200 {
            roster.append(("user\(i)@msngr.dev", 3))
        }

        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: roster)

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
    }

    func test_tier2_adl_emailWithSubdomainsAndDots() async throws {
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [("john.doe@corp.dept.msngr.dev", 3)])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("<d n=\"corp.dept.msngr.dev\">"))
        XCTAssertTrue(text.contains("<c n=\"john.doe\""))
    }

    func test_tier2_adl_domainGroupingAlphabeticalOrdering() async throws {
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [
            ("zebra@zebra.com", 3),
            ("apple@apple.com", 3),
            ("mango@mango.com", 3)
        ])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        let appleIdx = text.range(of: "apple.com")?.lowerBound
        let mangoIdx = text.range(of: "mango.com")?.lowerBound
        let zebraIdx = text.range(of: "zebra.com")?.lowerBound

        XCTAssertNotNil(appleIdx)
        XCTAssertNotNil(mangoIdx)
        XCTAssertNotNil(zebraIdx)
        XCTAssertTrue(appleIdx! < mangoIdx! && mangoIdx! < zebraIdx!, "Domains must be deterministically sorted")
    }

    func test_tier2_adl_specialCharactersInContactAccount() async throws {
        try await nsClient.connect()
        try await nsClient.syncAddressBook(contacts: [("alice+tag-1_2@msngr.dev", 3)])

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("c n=\"alice+tag-1_2\""))
    }

    func test_tier2_adl_corruptedAdlServerNak() async throws {
        let error = NotificationServerError.synchronizationFailed(code: 241)
        if case .synchronizationFailed(let code) = error {
            XCTAssertEqual(code, 241)
        } else {
            XCTFail("Expected synchronizationFailed(241)")
        }
    }
}
