//
// MockProtocolFixtures.swift
// MsngrIntegrationTests
//
// Authoritative mock SOAP responses and MSNP18 wire byte sequences extracted from
// reference Windows Live Messenger 2009 (MSNP18) specifications and Escargot wire captures.
//

import Foundation

// MARK: - Passport RST2 SOAP Fixtures (/RST.srf)

public enum MockPassportFixtures {
    /// Verbatim SOAP response for POST /RST.srf containing valid RequestSecurityTokenResponse blocks
    /// for messengerclear.live.com, contacts.msn.com, storage.live.com, and messenger.msn.com.
    public static let rst2SuccessResponse = """
    <?xml version="1.0" encoding="utf-8"?>
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"
      xmlns:wsse="http://schemas.xmlsoap.org/ws/2003/06/secext"
      xmlns:wsp="http://schemas.xmlsoap.org/ws/2002/12/policy"
      xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing"
      xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust">
      <Header/>
      <Body>
        <wst:RequestSecurityTokenResponseCollection xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust">
          <wst:RequestSecurityTokenResponse>
            <wsa:EndpointReference>
              <wsa:Address>messengerclear.live.com</wsa:Address>
            </wsa:EndpointReference>
            <wsa:Address>messengerclear.live.com</wsa:Address>
            <wsse:BinarySecurityToken Id="Compact1">mock-messenger-ticket-compact-security-token-value</wsse:BinarySecurityToken>
            <wst:BinarySecret>c2VjcmV0LWtleS0xMjM0NTY3ODkwMTIzNDU2</wst:BinarySecret>
          </wst:RequestSecurityTokenResponse>
          <wst:RequestSecurityTokenResponse>
            <wsa:EndpointReference>
              <wsa:Address>contacts.msn.com</wsa:Address>
            </wsa:EndpointReference>
            <wsa:Address>contacts.msn.com</wsa:Address>
            <wsse:BinarySecurityToken Id="Compact2">t=mock-address-book-ticket-contacts-token&amp;p=mock-contacts-proof</wsse:BinarySecurityToken>
          </wst:RequestSecurityTokenResponse>
          <wst:RequestSecurityTokenResponse>
            <wsa:EndpointReference>
              <wsa:Address>storage.live.com</wsa:Address>
            </wsa:EndpointReference>
            <wsa:Address>storage.live.com</wsa:Address>
            <wsse:BinarySecurityToken Id="Compact3">t=mock-storage-ticket-profile-images&amp;p=mock-storage-proof</wsse:BinarySecurityToken>
          </wst:RequestSecurityTokenResponse>
          <wst:RequestSecurityTokenResponse>
            <wsa:EndpointReference>
              <wsa:Address>messenger.msn.com</wsa:Address>
            </wsa:EndpointReference>
            <wsa:Address>messenger.msn.com</wsa:Address>
            <wsse:BinarySecurityToken Id="Compact4">t=mock-offline-ticket-oim-token&amp;p=mock-offline-proof</wsse:BinarySecurityToken>
          </wst:RequestSecurityTokenResponse>
          <wst:RequestSecurityTokenResponse>
            <wsa:EndpointReference>
              <wsa:Address>messengersecure.live.com</wsa:Address>
            </wsa:EndpointReference>
            <wsa:Address>messengersecure.live.com</wsa:Address>
            <wsse:BinarySecurityToken Id="Compact5">t=mock-secure-ticket&amp;p=mock</wsse:BinarySecurityToken>
          </wst:RequestSecurityTokenResponse>
          <wst:RequestSecurityTokenResponse>
            <wsa:EndpointReference>
              <wsa:Address>sup.live.com</wsa:Address>
            </wsa:EndpointReference>
            <wsa:Address>sup.live.com</wsa:Address>
            <wsse:BinarySecurityToken Id="Compact6">t=mock-sup-ticket&amp;p=mock</wsse:BinarySecurityToken>
          </wst:RequestSecurityTokenResponse>
        </wst:RequestSecurityTokenResponseCollection>
      </Body>
    </Envelope>
    """

    /// Verbatim SOAP Fault response for invalid credentials (HTTP 401/500).
    public static let rst2InvalidCredentialsFault = """
    <?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <soap:Fault>
          <faultcode>soap:Client</faultcode>
          <faultstring>The authentication service rejected these credentials.</faultstring>
          <detail>
            <psf:error xmlns:psf="http://schemas.microsoft.com/Passport/SoapServices/SOAPFault">
              <psf:value>0x80048821</psf:value>
              <psf:internalerror>
                <psf:code>0x80041012</psf:code>
                <psf:text>The specified member name is either invalid or does not exist.</psf:text>
              </psf:internalerror>
            </psf:error>
          </detail>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
    """
}

// MARK: - ABCH Address Book SOAP Fixtures (ABFindContactsPaged & FindMembership)

public enum MockABCHFixtures {
    /// Verbatim ABFindContactsPagedResponse SOAP envelope containing contacts, groups, owner "Me" record,
    /// deleted contacts, and circle ticket with signed XML formatting preserved.
    public static let abFindContactsPagedResponse = """
    <?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xmlns:xsd="http://www.w3.org/2001/XMLSchema"
      xmlns:ns1="http://www.msn.com/webservices/AddressBook">
      <soap:Header>
        <ns1:ServiceHeader>
          <ns1:Version>15.01.1408.0000</ns1:Version>
          <ns1:CacheKey>15.01.1408.0000:contacts.msn.com:cache_token</ns1:CacheKey>
          <ns1:CacheKeyChanged>true</ns1:CacheKeyChanged>
          <ns1:PreferredHostName>contacts.msn.com</ns1:PreferredHostName>
          <ns1:SessionId>11111111-2222-4333-8444-abc000000010</ns1:SessionId>
        </ns1:ServiceHeader>
      </soap:Header>
      <soap:Body>
        <ns1:ABFindContactsPagedResponse>
          <ns1:ABFindContactsPagedResult>
            <ns1:Groups>
              <ns1:Group>
                <ns1:groupId>00000000-0000-0000-0001-000000000001</ns1:groupId>
                <ns1:groupInfo>
                  <ns1:name>Coworkers</ns1:name>
                  <ns1:fDeleted>false</ns1:fDeleted>
                </ns1:groupInfo>
              </ns1:Group>
              <ns1:Group>
                <ns1:groupId>00000000-0000-0000-0001-000000000002</ns1:groupId>
                <ns1:groupInfo>
                  <ns1:name>Friends</ns1:name>
                  <ns1:fDeleted>false</ns1:fDeleted>
                </ns1:groupInfo>
              </ns1:Group>
            </ns1:Groups>
            <ns1:Contacts>
              <!-- Contact 1: Selin with NickName annotation and Coworkers group -->
              <ns1:Contact>
                <ns1:contactId>11111111-2222-3333-4444-555555555555</ns1:contactId>
                <ns1:contactInfo>
                  <ns1:annotations>
                    <ns1:Annotation>
                      <ns1:Name>AB.NickName</ns1:Name>
                      <ns1:Value>Selin</ns1:Value>
                    </ns1:Annotation>
                  </ns1:annotations>
                  <ns1:contactType>Regular</ns1:contactType>
                  <ns1:passportName>selin@msngr.dev</ns1:passportName>
                  <ns1:displayName>Selin (Engineering)</ns1:displayName>
                  <ns1:isMessengerUser>true</ns1:isMessengerUser>
                  <ns1:groupFilter>
                    <ns1:groupId>00000000-0000-0000-0001-000000000001</ns1:groupId>
                  </ns1:groupFilter>
                </ns1:contactInfo>
                <ns1:fDeleted>false</ns1:fDeleted>
              </ns1:Contact>
              <!-- Contact 2: Mert with direct displayName and Friends group -->
              <ns1:Contact>
                <ns1:contactId>22222222-3333-4444-5555-666666666666</ns1:contactId>
                <ns1:contactInfo>
                  <ns1:contactType>Regular</ns1:contactType>
                  <ns1:passportName>mert@msngr.dev</ns1:passportName>
                  <ns1:displayName>Mert</ns1:displayName>
                  <ns1:isMessengerUser>true</ns1:isMessengerUser>
                  <ns1:groupFilter>
                    <ns1:groupId>00000000-0000-0000-0001-000000000002</ns1:groupId>
                  </ns1:groupFilter>
                </ns1:contactInfo>
                <ns1:fDeleted>false</ns1:fDeleted>
              </ns1:Contact>
              <!-- Contact 3: Derya -->
              <ns1:Contact>
                <ns1:contactId>33333333-4444-5555-6666-777777777777</ns1:contactId>
                <ns1:contactInfo>
                  <ns1:contactType>Regular</ns1:contactType>
                  <ns1:passportName>derya@msngr.dev</ns1:passportName>
                  <ns1:displayName>Derya</ns1:displayName>
                  <ns1:isMessengerUser>true</ns1:isMessengerUser>
                </ns1:contactInfo>
                <ns1:fDeleted>false</ns1:fDeleted>
              </ns1:Contact>
              <!-- Owner Profile ('Me' Contact) -->
              <ns1:Contact>
                <ns1:contactInfo>
                  <ns1:contactType>Me</ns1:contactType>
                  <ns1:passportName>mock-user@example.com</ns1:passportName>
                  <ns1:displayName>Mock Profile</ns1:displayName>
                </ns1:contactInfo>
                <ns1:fDeleted>false</ns1:fDeleted>
              </ns1:Contact>
              <!-- Deleted Contact (Ignored by Parser) -->
              <ns1:Contact>
                <ns1:contactInfo>
                  <ns1:contactType>Regular</ns1:contactType>
                  <ns1:passportName>deleted@example.com</ns1:passportName>
                  <ns1:displayName>Deleted User</ns1:displayName>
                </ns1:contactInfo>
                <ns1:fDeleted>true</ns1:fDeleted>
              </ns1:Contact>
              <!-- Non-Messenger Email-Only Contact (Ignored by Parser) -->
              <ns1:Contact>
                <ns1:contactInfo>
                  <ns1:contactType>Regular</ns1:contactType>
                  <ns1:passportName>mail-only@example.com</ns1:passportName>
                  <ns1:isMessengerUser>false</ns1:isMessengerUser>
                </ns1:contactInfo>
                <ns1:fDeleted>false</ns1:fDeleted>
              </ns1:Contact>
            </ns1:Contacts>
            <ns1:CircleResult>
              <ns1:Circles>
                <ns1:CircleInverseInfo>
                  <ns1:Content>
                    <ns1:Handle>
                      <ns1:Id>00000000-0000-0000-0009-123456789abc</ns1:Id>
                    </ns1:Handle>
                    <ns1:Info>
                      <ns1:HostedDomain>live.com</ns1:HostedDomain>
                      <ns1:DisplayName>Development Circle</ns1:DisplayName>
                    </ns1:Info>
                  </ns1:Content>
                  <ns1:PersonalInfo>
                    <ns1:CirclePersonalMembership>
                      <ns1:State>Accepted</ns1:State>
                    </ns1:CirclePersonalMembership>
                  </ns1:PersonalInfo>
                  <ns1:Deleted>false</ns1:Deleted>
                </ns1:CircleInverseInfo>
              </ns1:Circles>
              <ns1:CircleTicket>&lt;SignedTicket&gt;
  &lt;CircleId&gt;00000000-0000-0000-0009-123456789abc&lt;/CircleId&gt;
  &lt;Signature&gt;MOCK_VALID_SIGNATURE&lt;/Signature&gt;
&lt;/SignedTicket&gt;</ns1:CircleTicket>
            </ns1:CircleResult>
          </ns1:ABFindContactsPagedResult>
        </ns1:ABFindContactsPagedResponse>
      </soap:Body>
    </soap:Envelope>
    """

    /// Empty address book for boundary testing.
    public static let abFindContactsEmptyResponse = """
    <?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
      xmlns:ns1="http://www.msn.com/webservices/AddressBook">
      <soap:Body>
        <ns1:ABFindContactsPagedResponse>
          <ns1:ABFindContactsPagedResult>
            <ns1:Contacts/>
            <ns1:Groups/>
          </ns1:ABFindContactsPagedResult>
        </ns1:ABFindContactsPagedResponse>
      </soap:Body>
    </soap:Envelope>
    """

    /// Verbatim FindMembershipResponse containing Allow list, Blocked list, Reverse list, and Pending invitations.
    public static let findMembershipResponse = """
    <?xml version="1.0" encoding="utf-8"?>
    <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/"
      xmlns:ns0="http://www.msn.com/webservices/AddressBook"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <Body>
        <ns0:FindMembershipResponse>
          <ns0:FindMembershipResult>
            <ns0:Services>
              <ns0:Service>
                <ns0:Info>
                  <ns0:Handle>
                    <ns0:Id>1</ns0:Id>
                    <ns0:Type>Messenger</ns0:Type>
                  </ns0:Handle>
                </ns0:Info>
                <ns0:Memberships>
                  <!-- Allow list -->
                  <ns0:Membership>
                    <ns0:MemberRole>Allow</ns0:MemberRole>
                    <ns0:Members>
                      <ns0:Member xsi:type="PassportMember">
                        <ns0:Type>Passport</ns0:Type>
                        <ns0:PassportName>selin@msngr.dev</ns0:PassportName>
                        <ns0:State>Accepted</ns0:State>
                        <ns0:Deleted>false</ns0:Deleted>
                      </ns0:Member>
                      <ns0:Member xsi:type="PassportMember">
                        <ns0:Type>Passport</ns0:Type>
                        <ns0:PassportName>mert@msngr.dev</ns0:PassportName>
                        <ns0:State>Accepted</ns0:State>
                        <ns0:Deleted>false</ns0:Deleted>
                      </ns0:Member>
                    </ns0:Members>
                    <ns0:MembershipIsComplete>true</ns0:MembershipIsComplete>
                  </ns0:Membership>
                  <!-- Block list -->
                  <ns0:Membership>
                    <ns0:MemberRole>Block</ns0:MemberRole>
                    <ns0:Members>
                      <ns0:Member xsi:type="PassportMember">
                        <ns0:Type>Passport</ns0:Type>
                        <ns0:PassportName>blocked@msngr.dev</ns0:PassportName>
                        <ns0:DisplayName>Blocked Friend</ns0:DisplayName>
                        <ns0:State>Accepted</ns0:State>
                        <ns0:Deleted>false</ns0:Deleted>
                      </ns0:Member>
                      <!-- Deleted block member (Ignored) -->
                      <ns0:Member xsi:type="PassportMember">
                        <ns0:Type>Passport</ns0:Type>
                        <ns0:PassportName>old-blocked@msngr.dev</ns0:PassportName>
                        <ns0:Deleted>true</ns0:Deleted>
                      </ns0:Member>
                    </ns0:Members>
                    <ns0:MembershipIsComplete>true</ns0:MembershipIsComplete>
                  </ns0:Membership>
                  <!-- Reverse list -->
                  <ns0:Membership>
                    <ns0:MemberRole>Reverse</ns0:MemberRole>
                    <ns0:Members>
                      <ns0:Member xsi:type="PassportMember">
                        <ns0:Type>Passport</ns0:Type>
                        <ns0:PassportName>reverse@msngr.dev</ns0:PassportName>
                        <ns0:State>Accepted</ns0:State>
                        <ns0:Deleted>false</ns0:Deleted>
                      </ns0:Member>
                    </ns0:Members>
                    <ns0:MembershipIsComplete>true</ns0:MembershipIsComplete>
                  </ns0:Membership>
                  <!-- Pending invitations -->
                  <ns0:Membership>
                    <ns0:MemberRole>Pending</ns0:MemberRole>
                    <ns0:Members>
                      <ns0:Member xsi:type="PassportMember">
                        <ns0:MembershipId>Pending/11111111-2222-4333-8444-abc000000016</ns0:MembershipId>
                        <ns0:Type>Passport</ns0:Type>
                        <ns0:State>Accepted</ns0:State>
                        <ns0:Deleted>false</ns0:Deleted>
                        <ns0:PassportName>pending-friend@msngr.dev</ns0:PassportName>
                        <ns0:DisplayName>Pending Friend</ns0:DisplayName>
                      </ns0:Member>
                    </ns0:Members>
                    <ns0:MembershipIsComplete>true</ns0:MembershipIsComplete>
                  </ns0:Membership>
                </ns0:Memberships>
              </ns0:Service>
            </ns0:Services>
          </ns0:FindMembershipResult>
        </ns0:FindMembershipResponse>
      </Body>
    </Envelope>
    """
}

// MARK: - Notification Server (NS) Wire Sequence Fixtures

public enum MockNotificationWireFixtures {
    // 1. Negotiation
    public static let clientVer = "VER 1 MSNP18 CVR0\r\n"
    public static let serverVer = "VER 1 MSNP18 CVR0\r\n"

    // 2. Client Version Registration
    public static let clientCvr = "CVR 2 0x0409 winnt 6.1 i386 MSNMSGR 14.0.8117.0416 msmsgs mock-user@example.com\r\n"
    public static let serverCvr = "CVR 2 14.0.8117.0416 14.0.8117.0416 14.0.8117.0416 http://msgr.dlservice.microsoft.com http://messenger.live.com\r\n"

    // 3. SSO Authentication Challenge
    public static let clientUsrInitiate = "USR 3 SSO I mock-user@example.com\r\n"
    public static let serverUsrChallenge = "USR 3 SSO S MBI_KEY_OLD 0123456789abcdef\r\n"

    // 4. SSO Authentication Response & Confirmation
    public static func clientUsrResponse(trId: Int = 4, ticket: String, proof: String, machineGuid: String = "00000000-0000-0000-0000-000000000000") -> String {
        return "USR \(trId) SSO S \(ticket) \(proof) {\(machineGuid)}\r\n"
    }
    public static let serverUsrConfirmation = "USR 4 OK mock-user@example.com 1 0\r\n"

    // 5. Initial Contact Sync via ADL
    // Note: l="1" indicates initial full sync; forward + allow list bitmask is l="3" (1 | 2).
    public static let adlPayload = "<ml l=\"1\"><d n=\"msngr.dev\"><c n=\"selin\" l=\"3\" t=\"1\" /><c n=\"mert\" l=\"3\" t=\"1\" /></d></ml>"
    public static var clientAdl: String {
        let count = adlPayload.utf8.count
        return "ADL 5 \(count)\r\n\(adlPayload)"
    }
    public static let serverAdlOk = "ADL 5 OK\r\n"

    // 6. Presence Broadcast & Personal Message
    public static let clientChgOnline = "CHG 6 NLN 2789003312:2609259408 0\r\n"
    public static let serverChgOnline = "CHG 6 NLN 2789003312:2609259408 0\r\n"

    public static let uuxPayload = "<Data><PSM>Testing WLM iOS Client</PSM><CurrentMedia></CurrentMedia><MachineGuid>{00000000-0000-0000-0000-000000000000}</MachineGuid><DDP></DDP></Data>"
    public static var clientUux: String {
        let count = uuxPayload.utf8.count
        return "UUX 7 \(count)\r\n\(uuxPayload)"
    }
    public static let serverUuxOk = "UUX 7 0\r\n"

    // 7. Inbound Presence Broadcasts from Server
    public static let serverIlnInitialPresence = "ILN 0 NLN 1:selin@msngr.dev 1 Selin 2789003312:2609259408 0\r\n"
    public static let serverNlnOnlinePresence = "NLN NLN 1:mert@msngr.dev Mert 2789003312:2609259408 0\r\n"
    public static let serverFlnOfflinePresence = "FLN 1:mert@msngr.dev\r\n"

    public static let ubxPayload = "<Data><PSM>Coffee first</PSM><CurrentMedia></CurrentMedia></Data>"
    public static var serverUbxPsm: String {
        let count = ubxPayload.utf8.count
        return "UBX 1:selin@msngr.dev \(count)\r\n\(ubxPayload)"
    }

    // 8. Switchboard Dispatch Request & Response
    public static let clientXfrSb = "XFR 8 SB\r\n"
    public static func serverXfrSb(trId: Int = 8, ip: String = "127.0.0.1", port: Int = 1864, authKey: String = "mock-outgoing-key") -> String {
        return "XFR \(trId) SB \(ip):\(port) CKI \(authKey)\r\n"
    }

    // 9. Inbound Switchboard Invitation (RNG)
    // Non-transactional verb: parameters are [sessionId, ip:port, CKI, key, inviterEmail, displayName]
    public static func serverRngInvitation(sessionId: String = "4242", ip: String = "127.0.0.1", port: Int = 1864, key: String = "mock-incoming-key", inviter: String = "selin@msngr.dev", name: String = "Selin") -> String {
        return "RNG \(sessionId) \(ip):\(port) CKI \(key) \(inviter) \(name)\r\n"
    }

    // 10. Ping & Pong Keep-Alive
    public static let clientPng = "PNG\r\n"
    public static let serverQng = "QNG 45\r\n"

    // 11. Clean Logout
    public static let clientOut = "OUT\r\n"
    public static let serverOutRemoteSignOut = "OUT OTH\r\n"
}

// MARK: - Switchboard (SB) Handshake & Chat Sequence Fixtures

public enum MockSwitchboardWireFixtures {
    // MARK: - Outgoing Call Flow
    // 1. Switchboard Authentication
    public static func clientUsrAuth(trId: Int = 1, email: String = "mock-user@example.com", guid: String = "00000000-0000-0000-0000-000000000000", key: String = "mock-outgoing-key") -> String {
        return "USR \(trId) \(email);{\(guid)} \(key)\r\n"
    }
    public static func serverUsrOk(trId: Int = 1, email: String = "mock-user@example.com", name: String = "Mock Profile") -> String {
        let escapedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "USR \(trId) OK \(email) \(escapedName)\r\n"
    }

    // 2. Self Invite (MSNP18 calls own account so multi-endpoints join)
    public static let clientCalSelf = "CAL 2 mock-user@example.com\r\n"
    public static let serverCalSelfRinging = "CAL 2 RINGING 4242\r\n"

    // 3. Peer Invite
    public static func clientCalPeer(trId: Int = 3, peerEmail: String = "selin@msngr.dev") -> String {
        return "CAL \(trId) \(peerEmail)\r\n"
    }
    public static func serverCalPeerRinging(trId: Int = 3, sessionId: String = "4242") -> String {
        return "CAL \(trId) RINGING \(sessionId)\r\n"
    }

    // 4. Peer Joins Session
    public static func serverJoiPeer(peerEmail: String = "selin@msngr.dev", endpointGuid: String = "11111111-2222-3333-4444-555555555555", name: String = "Selin", capabilities: String = "2789003312:2609259408") -> String {
        return "JOI \(peerEmail);{\(endpointGuid)} \(name) \(capabilities)\r\n"
    }

    // MARK: - Incoming Call Flow
    // 1. Answer Handshake
    public static func clientAns(trId: Int = 1, email: String = "mock-user@example.com", guid: String = "00000000-0000-0000-0000-000000000000", key: String = "mock-incoming-key", sessionId: String = "4242") -> String {
        return "ANS \(trId) \(email);{\(guid)} \(key) \(sessionId)\r\n"
    }
    // 2. Initial Roster in Session
    public static func serverIro(trId: Int = 1, peerEmail: String = "selin@msngr.dev", endpointGuid: String = "11111111-2222-3333-4444-555555555555", name: String = "Selin", capabilities: String = "2789003312:2609259408") -> String {
        return "IRO \(trId) 1 1 \(peerEmail);{\(endpointGuid)} \(name) \(capabilities)\r\n"
    }
    public static func serverAnsOk(trId: Int = 1) -> String {
        return "ANS \(trId) OK\r\n"
    }

    // MARK: - Messaging & Payloads
    // 1. Text Message (MIME text/plain with X-MMS-IM-Format)
    public static func makeTextMimePayload(body: String, fontFace: String = "Segoe UI", bold: Bool = false, italic: Bool = false, bgrHex: String = "0") -> String {
        var effects = ""
        if bold { effects += "B" }
        if italic { effects += "I" }
        let formatHeader = "FN=\(fontFace.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fontFace); EF=\(effects); CO=\(bgrHex); CS=0; PF=22"
        return "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nX-MMS-IM-Format: \(formatHeader)\r\n\r\n\(body)"
    }

    public static func clientMsgText(trId: Int = 4, body: String, ackMode: String = "A") -> (header: String, payload: String, frame: String) {
        let mime = makeTextMimePayload(body: body)
        let count = mime.utf8.count
        let header = "MSG \(trId) \(ackMode) \(count)\r\n"
        return (header, mime, header + mime)
    }

    public static func serverAck(trId: Int = 4) -> String {
        return "ACK \(trId)\r\n"
    }

    public static func serverMsgText(peerEmail: String = "selin@msngr.dev", endpointGuid: String = "11111111-2222-3333-4444-555555555555", name: String = "Selin", body: String) -> String {
        let mime = makeTextMimePayload(body: body, bold: true, bgrHex: "ff0000") // Red text
        let count = mime.utf8.count
        let header = "MSG \(peerEmail);{\(endpointGuid)} \(name) \(count)\r\n"
        return header + mime
    }

    // 2. Typing Indicator (MIME text/x-msmsgscontrol, ackMode = U)
    public static func makeTypingMimePayload(email: String) -> String {
        return "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\nTypingUser: \(email)\r\n\r\n\r\n"
    }

    public static func clientMsgTyping(trId: Int = 5, email: String = "mock-user@example.com") -> (header: String, payload: String, frame: String) {
        let mime = makeTypingMimePayload(email: email)
        let count = mime.utf8.count
        let header = "MSG \(trId) U \(count)\r\n"
        return (header, mime, header + mime)
    }

    public static func serverMsgTyping(peerEmail: String = "selin@msngr.dev", endpointGuid: String = "11111111-2222-3333-4444-555555555555", name: String = "Selin") -> String {
        let mime = makeTypingMimePayload(email: peerEmail)
        let count = mime.utf8.count
        let header = "MSG \(peerEmail);{\(endpointGuid)} \(name) \(count)\r\n"
        return header + mime
    }

    // 3. Nudge Packet (MIME text/x-msnmsgr-datacast, ackMode = N)
    public static let nudgeMimePayload = "MIME-Version: 1.0\r\nContent-Type: text/x-msnmsgr-datacast\r\n\r\nID: 1\r\n"

    public static func clientMsgNudge(trId: Int = 6) -> (header: String, payload: String, frame: String) {
        let count = nudgeMimePayload.utf8.count
        let header = "MSG \(trId) N \(count)\r\n"
        return (header, nudgeMimePayload, header + nudgeMimePayload)
    }

    public static func serverMsgNudge(peerEmail: String = "selin@msngr.dev", endpointGuid: String = "11111111-2222-3333-4444-555555555555", name: String = "Selin") -> String {
        let count = nudgeMimePayload.utf8.count
        let header = "MSG \(peerEmail);{\(endpointGuid)} \(name) \(count)\r\n"
        return header + nudgeMimePayload
    }

    // 4. Session Departure (BYE)
    public static func serverBye(peerEmail: String = "selin@msngr.dev", endpointGuid: String = "11111111-2222-3333-4444-555555555555") -> String {
        return "BYE \(peerEmail);{\(endpointGuid)}\r\n"
    }
}
