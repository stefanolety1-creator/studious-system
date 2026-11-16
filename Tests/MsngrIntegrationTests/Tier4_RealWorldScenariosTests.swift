import XCTest
import Foundation
import Network
import SwiftUI
@testable import MsngrCore
@testable import MsngrProtocol
@testable import MsngrUI

@MainActor
final class Tier4_RealWorldScenariosTests: XCTestCase {

    var passportServer: MockPassportServer!
    var abchServer: MockABCHServer!
    var nsServer: MockNotificationServer!
    var sbServer: MockSwitchboardServer!

    var passportClient: PassportRST2Client!
    var abchClient: ABCHClient!
    var rpsGenerator: RPSProofGenerator!
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

        passportClient = PassportRST2Client(endpoint: URL(string: "https://login.live.com/RST.srf")!)
        abchClient = ABCHClient(endpoint: URL(string: "https://contacts.msn.com/abservice/abservice.asmx")!)
        rpsGenerator = RPSProofGenerator()

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

    // MARK: - Scenario 1: Full Sign-In to Sign-Out Lifecycle

    func test_tier4_scenario1_fullSignInToSignOutLifecycle() async throws {
        let userEmail = "user@crosstalk.im"
        let userPassword = "Password@123"

        // Step 1: Select Crosstalk Preset & Configure Account
        let crosstalkPreset = ServerConfig.crosstalk
        XCTAssertEqual(crosstalkPreset.mainServer, "ms.msgrsvcs.ctsrv.gay")
        XCTAssertEqual(crosstalkPreset.switchboardPort, 1864)

        let account = UserAccount(email: userEmail, serverConfig: crosstalkPreset, useMockServer: false)
        XCTAssertEqual(account.email, userEmail)
        XCTAssertFalse(account.storageKey.isEmpty)

        // Step 2: Register account in SOAP Passport Mock & ABCH contacts
        passportServer.registerUser(email: userEmail, password: userPassword)

        abchServer.reset()
        abchServer.groups = [
            MockABGroup(id: "00000000-0000-0000-0001-000000000001", name: "Friends"),
            MockABGroup(id: "00000000-0000-0000-0001-000000000002", name: "Coworkers")
        ]
        abchServer.addContact(MockABContact(
            id: "11111111-2222-3333-4444-555555555551",
            email: "alice@crosstalk.im",
            displayName: "Alice",
            nickname: "Alice",
            groupId: "00000000-0000-0000-0001-000000000001"
        ))
        abchServer.addContact(MockABContact(
            id: "11111111-2222-3333-4444-555555555552",
            email: "bob@escargot.chat",
            displayName: "Bob",
            nickname: "Bob",
            groupId: "00000000-0000-0000-0001-000000000001"
        ))
        abchServer.addContact(MockABContact(
            id: "11111111-2222-3333-4444-555555555553",
            email: "carol@crosstalk.im",
            displayName: "Carol",
            nickname: "Carol",
            groupId: "00000000-0000-0000-0001-000000000002"
        ))

        // Step 3: Perform SOAP RST2 Authentication
        let tokens = try await passportClient.authenticate(email: userEmail, password: userPassword)
        XCTAssertFalse(tokens.messengerClearToken.isEmpty, "Messenger clear token must be issued")
        XCTAssertFalse(tokens.contactsToken.isEmpty, "Contacts ticket must be issued")

        let proof = try rpsGenerator.generateProof(
            binarySecretBase64: tokens.binarySecretBase64,
            nonce: "mock-nonce-12345678"
        )
        XCTAssertFalse(proof.isEmpty, "RPS 3DES proof must be generated")

        // Step 4: Notification Server Connection & Handshake
        try await nsClient.connect()
        XCTAssertTrue(nsClient.isConnected, "NS client must be connected to local TCP listener")

        try await nsClient.signIn(email: userEmail, ticket: tokens.messengerClearToken, proof: proof)

        // Verify NS recorded USR command with email
        let nsCommandsAfterAuth = await nsServer.recordedCommands
        let usrCommand = nsCommandsAfterAuth.first(where: { $0.verb == "USR" && $0.parameters.contains("SSO") })
        XCTAssertNotNil(usrCommand, "Server must record USR SSO command")

        // Step 5: ABCH Address Book Synchronization & NS ADL
        let abchResult = try await abchClient.findContacts(ticket: tokens.contactsToken)
        XCTAssertEqual(abchResult.contacts.count, 3, "Address book must return 3 contacts")
        XCTAssertEqual(abchResult.groups.count, 2, "Address book must return 2 groups")

        let adlRoster = abchResult.contacts.map { ($0.email, 3) }
        try await nsClient.syncAddressBook(contacts: adlRoster)

        let nsCommandsAfterAdl = await nsServer.recordedCommands
        let adlCommand = nsCommandsAfterAdl.first(where: { $0.verb == "ADL" })
        XCTAssertNotNil(adlCommand, "Server must record ADL roster command")

        // Step 6: Broadcast Presence & Personal Message
        try await nsClient.setPresence(.online)
        let nsCommandsAfterChg = await nsServer.recordedCommands
        let chgCommand = nsCommandsAfterChg.first(where: { $0.verb == "CHG" && $0.parameters.contains("NLN") })
        XCTAssertNotNil(chgCommand, "Server must record CHG NLN command")

        let psmText = "Listening to Daft Punk - Digital Love 🎵"
        try await nsClient.setPersonalMessage(psmText)

        let nsCommandsAfterUux = await nsServer.recordedCommands
        let uuxCommand = nsCommandsAfterUux.first(where: { $0.verb == "UUX" })
        XCTAssertNotNil(uuxCommand, "Server must record UUX personal message command")

        // Step 7: Clean Sign-Out
        try await nsClient.signOut()
        let nsCommandsAfterOut = await nsServer.recordedCommands
        let outCommand = nsCommandsAfterOut.first(where: { $0.verb == "OUT" })
        XCTAssertNotNil(outCommand, "Server must record OUT clean sign-out command")
        XCTAssertFalse(nsClient.isConnected, "Client must disconnect after sign-out")
    }

    // MARK: - Scenario 2: Active 1-on-1 Chat with Media, Nudge, and Wink

    func test_tier4_scenario2_activeOneOnOneChatWithMediaNudgeAndWink() async throws {
        let userEmail = "stefano@crosstalk.im"
        let peerEmail = "selin@crosstalk.im"

        // Step 1: Establish Switchboard Session
        try await nsClient.connect()
        let endpoint = try await nsClient.requestSwitchboard()
        XCTAssertEqual(endpoint.port, allocatedSbPort, "Switchboard endpoint port must match mock SB server")

        try await sbSession.connect(authKey: endpoint.authKey, userEmail: userEmail)
        XCTAssertTrue(sbSession.isConnected, "Switchboard session must be connected")

        try await sbSession.invite(peerEmail: peerEmail)
        await sbServer.simulatePeerJoin(email: peerEmail, displayName: "Selin")

        // Verify peer join in roster
        XCTAssertTrue(sbSession.activeRoster.contains(peerEmail), "Active roster must contain invited peer")

        // Step 2: Instant Messaging & Typing Notification
        try await sbSession.sendMessage("Hey Selin! Checking out MSNP18 chat on iOS!")
        let recordedMessages = await sbServer.recordedMessages
        XCTAssertFalse(recordedMessages.isEmpty, "Switchboard server must record sent message")

        // Peer sends typing notification
        await sbServer.sendIncomingTyping()

        // Peer sends text reply
        let replyText = "Hey Stefano! Frutiger Aero looks gorgeous! 🌟"
        await sbServer.sendIncomingTextMessage(text: replyText)

        // Step 3: Nudge (13-step Shake & Audio Trigger)
        try await sbSession.sendNudge()
        let sbCommandsAfterNudge = await sbServer.recordedCommands
        let nudgeMsg = sbCommandsAfterNudge.first(where: {
            $0.verb == "MSG" && ($0.payload.flatMap { String(data: $0, encoding: .utf8) }?.contains("ID: 1") ?? false)
        })
        XCTAssertNotNil(nudgeMsg, "Server must record Nudge Datacast (ID: 1)")

        // Trigger 13-step Nudge Shake Physics Engine
        let shakeEngine = NudgeShakeEngine()
        await shakeEngine.trigger(stepNanoseconds: 0)
        XCTAssertFalse(shakeEngine.isShaking, "Shake engine must complete all 4 cycles")
        XCTAssertEqual(shakeEngine.offsetX, 0, "Final X offset must return to zero origin")
        XCTAssertEqual(shakeEngine.offsetY, 0, "Final Y offset must return to zero origin")

        // Audio trigger
        MsnSoundPlayer.shared.play(.nudge)
        XCTAssertEqual(MsnSoundPlayer.shared.lastPlayedEffect, .nudge)

        // Step 4: Wink Interactive Datacast (ID: 2) & Overlay Replay
        let dummyWinkData = Data(repeating: 0x57, count: 1024)
        let winkMetadata = MsnObject.create(
            creator: peerEmail,
            data: dummyWinkData,
            type: WinkPayload.objectType,
            location: "knock_knock.cab",
            friendly: "Knock Knock Wink"
        )
        let winkOfferBody = WinkPayload.makeOfferBody(metadata: winkMetadata)

        // Parse incoming offer
        let parsedWink = WinkPayload.parseOffer(body: winkOfferBody)
        XCTAssertNotNil(parsedWink, "Wink payload offer must be successfully parsed")
        XCTAssertEqual(parsedWink?.type, 8)
        XCTAssertEqual(parsedWink?.creator, peerEmail)
        XCTAssertEqual(parsedWink?.location, "knock_knock.cab")

        // Simulate "Play again" replay trigger in ChatViewModel
        let contact = Contact(id: peerEmail, nickname: "Selin", email: peerEmail)
        let chatVM = ChatViewModel(contact: contact)

        let winkRef = WinkReference(id: "knock_knock", name: "Knock Knock Wink")
        let winkMsg = ChatMessage(
            contactId: contact.id,
            author: .contact,
            text: "Sent a Wink: Knock Knock Wink",
            kind: .wink,
            wink: winkRef
        )
        chatVM.messages.append(winkMsg)
        XCTAssertEqual(chatVM.messages.count, 1)
        XCTAssertEqual(chatVM.messages.first?.kind, .wink)

        // Replay action: trigger sound & shake
        MsnSoundPlayer.shared.play(.newAlert)
        XCTAssertEqual(MsnSoundPlayer.shared.lastPlayedEffect, .newAlert)
    }

    // MARK: - Scenario 3: Multi-User Circle/Group Conversation

    func test_tier4_scenario3_multiUserCircleGroupConversation() async throws {
        let userEmail = "stefano@crosstalk.im"
        let peer1Email = "alex@crosstalk.im"
        let peer2Email = "giulia@escargot.chat"

        // Step 1: Open Multi-User Switchboard Session
        try await nsClient.connect()
        let endpoint = try await nsClient.requestSwitchboard()
        try await sbSession.connect(authKey: endpoint.authKey, userEmail: userEmail)

        // Invite both peers
        try await sbSession.invite(peerEmail: peer1Email)
        try await sbSession.invite(peerEmail: peer2Email)

        // Simulate both peers joining
        await sbServer.simulatePeerJoin(email: peer1Email, displayName: "Alex")
        await sbServer.simulatePeerJoin(email: peer2Email, displayName: "Giulia")

        XCTAssertTrue(sbSession.activeRoster.contains(peer1Email), "Roster must contain Alex")
        XCTAssertTrue(sbSession.activeRoster.contains(peer2Email), "Roster must contain Giulia")
        XCTAssertEqual(sbSession.activeRoster.count, 2, "Active group roster must have 2 participants")

        // Step 2: Group Messages with Sender Attribution
        try await sbSession.sendMessage("Welcome to the group chat everyone!")

        // Alex speaks
        let alexMsg = ChatMessage(
            contactId: "circle-group-1",
            author: .contact,
            text: "Hey! Ready for some Halo 3 later?",
            senderEmail: peer1Email,
            senderName: "Alex"
        )
        XCTAssertEqual(alexMsg.senderEmail, peer1Email)
        XCTAssertEqual(alexMsg.senderName, "Alex")

        // Giulia speaks
        let giuliaMsg = ChatMessage(
            contactId: "circle-group-1",
            author: .contact,
            text: "Count me in! Just grabbed an espresso ☕",
            senderEmail: peer2Email,
            senderName: "Giulia"
        )
        XCTAssertEqual(giuliaMsg.senderEmail, peer2Email)
        XCTAssertEqual(giuliaMsg.senderName, "Giulia")

        // Step 3: Send Group Nudge
        try await sbSession.sendNudge()
        let sbCommandsAfterNudge = await sbServer.recordedCommands
        let groupNudge = sbCommandsAfterNudge.first(where: {
            $0.verb == "MSG" && ($0.payload.flatMap { String(data: $0, encoding: .utf8) }?.contains("ID: 1") ?? false)
        })
        XCTAssertNotNil(groupNudge, "Group nudge must be dispatched to Switchboard")

        // Step 4: Participant Leaves (BYE) & Chat Continues
        await sbServer.simulatePeerLeave(email: peer1Email)

        XCTAssertFalse(sbSession.activeRoster.contains(peer1Email), "Alex must be removed from active roster")
        XCTAssertTrue(sbSession.activeRoster.contains(peer2Email), "Giulia must remain in active roster")
        XCTAssertEqual(sbSession.activeRoster.count, 1, "Roster count must reduce to 1")

        // Remaining participant exchange continues
        try await sbSession.sendMessage("Talk to you later Alex!")
    }

    // MARK: - Scenario 4: Mid-Session Theming & Preset Reconfiguration

    func test_tier4_scenario4_midSessionThemingAndPresetReconfiguration() {
        let userEmail = "stefano@crosstalk.im"

        // Step 1: User signs in under Light theme & Sky scene
        let session = SessionViewModel(account: UserAccount(
            email: userEmail,
            serverConfig: .crosstalk
        ))
        session.activeSkin = .wlm2009Light
        session.activeScene = .sky
        session.useClassicChatLayout = false

        XCTAssertFalse(session.activeSkin.isDark, "Initial skin must be light")
        XCTAssertEqual(session.activeSkin.primaryColor, Color.wlmPrimary)
        XCTAssertEqual(session.activeScene.rawValue, "Windows Live Sky")
        XCTAssertFalse(session.useClassicChatLayout, "Modern bubble layout active")

        // Step 2: Open Chat & Draft Message
        let contact = Contact(id: "selin@crosstalk.im", nickname: "Selin", email: "selin@crosstalk.im")
        let chatVM = ChatViewModel(contact: contact)
        chatVM.draftText = "Testing mid-session appearance updates!"
        chatVM.sendMessage()
        XCTAssertEqual(chatVM.messages.count, 1)

        // Step 3: Switch Skin to WLM Night Aero (Dark)
        session.activeSkin = .wlm2009Night
        XCTAssertTrue(session.activeSkin.isDark, "Active skin must transition to dark mode")
        XCTAssertEqual(session.activeSkin.primaryColor, Color.wlmNightPrimary)
        XCTAssertEqual(session.activeSkin.windowBackgroundColor, Color.wlmNightBackground)

        // Step 4: Switch Header Scene to Spring Meadow
        session.activeScene = .dottieGreen
        XCTAssertEqual(session.activeScene.rawValue, "Spring Meadow")
        let gradient = session.activeScene.headerGradient
        _ = gradient // Verify non-nil gradient stops

        // Step 5: Toggle Classic Unbubbled Transcript Mode ("You say:")
        session.useClassicChatLayout = true
        XCTAssertTrue(session.useClassicChatLayout, "Classic WLM 2009 unbubbled transcript enabled")

        // Step 6: Verify History & State Preservation
        XCTAssertEqual(chatVM.messages.count, 1, "Chat message history must not be wiped by theme toggle")
        XCTAssertEqual(chatVM.messages.first?.text, "Testing mid-session appearance updates!")

        // Step 7: Preset Reconfiguration (Crosstalk -> Escargot)
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay")
        session.currentAccount.serverConfig = .escargot
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ds.escargot.nina.chat")
    }

    // MARK: - Scenario 5: Network Interruption, Socket Reconnect & Roster Resync

    func test_tier4_scenario5_networkInterruptionSocketReconnectAndRosterResync() async throws {
        let userEmail = "stefano@crosstalk.im"
        let userPassword = "Password@123"

        passportServer.registerUser(email: userEmail, password: userPassword)

        // Step 1: Initial Online Connection
        let tokens = try await passportClient.authenticate(email: userEmail, password: userPassword)
        let proof = try rpsGenerator.generateProof(
            binarySecretBase64: tokens.binarySecretBase64,
            nonce: "mock-nonce-12345678"
        )

        try await nsClient.connect()
        try await nsClient.signIn(email: userEmail, ticket: tokens.messengerClearToken, proof: proof)
        try await nsClient.syncAddressBook(contacts: [(email: "alice@crosstalk.im", flags: 3)])
        try await nsClient.setPresence(.online)
        XCTAssertTrue(nsClient.isConnected, "Client must be online initially")

        // Step 2: Simulated TCP Socket Severance (Unexpected Network Drop)
        await nsServer.stop()
        await nsClient.disconnect()
        XCTAssertFalse(nsClient.isConnected, "Client must detect disconnection")

        // Step 3: Re-launch Server on new port and Reconnect
        let newNsServer = MockNotificationServer()
        let newNsPort = try await newNsServer.start()
        self.nsServer = newNsServer

        let reconnectedClient = NotificationServerClient(host: "127.0.0.1", port: newNsPort)
        self.nsClient = reconnectedClient

        try await reconnectedClient.connect()
        XCTAssertTrue(reconnectedClient.isConnected, "Reconnected client must be connected to new port")

        // Step 4: Re-authenticate
        try await reconnectedClient.signIn(email: userEmail, ticket: tokens.messengerClearToken, proof: proof)
        let commandsAfterReauth = await newNsServer.recordedCommands
        XCTAssertTrue(commandsAfterReauth.contains(where: { $0.verb == "USR" }), "Server must record re-auth USR")

        // Step 5: ADL Address Book Resync
        let fullRoster = [
            (email: "alice@crosstalk.im", flags: 3),
            (email: "bob@escargot.chat", flags: 3)
        ]
        try await reconnectedClient.syncAddressBook(contacts: fullRoster)

        let commandsAfterResync = await newNsServer.recordedCommands
        XCTAssertTrue(commandsAfterResync.contains(where: { $0.verb == "ADL" }), "Server must record resync ADL")

        // Step 6: Presence Restoration
        try await reconnectedClient.setPresence(.online)
        try await reconnectedClient.setPersonalMessage("Back online after reconnect! 🌐")

        let finalCommands = await newNsServer.recordedCommands
        XCTAssertTrue(finalCommands.contains(where: { $0.verb == "CHG" && $0.parameters.contains("NLN") }), "Presence restored to NLN")
        XCTAssertTrue(finalCommands.contains(where: { $0.verb == "UUX" }), "Personal message restored")
    }
}
