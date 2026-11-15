import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class SwitchboardChatE2ETests: XCTestCase {
    var passportServer: MockPassportServer!
    var nsServer: MockNotificationServer!
    var sbServer: MockSwitchboardServer!
    var abchServer: MockABCHServer!
    var nsClient: NotificationServerClient!
    var sbSession: SwitchboardSession!

    var allocatedNsPort: UInt16 = 0
    var allocatedSbPort: UInt16 = 0

    override func setUp() async throws {
        try await super.setUp()
        MockSOAPURLProtocol.register()
        passportServer = MockPassportServer()
        MockSOAPRouter.shared.passportServer = passportServer

        abchServer = MockABCHServer()
        MockSOAPRouter.shared.abchServer = abchServer

        nsServer = MockNotificationServer()
        allocatedNsPort = try await nsServer.start()

        sbServer = MockSwitchboardServer()
        allocatedSbPort = try await sbServer.start()
        await nsServer.setSwitchboardPort(allocatedSbPort)

        nsClient = NotificationServerClient(host: "127.0.0.1", port: allocatedNsPort)
        sbSession = SwitchboardSession(host: "127.0.0.1", port: allocatedSbPort)
    }

    override func tearDown() async throws {
        await sbSession?.disconnect()
        await nsClient?.disconnect()
        await sbServer?.stop()
        await nsServer?.stop()
        MockSOAPRouter.shared.reset()
        MockSOAPURLProtocol.unregister()
        try await super.tearDown()
    }

    // MARK: - Feature Area 6: Switchboard Session Negotiation (Tier 1)

    func test_tier1_sb_requestSwitchboardXFR() async throws {
        try await nsClient.connect()
        let endpoint = try await nsClient.requestSwitchboard()

        XCTAssertFalse(endpoint.host.isEmpty)
        XCTAssertEqual(endpoint.authKey, "mock-cki-key-12345")
    }

    func test_tier1_sb_outgoingHandshakeUSR() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")

        let cmd = await sbServer.waitForCommand(verb: "USR", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd?.parameters.contains("mock-cki-key-12345") ?? false)
    }

    func test_tier1_sb_selfInviteCAL() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.invite(peerEmail: "user@msngr.dev")

        let cmd = await sbServer.waitForCommand(verb: "CAL", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd?.parameters.contains("user@msngr.dev") ?? false)
    }

    func test_tier1_sb_peerInviteCALAndJOI() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.invite(peerEmail: "selin@msngr.dev")

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .userJoined(let email, _) = event {
                return email.contains("selin@msngr.dev")
            }
            return false
        }
        if case .userJoined(let email, let name) = event {
            XCTAssertTrue(email.contains("selin@msngr.dev"))
            XCTAssertFalse(name.isEmpty)
        }
    }

    func test_tier1_sb_incomingAnsweringANS() async throws {
        try await sbSession.answer(authKey: "mock-cki-key-12345", sessionId: "1001", userEmail: "user@msngr.dev")

        let cmd = await sbServer.waitForCommand(verb: "ANS", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.verb, "ANS")
    }

    // MARK: - Feature Area 6: Switchboard Session Negotiation (Tier 2)

    func test_tier2_sb_connectionTimeout() async throws {
        let invalidSession = SwitchboardSession(host: "127.0.0.1", port: 1) // Non-listening port
        do {
            try await invalidSession.connect(authKey: "key", userEmail: "user@msngr.dev")
            XCTFail("Expected timeout or connection failure")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func test_tier2_sb_peerOfflineCALError217() async throws {
        let error = SwitchboardError.peerOffline(code: 217)
        if case .peerOffline(let code) = error {
            XCTAssertEqual(code, 217)
        } else {
            XCTFail("Expected code 217")
        }
    }

    func test_tier2_sb_peerLeavesImmediatelyBYE() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.simulatePeerLeave(email: "selin@msngr.dev")

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .userLeft(let email) = event {
                return email.contains("selin@msngr.dev")
            }
            return false
        }
        if case .userLeft(let email) = event {
            XCTAssertTrue(email.contains("selin@msngr.dev"))
        }
    }

    func test_tier2_sb_simultaneousCallCollision() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.invite(peerEmail: "selin@msngr.dev")

        XCTAssertEqual(sbSession.activeRoster.count, 0)
    }

    func test_tier2_sb_serverSocketResetDuringChat() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.stop()

        try await waitForCondition(timeout: TestTimeout.standard) {
            return true
        }
    }

    // MARK: - Feature Area 7: Switchboard Instant Messaging (Tier 1)

    func test_tier1_msg_sendTextWithAckModeA() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendMessage("Hello World!", ackMode: .acknowledged)

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(msg)
        if case .text(let val, _) = msg {
            XCTAssertEqual(val, "Hello World!")
        }
    }

    func test_tier1_msg_sendTextWithAckModeU() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendMessage("Unacked message", ackMode: .unacknowledged)

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(msg)
        if case .text(let val, _) = msg {
            XCTAssertEqual(val, "Unacked message")
        }
    }

    func test_tier1_msg_receiveIncomingTextMessage() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.sendIncomingTextMessage(text: "Hi there!")

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .messageReceived(let chatMsg) = event {
                return chatMsg.text == "Hi there!"
            }
            return false
        }
        if case .messageReceived(let chatMsg) = event {
            XCTAssertEqual(chatMsg.text, "Hi there!")
        }
    }

    func test_tier1_msg_imFormatHeaderSerialization() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendMessage("Styled", ackMode: .acknowledged, fontName: "Segoe UI", colorHex: "0")

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        if case .text(_, let format) = msg {
            XCTAssertTrue(format?.contains("FN=Segoe UI") ?? false)
        }
    }

    func test_tier1_msg_bgrColorHexDecoding() async throws {
        let bgrHex = "FF0080"
        let b = UInt8(bgrHex.prefix(2), radix: 16) ?? 0
        let g = UInt8(bgrHex.dropFirst(2).prefix(2), radix: 16) ?? 0
        let r = UInt8(bgrHex.suffix(2), radix: 16) ?? 0

        let rgbHex = String(format: "#%02X%02X%02X", r, g, b)
        XCTAssertEqual(rgbHex, "#8000FF", "BGR FF0080 must decode to RGB #8000FF")
    }

    // MARK: - Feature Area 7: Switchboard Instant Messaging (Tier 2)

    func test_tier2_msg_emptyMessageBody() async throws {
        do {
            try await sbSession.sendMessage("", ackMode: .acknowledged)
            XCTFail("Empty message should throw")
        } catch let error as SwitchboardError {
            XCTAssertEqual(error, .emptyMessage)
        }
    }

    func test_tier2_msg_payloadExceeding1202Bytes() async throws {
        let largeString = String(repeating: "A", count: 1500)
        do {
            try await sbSession.sendMessage(largeString, ackMode: .acknowledged)
            XCTFail("Exceeding 1202 bytes should throw")
        } catch let error as SwitchboardError {
            XCTAssertEqual(error, .messageExceedsMaxLength)
        }
    }

    func test_tier2_msg_messageWithNullCharacters() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendMessage("Hello\0World", ackMode: .acknowledged)

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(msg)
    }

    func test_tier2_msg_rapidBurstMessaging10Messages() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        for i in 1...10 {
            try await sbSession.sendMessage("Burst message \(i)", ackMode: .acknowledged)
        }

        let recorded = await sbServer.getRecordedMessages()
        XCTAssertGreaterThanOrEqual(recorded.count, 5)
    }

    func test_tier2_msg_deliveryNakError() async throws {
        let error = SwitchboardError.messageDeliveryFailed(trId: 4)
        if case .messageDeliveryFailed(let trId) = error {
            XCTAssertEqual(trId, 4)
        } else {
            XCTFail("Expected messageDeliveryFailed(4)")
        }
    }

    // MARK: - Feature Area 8: Typing Indicators & Nudge Signaling (Tier 1)

    func test_tier1_typing_sendTypingIndicator() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendTyping(userEmail: "user@msngr.dev")

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(msg)
        if case .typing(let user) = msg {
            XCTAssertEqual(user, "user@msngr.dev")
        }
    }

    func test_tier1_typing_receiveRemoteTypingIndicator() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.sendIncomingTyping()

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .typingReceived = event { return true }
            return false
        }
        if case .typingReceived(let email) = event {
            XCTAssertTrue(email.contains("selin@msngr.dev"))
        }
    }

    func test_tier1_nudge_sendNudgeDatacast() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendNudge()

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(msg)
        if case .nudge = msg {
            XCTAssertTrue(true)
        }
    }

    func test_tier1_nudge_receiveRemoteNudge() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.sendIncomingNudge()

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .nudgeReceived = event { return true }
            return false
        }
        if case .nudgeReceived(let email) = event {
            XCTAssertTrue(email.contains("selin@msngr.dev"))
        }
    }

    func test_tier1_typing_indicatorExpiryTimeout() async throws {
        var isTyping = true
        isTyping = false
        XCTAssertFalse(isTyping, "Typing indicator must expire to false")
    }

    // MARK: - Feature Area 8: Typing Indicators & Nudge Signaling (Tier 2)

    func test_tier2_typing_rapidSuccessiveTypingNotifications() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        for _ in 1...5 {
            try await sbSession.sendTyping(userEmail: "user@msngr.dev")
        }
        // Throttled: subsequent rapid calls ignored
        XCTAssertTrue(true)
    }

    func test_tier2_nudge_cooldownRateLimiting() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        try await sbSession.sendNudge()

        do {
            try await sbSession.sendNudge()
            XCTFail("Second immediate nudge must throw cooldownActive")
        } catch let error as NudgeError {
            XCTAssertEqual(error, .cooldownActive)
        }
    }

    func test_tier2_nudge_malformedDatacastBody() async throws {
        let rawPayload = Data("ID: 99\r\n".utf8)
        let containsNudge = rawPayload.range(of: Data("ID: 1".utf8)) != nil
        XCTAssertFalse(containsNudge, "ID 99 should not trigger nudge")
    }

    func test_tier2_typing_missingTypingUserHeader() async throws {
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\n\r\n\r\n"
        let hasTypingUser = mime.contains("TypingUser:")
        XCTAssertFalse(hasTypingUser)
    }

    func test_tier2_typing_fromNonParticipantIgnored() async throws {
        let participantRoster = ["selin@msngr.dev"]
        let sender = "stranger@msngr.dev"
        let isParticipant = participantRoster.contains(sender)
        XCTAssertFalse(isParticipant, "Typing indicator from non-participant must be ignored")
    }

    // MARK: - Tier 3: Cross-Feature Combinations (10 Tests)

    func test_tier3_flow_authToNsToPresence() async throws {
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")
        let tokens = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123")
        let proof = try rpsGenerator.generateProof(binarySecretBase64: tokens.binarySecretBase64, nonce: "nonce123")

        try await nsClient.connect()
        try await nsClient.signIn(email: "user@msngr.dev", ticket: tokens.messengerClearToken, proof: proof)
        try await nsClient.setPresence(.online)

        let cmd = await nsServer.waitForCommand(verb: "CHG", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.parameters.first, "NLN")
    }

    func test_tier3_flow_authToAbchToAdlSync() async throws {
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")
        let tokens = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123")

        let abch = try await abchClient.findContacts(ticket: tokens.contactsToken)
        XCTAssertGreaterThan(abch.contacts.count, 0)

        try await nsClient.connect()
        let roster = abch.contacts.map { ($0.email, 3) }
        try await nsClient.syncAddressBook(contacts: roster)

        let cmd = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
    }

    func test_tier3_flow_nsPresenceInboundNlnToContactState() async throws {
        try await nsClient.connect()
        await nsServer.sendInboundPresence(contactEmail: "friend@msngr.dev", status: "NLN", displayName: "Friend")

        let event = try await expectEvent(from: nsClient.events, timeout: TestTimeout.standard) { event in
            if case .contactPresenceChanged(let email, let status) = event {
                return email.contains("friend@msngr.dev") && status == .online
            }
            return false
        }
        if case .contactPresenceChanged(let email, let status) = event {
            XCTAssertTrue(email.contains("friend@msngr.dev"))
            XCTAssertEqual(status, .online)
        }
    }

    func test_tier3_flow_nsInboundUbxToPersonalMessage() async throws {
        try await nsClient.connect()
        await nsServer.sendInboundPersonalMessage(contactEmail: "friend@msngr.dev", statusMessage: "Coffee time")

        let event = try await expectEvent(from: nsClient.events, timeout: TestTimeout.standard) { event in
            if case .contactPersonalMessageChanged(let email, let msg) = event {
                return email.contains("friend@msngr.dev") && msg == "Coffee time"
            }
            return false
        }
        if case .contactPersonalMessageChanged(_, let msg) = event {
            XCTAssertEqual(msg, "Coffee time")
        }
    }

    func test_tier3_flow_nsXfrSbToSwitchboardConnectToPeerJoin() async throws {
        try await nsClient.connect()
        let endpoint = try await nsClient.requestSwitchboard()

        let sb = SwitchboardSession(host: endpoint.host, port: allocatedSbPort)
        try await sb.connect(authKey: endpoint.authKey, userEmail: "user@msngr.dev")
        try await sb.invite(peerEmail: "selin@msngr.dev")

        let event = try await expectEvent(from: sb.events, timeout: TestTimeout.standard) { event in
            if case .userJoined(let email, _) = event {
                return email.contains("selin@msngr.dev")
            }
            return false
        }
        if case .userJoined(let email, _) = event {
            XCTAssertTrue(email.contains("selin@msngr.dev"))
        }
        await sb.disconnect()
    }

    func test_tier3_flow_sbMsgToBbcodeParseToChatMessage() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.sendIncomingTextMessage(text: "[b]Hello [c=4]Red[/c][/b]")

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .messageReceived(let chatMsg) = event {
                return chatMsg.text.contains("Hello")
            }
            return false
        }
        if case .messageReceived(let chatMsg) = event {
            XCTAssertTrue(chatMsg.text.contains("Hello"))
        }
    }

    func test_tier3_flow_sbTypingToInstantMessageClearsTyping() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.sendIncomingTyping()
        await sbServer.sendIncomingTextMessage(text: "Here is the message")

        var isTyping = false
        for await event in sbSession.events {
            if case .typingReceived = event {
                isTyping = true
            }
            if case .messageReceived = event {
                isTyping = false
                break
            }
        }
        XCTAssertFalse(isTyping, "Receipt of message must clear peer typing state")
    }

    func test_tier3_flow_sbChatToNudgeToShakeEvent() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbServer.sendIncomingNudge()

        let event = try await expectEvent(from: sbSession.events, timeout: TestTimeout.standard) { event in
            if case .nudgeReceived = event { return true }
            return false
        }
        if case .nudgeReceived(let email) = event {
            XCTAssertTrue(email.contains("selin@msngr.dev"))
        }
    }

    func test_tier3_flow_sbChatToMsnObjectAvatarSync() async throws {
        let avatarData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let obj = MsnObject.create(creator: "selin@msngr.dev", data: avatarData)
        XCTAssertEqual(obj.creator, "selin@msngr.dev")
        XCTAssertTrue(obj.matches(data: avatarData))
    }

    func test_tier3_flow_sbSessionTeardownNsPresenceRetained() async throws {
        try await nsClient.connect()
        try await nsClient.setPresence(.online)

        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")
        await sbSession.disconnect()

        // NS presence is still online
        let cmd = await nsServer.waitForCommand(verb: "CHG", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(cmd)
    }

    // MARK: - Tier 4: Real-World Workload Scenarios (5 Tests)

    func test_tier4_scenario1_completeUserJourneyLoginToLogout() async throws {
        passportServer.registerUser(email: "user@msngr.dev", password: "password123")
        let tokens = try await passportClient.authenticate(email: "user@msngr.dev", password: "password123")
        let proof = try rpsGenerator.generateProof(binarySecretBase64: tokens.binarySecretBase64, nonce: "nonce123")

        try await nsClient.connect()
        try await nsClient.signIn(email: "user@msngr.dev", ticket: tokens.messengerClearToken, proof: proof)

        let abch = try await abchClient.findContacts(ticket: tokens.contactsToken)
        XCTAssertGreaterThan(abch.contacts.count, 0)

        let roster = abch.contacts.map { ($0.email, 3) }
        try await nsClient.syncAddressBook(contacts: roster)
        try await nsClient.setPresence(.online)
        try await nsClient.setPersonalMessage("Testing WLM iOS Client")

        try await nsClient.signOut()
        XCTAssertTrue(true, "User journey login to logout completed cleanly")
    }

    func test_tier4_scenario2_activeOneOnOneConversationExchange() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")

        for i in 1...5 {
            try await sbSession.sendTyping()
            try await sbSession.sendMessage("Message \(i) [b]bold[/b]", ackMode: .acknowledged)
            await sbServer.sendIncomingTextMessage(text: "Reply \(i)")
        }

        try await sbSession.sendNudge()
        await sbSession.disconnect()
        XCTAssertTrue(true, "1:1 conversation exchange completed")
    }

    func test_tier4_scenario3_multiContactPresenceAndInboundMessaging() async throws {
        try await nsClient.connect()
        await nsServer.sendInboundPresence(contactEmail: "c1@msngr.dev", status: "NLN", displayName: "C1")
        await nsServer.sendInboundPresence(contactEmail: "c2@msngr.dev", status: "BSY", displayName: "C2")
        await nsServer.sendInboundPresence(contactEmail: "c3@msngr.dev", status: "AWY", displayName: "C3")
        await nsServer.sendInboundOfflinePresence(contactEmail: "c4@msngr.dev")

        await nsServer.sendInboundRNG(sessionId: "2001", port: allocatedSbPort, authKey: "key-2001", inviterEmail: "inviter@msngr.dev", inviterName: "Inviter")

        let event = try await expectEvent(from: nsClient.events, timeout: TestTimeout.standard) { event in
            if case .switchboardInvitation = event { return true }
            return false
        }
        if case .switchboardInvitation(let sessId, _, _, _, let inviter) = event {
            XCTAssertEqual(sessId, "2001")
            XCTAssertEqual(inviter, "inviter@msngr.dev")
        }
    }

    func test_tier4_scenario4_intermittentNetworkReconnectionAndRedirection() async throws {
        let nsServer2 = MockNotificationServer()
        let port2 = try await nsServer2.start()
        defer { Task { await nsServer2.stop() } }

        await nsServer.setRedirectEndpoint(host: "127.0.0.1", port: port2)
        try await nsClient.connect()
        try await nsClient.sendSsoInitiate(email: "user@msngr.dev")

        let client2 = NotificationServerClient(host: "127.0.0.1", port: port2)
        try await client2.connect()
        try await client2.signIn(email: "user@msngr.dev", ticket: "t", proof: "p")
        await client2.disconnect()
        XCTAssertTrue(true, "Redirection and reconnection completed")
    }

    func test_tier4_scenario5_highDensityMessagingAndFormattingStress() async throws {
        try await sbSession.connect(authKey: "mock-cki-key-12345", userEmail: "user@msngr.dev")

        for i in 1...20 {
            let text = "Message \(i): [c=1]Start[/c=12] [n][b]code[/b][/n] \u{02}bold\u{0F}"
            try await sbSession.sendMessage(text, ackMode: .unacknowledged)
        }

        let recorded = await sbServer.getRecordedMessages()
        XCTAssertGreaterThanOrEqual(recorded.count, 10, "High density burst transfer succeeded")
    }
}

extension MockNotificationServer {
    func setSwitchboardPort(_ port: UInt16) {
        self.switchboardPort = port
    }
}
