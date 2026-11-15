//
// MockABCHServer.swift
// MsngrIntegrationTests
//
// In-memory mock server for Windows Live Contacts / ABCH SOAP services:
// - /abservice/abservice.asmx (ABFindContactsPaged, ABContactAdd, ABContactUpdate)
// - /abservice/SharingService.asmx (FindMembership, AddMember, DeleteMember)
//

import Foundation

/// In-memory mock server for Windows Live Contacts / ABCH SOAP services:
/// - /abservice/abservice.asmx (ABFindContactsPaged, ABContactAdd, ABContactUpdate)
/// - /abservice/SharingService.asmx (FindMembership, AddMember, DeleteMember)
public final class MockABCHServer: @unchecked Sendable {
    private let lock = NSLock()

    // In-memory Address Book Store
    public var ownerDisplayName: String = "Mock Profile"
    public var ownerEmail: String = "mock-user@example.com"
    public var circleTicket: String? = """
    <SignedTicket>
      <CircleId>00000000-0000-0000-0009-123456789abc</CircleId>
      <Signature>MOCK_VALID_SIGNATURE</Signature>
    </SignedTicket>
    """

    public var contacts: [MockABContact] = []
    public var groups: [MockABGroup] = []
    public var circles: [MockABCircles] = []

    // Recorded telemetry
    public private(set) var recordedRequests: [MockABCHRequest] = []

    public init() {
        populateDefaultRoster()
    }

    public func populateDefaultRoster() {
        lock.lock()
        defer { lock.unlock() }

        groups = [
            MockABGroup(id: "00000000-0000-0000-0001-000000000001", name: "Coworkers"),
            MockABGroup(id: "00000000-0000-0000-0001-000000000002", name: "Friends")
        ]

        contacts = [
            MockABContact(
                id: "11111111-2222-3333-4444-555555555551",
                email: "selin@msngr.dev",
                displayName: "Selin (Engineering)",
                nickname: "Selin",
                groupId: "00000000-0000-0000-0001-000000000001"
            ),
            MockABContact(
                id: "11111111-2222-3333-4444-555555555552",
                email: "mert@msngr.dev",
                displayName: "Mert",
                nickname: "Mert",
                groupId: "00000000-0000-0000-0001-000000000002"
            ),
            MockABContact(
                id: "11111111-2222-3333-4444-555555555553",
                email: "derya@msngr.dev",
                displayName: "Derya",
                nickname: "Derya"
            ),
            MockABContact(
                id: "11111111-2222-3333-4444-555555555554",
                email: "can@msngr.dev",
                displayName: "Can",
                nickname: nil
            ),
            MockABContact(
                id: "11111111-2222-3333-4444-555555555555",
                email: "zeynep@msngr.dev",
                displayName: "Zeynep",
                nickname: "Zeynep"
            ),
            MockABContact(
                id: "11111111-2222-3333-4444-555555555556",
                email: "ece@msngr.dev",
                displayName: "Ece",
                nickname: "Ece"
            ),
            MockABContact(
                id: "11111111-2222-3333-4444-555555555557",
                email: "deniz@msngr.dev",
                displayName: "Deniz",
                nickname: "Deniz",
                isBlocked: true
            )
        ]

        circles = [
            MockABCircles(
                id: "00000000-0000-0000-0009-123456789abc",
                name: "Development Circle",
                displayName: "Development Circle"
            )
        ]
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
        populateDefaultRoster()
    }

    // MARK: - State Inspection & Manipulation Helpers

    public func getContacts() -> [MockABContact] {
        lock.lock()
        defer { lock.unlock() }
        return contacts
    }

    public func findContact(email: String) -> MockABContact? {
        lock.lock()
        defer { lock.unlock() }
        return contacts.first(where: { $0.email.lowercased() == email.lowercased() && !$0.isDeleted })
    }

    public func addContact(_ contact: MockABContact) {
        lock.lock()
        defer { lock.unlock() }
        contacts.append(contact)
    }

    public func removeContact(email: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = contacts.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
            contacts[idx].isDeleted = true
        }
    }

    public func setBlocked(email: String, isBlocked: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = contacts.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
            contacts[idx].isBlocked = isBlocked
        }
    }

    public func getRecordedRequests() -> [MockABCHRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    public func clearRecordedRequests() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
    }

    // MARK: - SOAP Dispatcher

    public func handle(request: URLRequest, body: Data) -> MockSOAPResponse? {
        let xmlString = String(data: body, encoding: .utf8) ?? ""
        let soapAction = request.value(forHTTPHeaderField: "SOAPAction") ?? ""
        let path = request.url?.path ?? ""

        lock.lock()
        recordedRequests.append(MockABCHRequest(
            path: path,
            soapAction: soapAction,
            body: xmlString
        ))
        lock.unlock()

        if soapAction.contains("ABFindContactsPaged") || xmlString.contains("ABFindContactsPaged") {
            return MockSOAPResponse(statusCode: 200, xml: buildFindContactsResponseXml())
        }

        if soapAction.contains("FindMembership") || xmlString.contains("FindMembership") {
            return MockSOAPResponse(statusCode: 200, xml: buildFindMembershipResponseXml())
        }

        if soapAction.contains("ABContactAdd") || xmlString.contains("ABContactAdd") {
            return handleContactAdd(xmlString)
        }

        if soapAction.contains("ABContactUpdate") || xmlString.contains("ABContactUpdate") {
            return handleContactUpdate(xmlString)
        }

        if soapAction.contains("AddMember") || xmlString.contains("AddMember") {
            return handleAddMember(xmlString)
        }

        if soapAction.contains("DeleteMember") || xmlString.contains("DeleteMember") {
            return handleDeleteMember(xmlString)
        }

        return MockSOAPResponse(statusCode: 200, xml: "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"><soap:Body/></soap:Envelope>")
    }

    // MARK: - Handlers

    private func handleContactAdd(_ xml: String) -> MockSOAPResponse {
        guard let email = extractTag(xml, tag: "passportName") ?? extractTag(xml, tag: "PassportName") else {
            return MockSOAPResponse(statusCode: 500, xml: buildSoapFault(code: "InvalidEmail", message: "Enter a valid email address."))
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.contains("@") || !trimmedEmail.contains(".") {
            return MockSOAPResponse(statusCode: 500, xml: buildSoapFault(code: "InvalidEmail", message: "Enter a valid email address."))
        }

        lock.lock()
        let exists = contacts.contains(where: { $0.email.lowercased() == trimmedEmail.lowercased() && !$0.isDeleted })
        if exists {
            lock.unlock()
            return MockSOAPResponse(statusCode: 500, xml: buildSoapFault(code: "ContactAlreadyExists", message: "This person is already in your contacts."))
        }

        let displayName = extractTag(xml, tag: "displayName")
            ?? extractTag(xml, tag: "DisplayName")
            ?? trimmedEmail.components(separatedBy: "@").first
            ?? trimmedEmail
        let newGuid = UUID().uuidString.lowercased()
        let newContact = MockABContact(
            id: newGuid,
            email: trimmedEmail,
            displayName: displayName,
            nickname: displayName
        )
        contacts.append(newContact)
        lock.unlock()

        let responseXml = """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ABContactAddResponse xmlns="http://www.msn.com/webservices/AddressBook">
              <ABContactAddResult>
                <guid>\(newGuid)</guid>
              </ABContactAddResult>
            </ABContactAddResponse>
          </soap:Body>
        </soap:Envelope>
        """
        return MockSOAPResponse(statusCode: 200, xml: responseXml)
    }

    private func handleContactUpdate(_ xml: String) -> MockSOAPResponse {
        let contactId = extractTag(xml, tag: "contactId") ?? extractTag(xml, tag: "ContactId")
        let isMessenger = extractTag(xml, tag: "isMessengerUser") ?? extractTag(xml, tag: "IsMessengerUser")

        lock.lock()
        if let id = contactId {
            if let idx = contacts.firstIndex(where: { $0.id.lowercased() == id.lowercased() }) {
                if let isMsg = isMessenger, isMsg == "false" {
                    contacts[idx].isMessengerUser = false
                }
            }
        }
        lock.unlock()

        let responseXml = """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ABContactUpdateResponse xmlns="http://www.msn.com/webservices/AddressBook"/>
          </soap:Body>
        </soap:Envelope>
        """
        return MockSOAPResponse(statusCode: 200, xml: responseXml)
    }

    private func handleAddMember(_ xml: String) -> MockSOAPResponse {
        let role = extractTag(xml, tag: "MemberRole") ?? "Allow"
        let email = extractTag(xml, tag: "PassportName") ?? extractTag(xml, tag: "passportName") ?? ""

        lock.lock()
        if !email.isEmpty {
            if let idx = contacts.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
                if role == "Block" { contacts[idx].isBlocked = true }
                if role == "Allow" { contacts[idx].isBlocked = false }
            }
        }
        lock.unlock()

        return MockSOAPResponse(statusCode: 200, xml: """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <AddMemberResponse xmlns="http://www.msn.com/webservices/AddressBook"/>
          </soap:Body>
        </soap:Envelope>
        """)
    }

    private func handleDeleteMember(_ xml: String) -> MockSOAPResponse {
        let role = extractTag(xml, tag: "MemberRole") ?? ""
        let email = extractTag(xml, tag: "PassportName") ?? extractTag(xml, tag: "passportName") ?? ""

        lock.lock()
        if !email.isEmpty {
            if let idx = contacts.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
                if role == "Block" { contacts[idx].isBlocked = false }
            }
        }
        lock.unlock()

        return MockSOAPResponse(statusCode: 200, xml: """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <DeleteMemberResponse xmlns="http://www.msn.com/webservices/AddressBook"/>
          </soap:Body>
        </soap:Envelope>
        """)
    }

    // MARK: - XML Builders

    private func buildFindContactsResponseXml() -> String {
        lock.lock()
        let currentOwnerName = ownerDisplayName
        let currentOwnerEmail = ownerEmail
        let currentContacts = contacts
        let currentGroups = groups
        let currentCircles = circles
        let currentCircleTicket = circleTicket
        lock.unlock()

        var groupNodes = ""
        for grp in currentGroups where !grp.isDeleted {
            groupNodes += """
              <Group>
                <groupId>\(grp.id)</groupId>
                <groupInfo>
                  <name>\(grp.name)</name>
                  <fDeleted>false</fDeleted>
                </groupInfo>
              </Group>
            """
        }

        var contactNodes = ""
        for contact in currentContacts where !contact.isDeleted && contact.isMessengerUser {
            let nickAnnotation = contact.nickname.map {
                "<annotations><Annotation><Name>AB.NickName</Name><Value>\($0)</Value></Annotation></annotations>"
            } ?? ""

            let groupFilter = contact.groupId.map {
                "<groupFilter><groupId>\($0)</groupId></groupFilter>"
            } ?? ""

            contactNodes += """
            <Contact>
              <contactId>\(contact.id)</contactId>
              <contactInfo>
                <contactType>Regular</contactType>
                <passportName>\(contact.email)</passportName>
                <displayName>\(contact.displayName)</displayName>
                <isMessengerUser>true</isMessengerUser>
                \(groupFilter)
                \(nickAnnotation)
              </contactInfo>
              <fDeleted>false</fDeleted>
            </Contact>
            """
        }

        var circleNodes = ""
        for circle in currentCircles where !circle.isDeleted {
            circleNodes += """
            <CircleInverseInfo>
              <Id>\(circle.id)</Id>
              <Name>\(circle.name)</Name>
              <DisplayName>\(circle.displayName)</DisplayName>
              <HostedDomain>live.com</HostedDomain>
              <State>Accepted</State>
              <Deleted>false</Deleted>
            </CircleInverseInfo>
            """
        }

        let circleTicketXml = currentCircleTicket.map { "<CircleTicket>\($0)</CircleTicket>" } ?? ""

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xmlns:xsd="http://www.w3.org/2001/XMLSchema"
          xmlns:ns1="http://www.msn.com/webservices/AddressBook">
          <soap:Body>
            <ABFindContactsPagedResponse xmlns="http://www.msn.com/webservices/AddressBook">
              <ABFindContactsPagedResult>
                <Groups>
                  \(groupNodes)
                </Groups>
                <Contacts>
                  <Contact>
                    <contactInfo>
                      <contactType>Me</contactType>
                      <passportName>\(currentOwnerEmail)</passportName>
                      <displayName>\(currentOwnerName)</displayName>
                    </contactInfo>
                    <fDeleted>false</fDeleted>
                  </Contact>
                  \(contactNodes)
                </Contacts>
                <CircleResult>
                  <Circles>
                    \(circleNodes)
                  </Circles>
                  \(circleTicketXml)
                </CircleResult>
              </ABFindContactsPagedResult>
            </ABFindContactsPagedResponse>
          </soap:Body>
        </soap:Envelope>
        """
    }

    private func buildFindMembershipResponseXml() -> String {
        lock.lock()
        let currentContacts = contacts
        lock.unlock()

        var allowMembers = ""
        var blockMembers = ""
        var pendingMembers = ""

        for contact in currentContacts where !contact.isDeleted {
            if contact.isBlocked {
                blockMembers += """
                <Member xsi:type="PassportMember">
                  <Type>Passport</Type>
                  <PassportName>\(contact.email)</PassportName>
                  <DisplayName>\(contact.displayName)</DisplayName>
                  <Deleted>false</Deleted>
                </Member>
                """
            } else if contact.isPending {
                pendingMembers += """
                <Member xsi:type="PassportMember">
                  <Type>Passport</Type>
                  <MembershipId>Pending/\(contact.id)</MembershipId>
                  <PassportName>\(contact.email)</PassportName>
                  <DisplayName>\(contact.displayName)</DisplayName>
                  <State>Pending</State>
                  <Deleted>false</Deleted>
                </Member>
                """
            } else {
                allowMembers += """
                <Member xsi:type="PassportMember">
                  <Type>Passport</Type>
                  <PassportName>\(contact.email)</PassportName>
                  <DisplayName>\(contact.displayName)</DisplayName>
                  <Deleted>false</Deleted>
                </Member>
                """
            }
        }

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <soap:Body>
            <FindMembershipResponse xmlns="http://www.msn.com/webservices/AddressBook">
              <FindMembershipResult>
                <Services>
                  <Service>
                    <Info>
                      <Handle>
                        <Id>1</Id>
                        <Type>Messenger</Type>
                      </Handle>
                    </Info>
                    <Memberships>
                      <Membership>
                        <MemberRole>Allow</MemberRole>
                        <Members>\(allowMembers)</Members>
                        <MembershipIsComplete>true</MembershipIsComplete>
                      </Membership>
                      <Membership>
                        <MemberRole>Block</MemberRole>
                        <Members>\(blockMembers)</Members>
                        <MembershipIsComplete>true</MembershipIsComplete>
                      </Membership>
                      <Membership>
                        <MemberRole>Pending</MemberRole>
                        <Members>\(pendingMembers)</Members>
                        <MembershipIsComplete>true</MembershipIsComplete>
                      </Membership>
                    </Memberships>
                  </Service>
                </Services>
              </FindMembershipResult>
            </FindMembershipResponse>
          </soap:Body>
        </soap:Envelope>
        """
    }

    private func buildSoapFault(code: String, message: String) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>soap:Client</faultcode>
              <faultstring>\(message)</faultstring>
              <detail>
                <errorcode>\(code)</errorcode>
              </detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
    }

    private func extractTag(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Data Models

public struct MockABContact: Sendable, Equatable {
    public var id: String
    public var email: String
    public var displayName: String
    public var nickname: String?
    public var groupId: String?
    public var isMessengerUser: Bool
    public var isDeleted: Bool
    public var isBlocked: Bool
    public var isPending: Bool

    public init(
        id: String,
        email: String,
        displayName: String,
        nickname: String? = nil,
        groupId: String? = nil,
        isMessengerUser: Bool = true,
        isDeleted: Bool = false,
        isBlocked: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.nickname = nickname
        self.groupId = groupId
        self.isMessengerUser = isMessengerUser
        self.isDeleted = isDeleted
        self.isBlocked = isBlocked
        self.isPending = isPending
    }
}

public struct MockABGroup: Sendable, Equatable {
    public var id: String
    public var name: String
    public var isDeleted: Bool

    public init(id: String, name: String, isDeleted: Bool = false) {
        self.id = id
        self.name = name
        self.isDeleted = isDeleted
    }
}

public struct MockABCircles: Sendable, Equatable {
    public var id: String
    public var name: String
    public var displayName: String
    public var isDeleted: Bool

    public init(id: String, name: String, displayName: String, isDeleted: Bool = false) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.isDeleted = isDeleted
    }
}

public struct MockABCHRequest: Sendable {
    public let path: String
    public let soapAction: String
    public let body: String

    public init(path: String, soapAction: String, body: String) {
        self.path = path
        self.soapAction = soapAction
        self.body = body
    }
}
