//
// MockPassportServer.swift
// MsngrIntegrationTests
//
// In-memory mock server for Windows Live ID / Passport RST2 SOAP authentication.
// Validates credentials, parses SOAP XML envelopes, and returns RST2 XML tokens.
//

import Foundation

/// In-memory mock server for Windows Live ID / Passport RST2 SOAP authentication.
public final class MockPassportServer: @unchecked Sendable {
    private let lock = NSLock()

    // Configurable credentials (email: password)
    public var registeredUsers: [String: String] = [
        "mock-user@example.com": "mock-password",
        "friend@msngr.dev": "password123",
        "selin@msngr.dev": "password123",
        "mert@msngr.dev": "password123"
    ]

    // Deterministic tickets
    public var messengerTicket: String = "mock-messenger-ticket-12345"
    public var contactsTicket: String = "t=mock-contacts-ticket&amp;p=mock"
    public var storageTicket: String = "t=mock-storage-ticket&amp;p=mock"
    public var offlineTicket: String = "t=mock-offline-ticket&amp;p=mock"
    public var secureTicket: String = "t=mock-secure-ticket&amp;p=mock"
    public var supTicket: String = "t=mock-sup-ticket&amp;p=mock"

    /// Base64 binary secret for HMAC-SHA1 / 3DES RPS proof derivation (24 bytes).
    public var binarySecretBase64: String = Data(repeating: 0x42, count: 24).base64EncodedString()

    // Boundary & error flags
    public var forceSoapFault: Bool = false
    public var faultMessage: String = "The community server rejected these credentials."
    public var rejectEmailSubstrings: [String] = ["fail", "invalid"]

    // Recorded telemetry
    public private(set) var recordedRequests: [MockPassportRequest] = []

    public init() {}

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
        forceSoapFault = false
        faultMessage = "The community server rejected these credentials."
        binarySecretBase64 = Data(repeating: 0x42, count: 24).base64EncodedString()
        registeredUsers = [
            "mock-user@example.com": "mock-password",
            "friend@msngr.dev": "password123",
            "selin@msngr.dev": "password123",
            "mert@msngr.dev": "password123"
        ]
    }

    public func registerUser(email: String, password: String) {
        lock.lock()
        defer { lock.unlock() }
        registeredUsers[email.lowercased()] = password
    }

    public func recordRequest(_ req: MockPassportRequest) {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(req)
    }

    public func getRecordedRequests() -> [MockPassportRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    public var lastRequest: MockPassportRequest? {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.last
    }

    public func clearRecordedRequests() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
    }

    // MARK: - SOAP Dispatcher

    public func handle(request: URLRequest, body: Data) -> MockSOAPResponse? {
        let xmlString = String(data: body, encoding: .utf8) ?? ""

        let username = extractTag(xmlString, tag: "wsse:Username")
            ?? extractTag(xmlString, tag: "Username")
            ?? ""
        let password = extractTag(xmlString, tag: "wsse:Password")
            ?? extractTag(xmlString, tag: "Password")
            ?? ""
        let policy = extractAttribute(xmlString, tag: "wsse:PolicyReference", attribute: "URI")
            ?? extractAttribute(xmlString, tag: "PolicyReference", attribute: "URI")
            ?? ""

        let passportReq = MockPassportRequest(
            url: request.url?.absoluteString ?? "",
            username: username,
            password: password,
            policy: policy,
            rawBody: xmlString
        )
        recordRequest(passportReq)

        // Evaluate Fault conditions
        lock.lock()
        let shouldFault = forceSoapFault || shouldReject(username: username, password: password)
        let faultMsg = faultMessage
        lock.unlock()

        if shouldFault {
            return MockSOAPResponse(statusCode: 500, xml: buildSoapFaultXml(message: faultMsg))
        }

        // Build successful RST2 response
        let responseXml = buildRst2SuccessResponseXml()
        return MockSOAPResponse(statusCode: 200, xml: responseXml)
    }

    private func shouldReject(username: String, password: String) -> Bool {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        for pattern in rejectEmailSubstrings {
            if username.localizedCaseInsensitiveContains(pattern) {
                return true
            }
        }

        guard let expected = registeredUsers[username.lowercased()] else {
            // Unregistered user check: if it contains "@" and no reject substring,
            // we allow generic mock users unless password is empty
            return false
        }

        // Legacy MSN Passport truncates passwords to 16 characters
        let truncatedExpected = String(expected.prefix(16))
        let truncatedProvided = String(password.prefix(16))
        return truncatedExpected != truncatedProvided
    }

    // MARK: - XML Templates

    private func buildRst2SuccessResponseXml() -> String {
        lock.lock()
        let msgTicket = messengerTicket
        let conTicket = contactsTicket
        let storTicket = storageTicket
        let offTicket = offlineTicket
        let secTicket = secureTicket
        let sTicket = supTicket
        let secret = binarySecretBase64
        lock.unlock()

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"
          xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust"
          xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing"
          xmlns:wsse="http://schemas.xmlsoap.org/ws/2003/06/secext">
          <Body>
            <wst:RequestSecurityTokenResponseCollection xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust">
              <wst:RequestSecurityTokenResponse>
                <wsa:EndpointReference>
                  <wsa:Address>messengerclear.live.com</wsa:Address>
                </wsa:EndpointReference>
                <wsa:Address>messengerclear.live.com</wsa:Address>
                <wsse:BinarySecurityToken Id="Compact1">\(msgTicket)</wsse:BinarySecurityToken>
                <wst:BinarySecret>\(secret)</wst:BinarySecret>
              </wst:RequestSecurityTokenResponse>
              <wst:RequestSecurityTokenResponse>
                <wsa:EndpointReference>
                  <wsa:Address>contacts.msn.com</wsa:Address>
                </wsa:EndpointReference>
                <wsa:Address>contacts.msn.com</wsa:Address>
                <wsse:BinarySecurityToken Id="Compact2">\(conTicket)</wsse:BinarySecurityToken>
              </wst:RequestSecurityTokenResponse>
              <wst:RequestSecurityTokenResponse>
                <wsa:EndpointReference>
                  <wsa:Address>storage.live.com</wsa:Address>
                </wsa:EndpointReference>
                <wsa:Address>storage.live.com</wsa:Address>
                <wsse:BinarySecurityToken Id="Compact3">\(storTicket)</wsse:BinarySecurityToken>
              </wst:RequestSecurityTokenResponse>
              <wst:RequestSecurityTokenResponse>
                <wsa:EndpointReference>
                  <wsa:Address>messenger.msn.com</wsa:Address>
                </wsa:EndpointReference>
                <wsa:Address>messenger.msn.com</wsa:Address>
                <wsse:BinarySecurityToken Id="Compact4">\(offTicket)</wsse:BinarySecurityToken>
              </wst:RequestSecurityTokenResponse>
              <wst:RequestSecurityTokenResponse>
                <wsa:EndpointReference>
                  <wsa:Address>messengersecure.live.com</wsa:Address>
                </wsa:EndpointReference>
                <wsa:Address>messengersecure.live.com</wsa:Address>
                <wsse:BinarySecurityToken Id="Compact5">\(secTicket)</wsse:BinarySecurityToken>
              </wst:RequestSecurityTokenResponse>
              <wst:RequestSecurityTokenResponse>
                <wsa:EndpointReference>
                  <wsa:Address>sup.live.com</wsa:Address>
                </wsa:EndpointReference>
                <wsa:Address>sup.live.com</wsa:Address>
                <wsse:BinarySecurityToken Id="Compact6">\(sTicket)</wsse:BinarySecurityToken>
              </wst:RequestSecurityTokenResponse>
            </wst:RequestSecurityTokenResponseCollection>
          </Body>
        </Envelope>
        """
    }

    private func buildSoapFaultXml(message: String) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">
          <S:Body>
            <S:Fault>
              <faultcode>wsse:FailedAuthentication</faultcode>
              <faultstring>\(message)</faultstring>
              <detail>
                <psf:error xmlns:psf="http://schemas.microsoft.com/Passport/SoapServices/SOAPFault">
                  <psf:value>0x80048821</psf:value>
                  <psf:internalerror>
                    <psf:code>0x80041012</psf:code>
                    <psf:text>\(message)</psf:text>
                  </psf:internalerror>
                </psf:error>
              </detail>
            </S:Fault>
          </S:Body>
        </S:Envelope>
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

    private func extractAttribute(_ xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\\b\(attribute)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[captureRange])
    }
}

// MARK: - MockPassportRequest

public struct MockPassportRequest: Sendable {
    public let url: String
    public let username: String
    public let password: String
    public let policy: String
    public let rawBody: String

    public init(url: String, username: String, password: String, policy: String, rawBody: String) {
        self.url = url
        self.username = username
        self.password = password
        self.policy = policy
        self.rawBody = rawBody
    }
}
