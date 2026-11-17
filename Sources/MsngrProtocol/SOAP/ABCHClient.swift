import Foundation
import MsngrCore

/// Membership list role in ABCH Address Book.
public enum MemberRole: String, Sendable {
    case allow = "Allow"
    case block = "Block"
    case pending = "Pending"
}

/// Represents a member entry in an ABCH membership list (`Allow`, `Block`, `Pending`).
public struct ABMember: Sendable, Equatable {
    public let email: String
    public let role: MemberRole

    public init(email: String, role: MemberRole) {
        self.email = email
        self.role = role
    }
}

/// Result of `ABFindContactsPaged` SOAP query containing contacts, groups, and optional Circle ticket.
public struct ABFindContactsResult: Sendable {
    public let contacts: [Contact]
    public let groups: [ContactGroup]
    public let circleTicket: String?

    public init(contacts: [Contact], groups: [ContactGroup], circleTicket: String?) {
        self.contacts = contacts
        self.groups = groups
        self.circleTicket = circleTicket
    }
}

/// Errors thrown by ABCH Address Book SOAP operations.
public enum AddressBookError: Error, Equatable, Sendable {
    case invalidEmail
    case contactAlreadyExists
    case serviceFault(String)
    case unauthorized
}

/// Client for Windows Live Address Book Clearing House (ABCH) SOAP web services.
public final class ABCHClient: @unchecked Sendable {
    /// Configurable default URLSession used when no explicit session is passed.
    public static var defaultSession: URLSession = .shared

    public let endpoint: URL
    private let session: URLSession
    public var logHandler: (@Sendable (String) -> Void)?

    private func logMessage(_ msg: String) {
        logHandler?(msg)
        #if DEBUG
        print("[ABCH] \(msg)")
        #endif
    }

    public init(
        endpoint: URL = URL(string: "https://contacts.msn.com/abservice/abservice.asmx")!,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.session = session ?? Self.defaultSession
    }

    public func findContacts(ticket: String) async throws -> ABFindContactsResult {
        logMessage("Fetching contacts from ABCH service at \(endpoint.absoluteString)...")
        let soap = SOAPXmlBuilder.buildABFindContactsPaged(ticket: ticket)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("http://www.msn.com/webservices/AddressBook/ABFindContactsPaged", forHTTPHeaderField: "SOAPAction")
        req.httpBody = Data(soap.utf8)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            logMessage("? ABCH request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw AddressBookError.serviceFault("Failed to fetch address book")
        }

        let xml = String(data: data, encoding: .utf8) ?? ""
        let result = parseContactsResult(from: xml)
        logMessage("? ABCH returned \(result.contacts.count) contacts and \(result.groups.count) groups")
        return result
    }

    public func findMembership(ticket: String, role: MemberRole) async throws -> [ABMember] {
        let soap = SOAPXmlBuilder.buildFindMembership(ticket: ticket, role: role.rawValue)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("http://www.msn.com/webservices/AddressBook/FindMembership", forHTTPHeaderField: "SOAPAction")
        req.httpBody = Data(soap.utf8)

        let (data, _) = try await session.data(for: req)
        let xml = String(data: data, encoding: .utf8) ?? ""
        return parseMembership(from: xml, targetRole: role)
    }

    public func addContact(email: String, displayName: String = "") async throws -> String {
        guard email.contains("@"), email.contains(".") else {
            throw AddressBookError.invalidEmail
        }

        let soap = SOAPXmlBuilder.buildABContactAdd(email: email, displayName: displayName)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("http://www.msn.com/webservices/AddressBook/ABContactAdd", forHTTPHeaderField: "SOAPAction")
        req.httpBody = Data(soap.utf8)

        let (data, response) = try await session.data(for: req)
        let xml = String(data: data, encoding: .utf8) ?? ""

        if xml.contains("ContactAlreadyExists") {
            throw AddressBookError.contactAlreadyExists
        }
        if xml.contains("InvalidEmail") {
            throw AddressBookError.invalidEmail
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AddressBookError.serviceFault("Contact add fault")
        }

        return SOAPXmlBuilder.extractTag(xml, tag: "guid") ?? UUID().uuidString.lowercased()
    }

    public func removeContact(contactGuid: String) async throws {
        let soap = SOAPXmlBuilder.buildABContactUpdate(contactGuid: contactGuid, isMessengerUser: false)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("http://www.msn.com/webservices/AddressBook/ABContactUpdate", forHTTPHeaderField: "SOAPAction")
        req.httpBody = Data(soap.utf8)

        _ = try await session.data(for: req)
    }

    private func parseContactsResult(from xml: String) -> ABFindContactsResult {
        var contacts: [Contact] = []
        var groups: [ContactGroup] = []

        let groupPattern = "<Group[^>]*>(.*?)</Group>"
        if let gRegex = try? NSRegularExpression(pattern: groupPattern, options: .dotMatchesLineSeparators) {
            let matches = gRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..<xml.endIndex, in: xml))
            for m in matches {
                guard let r = Range(m.range(at: 1), in: xml) else { continue }
                let block = String(xml[r])
                let gId = SOAPXmlBuilder.extractTag(block, tag: "groupId") ?? UUID().uuidString
                let gName = SOAPXmlBuilder.extractTag(block, tag: "name") ?? "Group"
                groups.append(ContactGroup(id: gId, name: gName))
            }
        }

        let contactPattern = "<Contact[^>]*>(.*?)</Contact>"
        if let cRegex = try? NSRegularExpression(pattern: contactPattern, options: .dotMatchesLineSeparators) {
            let matches = cRegex.matches(in: xml, options: [], range: NSRange(xml.startIndex..<xml.endIndex, in: xml))
            for m in matches {
                guard let r = Range(m.range(at: 1), in: xml) else { continue }
                let block = String(xml[r])
                let id = SOAPXmlBuilder.extractTag(block, tag: "contactId") ?? UUID().uuidString
                let email = SOAPXmlBuilder.extractTag(block, tag: "passportName") ?? ""
                let name = SOAPXmlBuilder.extractTag(block, tag: "displayName") ?? email
                let nick = SOAPXmlBuilder.extractTag(block, tag: "Value") ?? name
                let gId = SOAPXmlBuilder.extractTag(block, tag: "groupId")
                let isBlocked = block.contains("<isBlocked>true</isBlocked>")

                if !email.isEmpty {
                    contacts.append(Contact(
                        id: id,
                        email: email,
                        displayName: nick,
                        presence: .online,
                        groupId: gId,
                        isBlocked: isBlocked
                    ))
                }
            }
        }

        let circleTicket = SOAPXmlBuilder.extractTag(xml, tag: "CircleTicket")
        return ABFindContactsResult(contacts: contacts, groups: groups, circleTicket: circleTicket)
    }

    private func parseMembership(from xml: String, targetRole: MemberRole) -> [ABMember] {
        var members: [ABMember] = []
        let pattern = "<Member[^>]*>(.*?)</Member>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..<xml.endIndex, in: xml))

        for m in matches {
            guard let r = Range(m.range(at: 1), in: xml) else { continue }
            let block = String(xml[r])
            let email = SOAPXmlBuilder.extractTag(block, tag: "PassportName")
                ?? SOAPXmlBuilder.extractTag(block, tag: "passportName") ?? ""
            if !email.isEmpty {
                members.append(ABMember(email: email, role: targetRole))
            }
        }
        return members
    }
}
