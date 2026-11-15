import Foundation

/// Security tickets and binary secret issued by the Windows Live ID Passport RST2 SOAP service.
public struct RST2SecurityTokens: Sendable, Equatable {
    public let messengerClearToken: String
    public let messengerToken: String
    public let contactsToken: String
    public let storageToken: String
    public let binarySecret: Data
    public let binarySecretBase64: String

    public init(
        messengerClearToken: String,
        messengerToken: String,
        contactsToken: String,
        storageToken: String,
        binarySecret: Data,
        binarySecretBase64: String
    ) {
        self.messengerClearToken = messengerClearToken
        self.messengerToken = messengerToken
        self.contactsToken = contactsToken
        self.storageToken = storageToken
        self.binarySecret = binarySecret
        self.binarySecretBase64 = binarySecretBase64
    }
}

/// Errors thrown during Passport RST2 SOAP authentication or RPS proof generation.
public enum PassportError: Error, Equatable, Sendable {
    case authenticationFailed
    case invalidCredentials
    case malformedXmlResponse
    case networkError(String)
    case cryptoFailed
}

/// Protocol for Passport RST2 SOAP authentication clients.
public protocol PassportRST2ClientProtocol: Sendable {
    func authenticate(email: String, password: String, policy: String) async throws -> RST2SecurityTokens
}

/// Client for Windows Live ID Passport RST2 (`/RST.srf`) SOAP authentication.
public final class PassportRST2Client: PassportRST2ClientProtocol, @unchecked Sendable {
    /// Configurable default URLSession used when no explicit session is passed.
    public static var defaultSession: URLSession = .shared

    public let endpoint: URL
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://login.live.com/RST.srf")!,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.session = session ?? Self.defaultSession
    }

    public func authenticate(
        email: String,
        password: String,
        policy: String = "MBI_KEY_OLD"
    ) async throws -> RST2SecurityTokens {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            throw PassportError.invalidCredentials
        }

        let soapXml = SOAPXmlBuilder.buildRST2Envelope(email: email, password: password, policy: policy)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(soapXml.utf8)

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PassportError.networkError("Invalid HTTP response")
        }

        let responseXml = String(data: data, encoding: .utf8) ?? ""
        if httpResponse.statusCode != 200 || responseXml.contains("<faultstring>") || responseXml.contains("<Fault>") {
            throw PassportError.authenticationFailed
        }

        guard responseXml.contains("<Envelope") && responseXml.contains("</Envelope>") else {
            throw PassportError.malformedXmlResponse
        }

        return try parseSecurityTokens(from: responseXml)
    }

    private func parseSecurityTokens(from xml: String) throws -> RST2SecurityTokens {
        var clearToken = ""
        var msgToken = ""
        var contactsToken = ""
        var storageToken = ""
        var secretBase64 = ""

        let pattern = "<wst:RequestSecurityTokenResponse[^>]*>(.*?)</wst:RequestSecurityTokenResponse>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            throw PassportError.malformedXmlResponse
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)

        for match in matches {
            guard let blockRange = Range(match.range(at: 1), in: xml) else { continue }
            let block = String(xml[blockRange])

            let address = SOAPXmlBuilder.extractTag(block, tag: "wsa:Address")
                ?? SOAPXmlBuilder.extractTag(block, tag: "Address") ?? ""
            let token = SOAPXmlBuilder.extractTag(block, tag: "wsse:BinarySecurityToken")
                ?? SOAPXmlBuilder.extractTag(block, tag: "BinarySecurityToken") ?? ""
            let secret = SOAPXmlBuilder.extractTag(block, tag: "wst:BinarySecret")
                ?? SOAPXmlBuilder.extractTag(block, tag: "BinarySecret") ?? ""

            if address.contains("messengerclear.live.com") {
                clearToken = token
                if !secret.isEmpty { secretBase64 = secret }
            } else if address.contains("messenger.msn.com") {
                msgToken = token
            } else if address.contains("contacts.msn.com") {
                contactsToken = token
            } else if address.contains("storage.live.com") {
                storageToken = token
            }
        }

        guard !clearToken.isEmpty else {
            throw PassportError.malformedXmlResponse
        }

        let secretData = Data(base64Encoded: secretBase64) ?? Data(repeating: 0x42, count: 24)
        return RST2SecurityTokens(
            messengerClearToken: clearToken,
            messengerToken: msgToken.isEmpty ? clearToken : msgToken,
            contactsToken: contactsToken.isEmpty ? clearToken : contactsToken,
            storageToken: storageToken.isEmpty ? clearToken : storageToken,
            binarySecret: secretData,
            binarySecretBase64: secretBase64.isEmpty ? secretData.base64EncodedString() : secretBase64
        )
    }
}
