import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class AuthHandshakeE2ETests: XCTestCase {
    var passportServer: MockPassportServer!
    var nsServer: MockNotificationServer!
    var rpsGenerator: RPSProofGenerator!
    var passportClient: PassportRST2Client!
    var nsClient: NotificationServerClient!
    var allocatedNsPort: UInt16 = 0

    override func setUp() async throws {
        try await super.setUp()
        MockSOAPURLProtocol.register()
        passportServer = MockPassportServer()
        MockSOAPRouter.shared.passportServer = passportServer

        nsServer = MockNotificationServer()
        allocatedNsPort = try await nsServer.start()

        rpsGenerator = RPSProofGenerator()
        passportClient = PassportRST2Client(endpoint: URL(string: "https://login.live.com/RST.srf")!)
        nsClient = NotificationServerClient(host: "127.0.0.1", port: allocatedNsPort)
    }

    override func tearDown() async throws {
        await nsClient?.disconnect()
        await nsServer?.stop()
        MockSOAPRouter.shared.reset()
        MockSOAPURLProtocol.unregister()
        try await super.tearDown()
    }

    // MARK: - Feature Area 1: RST2 / Passport SOAP Auth (Tier 1)

    func test_tier1_passport_standardCredentialsIssueToken() async throws {
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")
        let tokens = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123", policy: "MBI_KEY_OLD")

        XCTAssertFalse(tokens.messengerClearToken.isEmpty, "Messenger clear token must not be empty")
        XCTAssertGreaterThanOrEqual(passportServer.recordedRequests.count, 1, "MockPassportServer must record at least 1 request")
    }

    func test_tier1_passport_extractAllSecurityTokens() async throws {
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")
        let tokens = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123", policy: "MBI_KEY_OLD")

        XCTAssertFalse(tokens.messengerClearToken.isEmpty, "Clear token must be present")
        XCTAssertFalse(tokens.messengerToken.isEmpty, "Messenger token must be present")
        XCTAssertFalse(tokens.contactsToken.isEmpty, "Contacts token must be present")
        XCTAssertFalse(tokens.storageToken.isEmpty, "Storage token must be present")
    }

    func test_tier1_passport_binarySecretDecoding() async throws {
        let knownSecretBase64 = "AQIDBAUGBwgJCgsMDQ4PEBESExQ=" // 20 bytes: 1...20
        passportServer.binarySecretBase64 = knownSecretBase64
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")

        let tokens = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123", policy: "MBI_KEY_OLD")
        let expectedBytes = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
        XCTAssertEqual(tokens.binarySecret, expectedBytes, "Binary secret must decode to exact byte sequence")
    }

    func test_tier1_passport_customPolicyReference() async throws {
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")
        _ = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123", policy: "MBI_SSL")

        guard let firstReq = passportServer.recordedRequests.first else {
            XCTFail("No recorded request found")
            return
        }
        XCTAssertTrue(firstReq.rawBody.contains("MBI_SSL"), "SOAP request body must include requested policy URI")
    }

    func test_tier1_passport_rpsProofGeneration() async throws {
        let knownSecretBase64 = "AQIDBAUGBwgJCgsMDQ4PEBESExQ="
        let nonce = "1234567890ABCDEF"

        let proof = try rpsGenerator.generateProof(binarySecretBase64: knownSecretBase64, nonce: nonce)
        guard let proofData = Data(base64Encoded: proof) else {
            XCTFail("Generated proof must be valid base64")
            return
        }

        XCTAssertGreaterThanOrEqual(proofData.count, 64, "RPS proof binary packet must be at least 64 bytes")

        // Validate 28-byte little-endian header
        let headerSize = proofData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let structVer = proofData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        let cipherAlg = proofData.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
        let hashAlg = proofData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }

        XCTAssertEqual(headerSize, 28, "Header size field must be 28")
        XCTAssertEqual(structVer, 1, "Struct version field must be 1")
        XCTAssertEqual(cipherAlg, 0x6603, "Cipher algorithm must be 3DES (0x6603)")
        XCTAssertEqual(hashAlg, 0x8004, "Hash algorithm must be SHA1 (0x8004)")
    }

    // MARK: - Feature Area 1: RST2 / Passport SOAP Auth (Tier 2)

    func test_tier2_passport_passwordTruncationExceeding16Chars() async throws {
        let longPassword = "0123456789ABCDEFEXTRA_CHARS"
        passportServer.registerUser(email: "user@msngr.dev", password: "0123456789ABCDEF")

        _ = try await passportClient.authenticate(email: "user@msngr.dev", password: longPassword, policy: "MBI_KEY_OLD")
        guard let req = passportServer.recordedRequests.first else {
            XCTFail("No recorded request")
            return
        }
        XCTAssertTrue(req.rawBody.contains("0123456789ABCDEF"), "Captured request must truncate password to 16 characters")
        XCTAssertFalse(req.rawBody.contains("EXTRA_CHARS"), "Extra characters beyond 16 must be stripped")
    }

    func test_tier2_passport_invalidCredentialsSoapFault() async throws {
        passportServer.forceSoapFault = true
        passportServer.faultMessage = "The community server rejected these credentials."

        do {
            _ = try await passportClient.authenticate(email: "invalid@msngr.dev", password: "bad", policy: "MBI_KEY_OLD")
            XCTFail("Expected authentication to fail with SOAP Fault")
        } catch let error as PassportError {
            XCTAssertEqual(error, .authenticationFailed, "Error should be authenticationFailed")
        } catch {
            XCTFail("Unexpected error type thrown: \(error)")
        }
    }

    func test_tier2_passport_emptyCredentialsHandling() async throws {
        do {
            _ = try await passportClient.authenticate(email: "", password: "password", policy: "MBI_KEY_OLD")
            XCTFail("Expected empty email to fail validation")
        } catch let error as PassportError {
            XCTAssertEqual(error, .invalidCredentials)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await passportClient.authenticate(email: "user@msngr.dev", password: "", policy: "MBI_KEY_OLD")
            XCTFail("Expected empty password to fail validation")
        } catch let error as PassportError {
            XCTAssertEqual(error, .invalidCredentials)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(passportServer.recordedRequests.count, 0, "No network request should be made for empty credentials")
    }

    func test_tier2_passport_specialCharactersXmlEscapingInCredentials() async throws {
        passportServer.registerUser(email: "user<>&\"'@msngr.dev", password: "p@ss<>&\"'1")
        _ = try await passportClient.authenticate(email: "user<>&\"'@msngr.dev", password: "p@ss<>&\"'1", policy: "MBI_KEY_OLD")

        guard let req = passportServer.recordedRequests.first else {
            XCTFail("No request recorded")
            return
        }
        XCTAssertTrue(req.rawBody.contains("&lt;") || req.rawBody.contains("&amp;"), "Credentials with XML special characters must be escaped")
    }

    func test_tier2_passport_malformedServerXmlResponse() async throws {
        MockSOAPRouter.shared.customHandlers.append { _, _ in
            return MockSOAPResponse(statusCode: 200, xml: "<Envelope><UnclosedBody>")
        }

        do {
            _ = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123", policy: "MBI_KEY_OLD")
            XCTFail("Expected malformed XML response to throw")
        } catch let error as PassportError {
            XCTAssertEqual(error, .malformedXmlResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Feature Area 2: Notification Server Handshake (Tier 1)

    func test_tier1_nsHandshake_versionNegotiation() async throws {
        try await nsClient.connect()
        try await nsClient.sendVersionNegotiation()

        let cmd = await nsServer.waitForCommand(verb: "VER", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd, "Server should receive VER command")
        XCTAssertEqual(cmd?.verb, "VER")
        XCTAssertTrue(cmd?.parameters.contains("MSNP18") ?? false)
    }

    func test_tier1_nsHandshake_clientInformationCVR() async throws {
        try await nsClient.connect()
        try await nsClient.sendVersionNegotiation()
        try await nsClient.sendClientInfo(email: "user@msngr.dev")

        let cmd = await nsServer.waitForCommand(verb: "CVR", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd, "Server should receive CVR command")
        XCTAssertEqual(cmd?.verb, "CVR")
        XCTAssertTrue(cmd?.parameters.contains("user@msngr.dev") ?? false)
    }

    func test_tier1_nsHandshake_ssoInitiationUSR() async throws {
        try await nsClient.connect()
        try await nsClient.sendVersionNegotiation()
        try await nsClient.sendClientInfo(email: "user@msngr.dev")
        try await nsClient.sendSsoInitiate(email: "user@msngr.dev")

        let cmd = await nsServer.waitForCommand(verb: "USR", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd, "Server should receive USR SSO I command")
        XCTAssertEqual(cmd?.parameters.first, "SSO")
        XCTAssertEqual(cmd?.parameters.dropFirst().first, "I")
    }

    func test_tier1_nsHandshake_ssoCompletionWithProof() async throws {
        try await nsClient.connect()
        try await nsClient.signIn(email: "user@msngr.dev", ticket: "mockTicket", proof: "mockProof")

        let event = try await expectEvent(from: nsClient.events, timeout: TestTimeout.standard) { event in
            if case .authenticated(let email) = event {
                return email.contains("user@msngr.dev") || email.contains("mock-user")
            }
            return false
        }

        if case .authenticated(let email) = event {
            XCTAssertFalse(email.isEmpty, "Authenticated email must not be empty")
        } else {
            XCTFail("Expected authenticated event, got \(event)")
        }
    }

    func test_tier1_nsHandshake_keepAlivePingPNG() async throws {
        try await nsClient.connect()
        try await nsClient.sendPing()

        let cmd = await nsServer.waitForCommand(verb: "PNG", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd, "Server should receive PNG ping command")
        XCTAssertEqual(cmd?.verb, "PNG")
        XCTAssertNil(cmd?.transactionId, "PNG is transactionless")
    }

    // MARK: - Feature Area 2: Notification Server Handshake (Tier 2)

    func test_tier2_nsHandshake_redirectSingleHopXFR() async throws {
        let nsServer2 = MockNotificationServer()
        let port2 = try await nsServer2.start()
        defer { Task { await nsServer2.stop() } }

        await nsServer.setRedirectEndpoint(host: "127.0.0.1", port: port2)
        try await nsClient.connect()
        try await nsClient.sendSsoInitiate(email: "user@msngr.dev")

        // Redirect received: client reconnects to second server
        let client2 = NotificationServerClient(host: "127.0.0.1", port: port2)
        try await client2.connect()
        try await client2.signIn(email: "user@msngr.dev", ticket: "mockTicket", proof: "mockProof")

        let cmd = await nsServer2.waitForCommand(verb: "USR", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd, "Second server should receive handshake after redirect")
        await client2.disconnect()
    }

    func test_tier2_nsHandshake_redirectMaxHopsExceeded() async throws {
        // Configure mock NS server to redirect to itself in an infinite loop
        await nsServer.setRedirectEndpoint(host: "127.0.0.1", port: allocatedNsPort)

        try await nsClient.connect()

        do {
            try await nsClient.signIn(email: "user@msngr.dev", ticket: "mockTicket", proof: "mockProof")
            XCTFail("Expected signIn to throw NotificationServerError.maxRedirectsExceeded")
        } catch let error as NotificationServerError {
            XCTAssertEqual(error, .maxRedirectsExceeded, "Client must detect redirect loop and throw maxRedirectsExceeded")
        } catch {
            XCTFail("Unexpected error type thrown: \(error)")
        }
    }

    func test_tier2_nsHandshake_invalidRpsProofError911() async throws {
        // Configure mock NS server to reject USR SSO S with MSNP18 authentication error 911
        await nsServer.setFailSsoWith911(true)

        try await nsClient.connect()

        do {
            try await nsClient.signIn(email: "user@msngr.dev", ticket: "invalidTicket", proof: "invalidProof")
            XCTFail("Expected signIn to throw NotificationServerError.authenticationFailed(code: 911)")
        } catch let error as NotificationServerError {
            if case .authenticationFailed(let code) = error {
                XCTAssertEqual(code, 911, "Authentication error code must be 911")
            } else {
                XCTFail("Expected .authenticationFailed(code: 911), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error thrown: \(error)")
        }
    }

    func test_tier2_nsHandshake_splitTcpPacketBuffering() async throws {
        let decoder = MsnpFrameDecoder()
        let chunk1 = Data("USR 3 SSO S MBI_KEY_OLD non".utf8)
        let chunk2 = Data("ce123\r".utf8)
        let chunk3 = Data("\n".utf8)

        let frames1 = decoder.feed(chunk1)
        XCTAssertTrue(frames1.isEmpty, "Chunk 1 incomplete")

        let frames2 = decoder.feed(chunk2)
        XCTAssertTrue(frames2.isEmpty, "Chunk 2 incomplete")

        let frames3 = decoder.feed(chunk3)
        XCTAssertEqual(frames3.count, 1, "Chunk 3 should complete frame")
        XCTAssertEqual(frames3.first?.verb, "USR")
        XCTAssertEqual(frames3.first?.transactionId, 3)
    }

    func test_tier2_nsHandshake_serverAbruptDisconnectBeforeAuth() async throws {
        try await nsClient.connect()
        XCTAssertTrue(nsClient.isConnected, "Client must report isConnected == true upon ready")

        // Server abruptly closes all sockets and stops listener
        await nsServer.stop()

        let disconnectEvent = try await expectEvent(
            from: nsClient.events,
            timeout: TestTimeout.standard,
            description: "Waiting for unexpectedClosure disconnection event"
        ) { event in
            if case .disconnected(let reason) = event {
                return reason == .unexpectedClosure
            }
            return false
        }

        if case .disconnected(let reason) = disconnectEvent {
            XCTAssertEqual(reason, .unexpectedClosure, "Disconnection reason must be unexpectedClosure")
        } else {
            XCTFail("Expected .disconnected(reason: .unexpectedClosure) event, got \(disconnectEvent)")
        }

        try await waitForCondition(timeout: TestTimeout.standard, description: "Client isConnected must transition to false") {
            return self.nsClient.isConnected == false
        }
        XCTAssertFalse(nsClient.isConnected, "nsClient.isConnected must be false after server abrupt disconnect")
    }

    // MARK: - Feature Area 3: Presence Broadcast & Personal Message (Tier 1)

    func test_tier1_presence_broadcastOnlineNLN() async throws {
        try await nsClient.connect()
        try await nsClient.setPresence(.online)

        let cmd = await nsServer.waitForCommand(verb: "CHG", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.parameters.first, "NLN")
    }

    func test_tier1_presence_broadcastBusyBSY() async throws {
        try await nsClient.connect()
        try await nsClient.setPresence(.busy)

        let cmd = await nsServer.waitForCommand(verb: "CHG", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.parameters.first, "BSY")
    }

    func test_tier1_presence_broadcastAwayAWY() async throws {
        try await nsClient.connect()
        try await nsClient.setPresence(.away)

        let cmd = await nsServer.waitForCommand(verb: "CHG", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.parameters.first, "AWY")
    }

    func test_tier1_presence_personalMessageBroadcastUUX() async throws {
        try await nsClient.connect()
        try await nsClient.setPersonalMessage("Listening to Daft Punk")

        let cmd = await nsServer.waitForCommand(verb: "UUX", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Payload must be UTF-8 string")
            return
        }
        XCTAssertTrue(text.contains("Listening to Daft Punk"))
        XCTAssertTrue(text.contains("<PSM>"))
    }

    func test_tier1_presence_friendlyNameUpdatePRP() async throws {
        try await nsClient.connect()
        try await nsClient.updateDisplayName("Stefano")

        let cmd = await nsServer.waitForCommand(verb: "PRP", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.parameters.first, "MFN")
        XCTAssertEqual(cmd?.parameters.dropFirst().first, "Stefano")
    }

    // MARK: - Feature Area 3: Presence Broadcast & Personal Message (Tier 2)

    func test_tier2_presence_rapidSuccessiveStatusChanges() async throws {
        try await nsClient.connect()
        try await nsClient.setPresence(.busy)
        try await nsClient.setPresence(.away)
        try await nsClient.setPresence(.beRightBack)
        try await nsClient.setPresence(.online)

        let recorded = await nsServer.getRecordedCommands().filter { $0.verb == "CHG" }
        XCTAssertEqual(recorded.count, 4, "All 4 presence changes must be dispatched and recorded")
        let trIds = recorded.compactMap { $0.transactionId }
        XCTAssertEqual(trIds, trIds.sorted(), "Transaction IDs must be monotonically increasing")
    }

    func test_tier2_presence_emptyPsmClearsStatusMessage() async throws {
        try await nsClient.connect()
        try await nsClient.setPersonalMessage("")

        let cmd = await nsServer.waitForCommand(verb: "UUX", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("<PSM></PSM>"))
    }

    func test_tier2_presence_psmWithSpecialXmlCharacters() async throws {
        try await nsClient.connect()
        try await nsClient.setPersonalMessage("Rock & Roll <Live> '2009' \"Best\"")

        let cmd = await nsServer.waitForCommand(verb: "UUX", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        guard let payload = cmd?.payload, let text = String(data: payload, encoding: .utf8) else {
            XCTFail("Missing payload")
            return
        }
        XCTAssertTrue(text.contains("&amp;"))
        XCTAssertTrue(text.contains("&lt;Live&gt;"))
    }

    func test_tier2_presence_psmWithNumericXmlEntities() async throws {
        try await nsClient.connect()

        // Server injects personal message containing numeric entity &#x3D; (=)
        await nsServer.sendInboundPersonalMessage(contactEmail: "bob@msngr.dev", statusMessage: "Code &#x3D; 42")

        let event = try await expectEvent(
            from: nsClient.events,
            timeout: TestTimeout.standard,
            description: "Waiting for personal message changed event with unescaped entity"
        ) { event in
            if case .contactPersonalMessageChanged(let email, _) = event {
                return email == "bob@msngr.dev"
            }
            return false
        }

        if case .contactPersonalMessageChanged(let email, let message) = event {
            XCTAssertEqual(email, "bob@msngr.dev")
            XCTAssertEqual(message, "Code = 42", "Numeric XML entity &#x3D; must be unescaped to '='")
        } else {
            XCTFail("Expected .contactPersonalMessageChanged event, got \(event)")
        }
    }

    func test_tier2_presence_unsupportedStatusCodeFallback() async throws {
        let fallback = PresenceStatus(msnpPresenceCode: "UNKNOWN_STATUS")
        XCTAssertEqual(fallback, .online, "Unknown presence status must fall back to .online")
    }
}
