import Foundation

/// Utility for constructing and parsing SOAP XML envelopes for Passport RST2 and ABCH services.
public enum SOAPXmlBuilder {
    /// Escapes XML special characters (`&`, `<`, `>`, `"`, `'`).
    public static func escapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Unescapes XML entities including numeric entities (`&#x3D;`, `&#61;`).
    public static func unescapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#x3D;", with: "=", options: .caseInsensitive)
            .replacingOccurrences(of: "&#61;", with: "=")
    }

    /// Extracts the inner text of the first matching XML tag.
    public static func extractTag(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
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

    /// Builds a Windows Live ID Passport RST2 SOAP request envelope.
    public static func buildRST2Envelope(email: String, password: String, policy: String = "MBI_KEY_OLD") -> String {
        let truncatedPassword = String(password.prefix(16))
        let escapedEmail = escapeXml(email)
        let escapedPassword = escapeXml(truncatedPassword)
        let escapedPolicy = escapeXml(policy)

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"
          xmlns:wsse="http://schemas.xmlsoap.org/ws/2003/06/secext"
          xmlns:wsp="http://schemas.xmlsoap.org/ws/2002/12/policy"
          xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust">
          <Header>
            <wsse:Security>
              <wsse:UsernameToken Id="user">
                <wsse:Username>\(escapedEmail)</wsse:Username>
                <wsse:Password>\(escapedPassword)</wsse:Password>
              </wsse:UsernameToken>
            </wsse:Security>
          </Header>
          <Body>
            <wst:RequestMultipleSecurityTokens Id="RST0">
              <wst:RequestSecurityToken Id="RST1">
                <wsp:AppliesTo>
                  <wsa:EndpointReference xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing">
                    <wsa:Address>messengerclear.live.com</wsa:Address>
                  </wsa:EndpointReference>
                </wsp:AppliesTo>
                <wsse:PolicyReference URI="\(escapedPolicy)" />
              </wst:RequestSecurityToken>
              <wst:RequestSecurityToken Id="RST2">
                <wsp:AppliesTo>
                  <wsa:EndpointReference xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing">
                    <wsa:Address>messenger.msn.com</wsa:Address>
                  </wsa:EndpointReference>
                </wsp:AppliesTo>
                <wsse:PolicyReference URI="?id=507" />
              </wst:RequestSecurityToken>
              <wst:RequestSecurityToken Id="RST3">
                <wsp:AppliesTo>
                  <wsa:EndpointReference xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing">
                    <wsa:Address>contacts.msn.com</wsa:Address>
                  </wsa:EndpointReference>
                </wsp:AppliesTo>
                <wsse:PolicyReference URI="MBI" />
              </wst:RequestSecurityToken>
              <wst:RequestSecurityToken Id="RST4">
                <wsp:AppliesTo>
                  <wsa:EndpointReference xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing">
                    <wsa:Address>storage.live.com</wsa:Address>
                  </wsa:EndpointReference>
                </wsp:AppliesTo>
                <wsse:PolicyReference URI="MBI" />
              </wst:RequestSecurityToken>
            </wst:RequestMultipleSecurityTokens>
          </Body>
        </Envelope>
        """
    }

    /// Builds an ABCH `ABFindContactsPaged` SOAP request envelope.
    public static func buildABFindContactsPaged(ticket: String) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Header>
            <ABAuthHeader xmlns="http://www.msn.com/webservices/AddressBook">
              <TicketToken>\(escapeXml(ticket))</TicketToken>
            </ABAuthHeader>
          </soap:Header>
          <soap:Body>
            <ABFindContactsPaged xmlns="http://www.msn.com/webservices/AddressBook" />
          </soap:Body>
        </soap:Envelope>
        """
    }

    /// Builds an ABCH `FindMembership` SOAP request envelope.
    public static func buildFindMembership(ticket: String, role: String) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Header>
            <ABAuthHeader xmlns="http://www.msn.com/webservices/AddressBook">
              <TicketToken>\(escapeXml(ticket))</TicketToken>
            </ABAuthHeader>
          </soap:Header>
          <soap:Body>
            <FindMembership xmlns="http://www.msn.com/webservices/AddressBook">
              <Role>\(escapeXml(role))</Role>
            </FindMembership>
          </soap:Body>
        </soap:Envelope>
        """
    }

    /// Builds an ABCH `ABContactAdd` SOAP request envelope.
    public static func buildABContactAdd(email: String, displayName: String) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ABContactAdd xmlns="http://www.msn.com/webservices/AddressBook">
              <contacts>
                <Contact>
                  <contactInfo>
                    <passportName>\(escapeXml(email))</passportName>
                    <DisplayName>\(escapeXml(displayName))</DisplayName>
                  </contactInfo>
                </Contact>
              </contacts>
            </ABContactAdd>
          </soap:Body>
        </soap:Envelope>
        """
    }

    /// Builds an ABCH `ABContactUpdate` SOAP request envelope.
    public static func buildABContactUpdate(contactGuid: String, isMessengerUser: Bool) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <ABContactUpdate xmlns="http://www.msn.com/webservices/AddressBook">
              <contacts>
                <Contact>
                  <contactId>\(escapeXml(contactGuid))</contactId>
                  <contactInfo>
                    <isMessengerUser>\(isMessengerUser ? "true" : "false")</isMessengerUser>
                  </contactInfo>
                </Contact>
              </contacts>
            </ABContactUpdate>
          </soap:Body>
        </soap:Envelope>
        """
    }
}
