import Foundation
import MsngrCore

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
    case missingBinarySecret
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
    public private(set) var lastFaultString: String?
    public var logHandler: (@Sendable (String) -> Void)?

    private func logMessage(_ msg: String) {
        logHandler?(msg)
        #if DEBUG
        print("[Passport] \(msg)")
        #endif
    }

    public init(
        endpoint: URL = ServerConfig.crosstalk.authServerUrl ?? URL(string: "https://ctas.login.ugnet.gay/RST.srf")!,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        self.session = session ?? Self.defaultSession
    }

    /// Formats an authentic Windows Live ID Passport RST2 SOAP request with PPCRL envelope structure.
    public static func buildPPCRLEnvelope(email: String, password: String, policy: String = "MBI_KEY_OLD") -> String {
        let truncatedPassword = String(password.prefix(16))
        let escapedEmail = SOAPXmlBuilder.escapeXml(email)
        let escapedPassword = SOAPXmlBuilder.escapeXml(truncatedPassword)
        let escapedPolicy = SOAPXmlBuilder.escapeXml(policy)

        let requests: [(id: Int, domain: String, policyUri: String)] = [
            (1, "messengerclear.live.com", escapedPolicy),
            (2, "messenger.msn.com", "?id=507"),
            (3, "contacts.msn.com", "MBI"),
            (4, "messengersecure.live.com", "MBI_SSL"),
            (5, "storage.live.com", "MBI"),
            (6, "sup.live.com", "MBI")
        ]

        var rstBody = ""
        for r in requests {
            rstBody += """
            <wst:RequestSecurityToken Id="RST\(r.id)">
              <wst:RequestType>http://schemas.xmlsoap.org/ws/2004/04/security/trust/Issue</wst:RequestType>
              <wsp:AppliesTo><wsa:EndpointReference><wsa:Address>\(r.domain)</wsa:Address></wsa:EndpointReference></wsp:AppliesTo>
              <wsse:PolicyReference URI="\(r.policyUri)"></wsse:PolicyReference>
            </wst:RequestSecurityToken>
            """
        }

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"
          xmlns:wsse="http://schemas.xmlsoap.org/ws/2003/06/secext"
          xmlns:wsp="http://schemas.xmlsoap.org/ws/2002/12/policy"
          xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing"
          xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust">
          <Header>
            <ps:AuthInfo xmlns:ps="http://schemas.microsoft.com/Passport/SoapServices/PPCRL" Id="PPAuthInfo">
              <ps:HostingApp>{7108E71A-9926-4FCB-BCC9-9A9D3F32E423}</ps:HostingApp>
              <ps:BinaryVersion>4</ps:BinaryVersion><ps:UIVersion>1</ps:UIVersion>
              <ps:Cookies></ps:Cookies><ps:RequestParams>AQAAAAIAAABsYwQAAAAxMDMz</ps:RequestParams>
            </ps:AuthInfo>
            <wsse:Security><wsse:UsernameToken Id="user">
              <wsse:Username>\(escapedEmail)</wsse:Username>
              <wsse:Password>\(escapedPassword)</wsse:Password>
            </wsse:UsernameToken></wsse:Security>
          </Header>
          <Body>
            <ps:RequestMultipleSecurityTokens xmlns:ps="http://schemas.microsoft.com/Passport/SoapServices/PPCRL" Id="RSTS">
              <wst:RequestSecurityToken Id="RST0">
                <wst:RequestType>http://schemas.xmlsoap.org/ws/2004/04/security/trust/Issue</wst:RequestType>
                <wsp:AppliesTo><wsa:EndpointReference><wsa:Address>http://Passport.NET/tb</wsa:Address></wsa:EndpointReference></wsp:AppliesTo>
              </wst:RequestSecurityToken>
              \(rstBody)
            </ps:RequestMultipleSecurityTokens>
          </Body>
        </Envelope>
        """
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

        let soapXml = Self.buildPPCRLEnvelope(email: email, password: password, policy: policy)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("http://schemas.xmlsoap.org/ws/2004/04/security/trust/RST/Issue", forHTTPHeaderField: "SOAPAction")
        req.setValue("MSNMSGR/14.0.8117.0416", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(soapXml.utf8)

        logMessage("Connecting to Passport RST2 at \(endpoint.absoluteString)...")
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            logMessage("? Passport network error: Invalid HTTP response")
            throw PassportError.networkError("Invalid HTTP response")
        }

        logMessage("Passport server responded with HTTP \(httpResponse.statusCode)")
        let responseXml = String(data: data, encoding: .utf8) ?? ""
        if httpResponse.statusCode != 200 || responseXml.contains("<faultstring>") || responseXml.contains("<Fault>") {
            self.lastFaultString = extractTagIgnoringNamespace(responseXml, localName: "faultstring")
                ?? extractTagIgnoringNamespace(responseXml, localName: "detail")
                ?? "Authentication failed"
            logMessage("? Passport fault: \(self.lastFaultString ?? "Unknown error")")
            throw PassportError.authenticationFailed
        }

        guard responseXml.contains("<Envelope") && responseXml.contains("</Envelope>") else {
            logMessage("? Passport malformed XML envelope")
            throw PassportError.malformedXmlResponse
        }

        let tokens = try parseSecurityTokens(from: responseXml)
        logMessage("? Passport security tokens retrieved successfully")
        return tokens
    }

    private func extractTagIgnoringNamespace(_ xml: String, localName: String) -> String? {
        let pattern = "<(?:\\w+:)?\(localName)[^>]*>(.*?)</(?:\\w+:)?\(localName)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return nil
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseSecurityTokens(from xml: String) throws -> RST2SecurityTokens {
        var clearToken = ""
        var msgToken = ""
        var contactsToken = ""
        var storageToken = ""
        var secretBase64 = ""

        let pattern = "<(?:\\w+:)?RequestSecurityTokenResponse[^>]*>(.*?)</(?:\\w+:)?RequestSecurityTokenResponse>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            throw PassportError.malformedXmlResponse
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)

        for match in matches {
            guard let blockRange = Range(match.range(at: 1), in: xml) else { continue }
            let block = String(xml[blockRange])

            let address = extractTagIgnoringNamespace(block, localName: "Address") ?? ""
            let token = extractTagIgnoringNamespace(block, localName: "BinarySecurityToken") ?? ""
            let secret = extractTagIgnoringNamespace(block, localName: "BinarySecret") ?? ""

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

        guard !secretBase64.isEmpty, let secretData = Data(base64Encoded: secretBase64) else {
            throw PassportError.missingBinarySecret
        }

        return RST2SecurityTokens(
            messengerClearToken: clearToken,
            messengerToken: msgToken.isEmpty ? clearToken : msgToken,
            contactsToken: contactsToken.isEmpty ? clearToken : contactsToken,
            storageToken: storageToken.isEmpty ? clearToken : storageToken,
            binarySecret: secretData,
            binarySecretBase64: secretBase64
        )
    }
}
