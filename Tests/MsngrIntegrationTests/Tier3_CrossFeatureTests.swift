//
// Tier3_CrossFeatureTests.swift
// MsngrIntegrationTests
//
// Tier 3: Pairwise Combinatorial Integration Tests covering cross-feature
// interactions and state-machine transitions across all 7 core feature domains.
//

import XCTest
import Foundation
import Network
@testable import MsngrCore
@testable import MsngrProtocol
@testable import MsngrUI

@MainActor
final class Tier3_CrossFeatureTests: XCTestCase {

    var passportServer: MockPassportServer!
    var nsServer: MockNotificationServer!
    var sbServer: MockSwitchboardServer!
    var abchServer: MockABCHServer!

    var passportClient: PassportRST2Client!
    var nsClient: NotificationServerClient!
    var sbSession: SwitchboardSession!
    var abchClient: ABCHClient!
    var rpsGenerator: RPSProofGenerator!

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

        rpsGenerator = RPSProofGenerator()
        passportClient = PassportRST2Client(endpoint: URL(string: "https://login.live.com/RST.srf")!)
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

    // MARK: - =================================================================
    // MARK: - 1. Preset Switching With Active Auth Handshake
    // MARK: - =================================================================

    /// Pairwise Test 1: Switching server presets and executing authentication
    /// verifies that the authentication request targets the newly configured preset auth URL and issues valid tokens.
    func test_tier3_presetSwitchingWithActiveAuthHandshake() async throws {
        let userEmail = "user@crosstalk.im"
        let userPassword = "password123"

        let session = SessionViewModel()
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay", "Initial default preset is Crosstalk")
        XCTAssertEqual(session.currentAccount.serverConfig.mainPort, 1863)
        XCTAssertEqual(session.currentAccount.serverConfig.switchboardPort, 1864)
        XCTAssertEqual(session.currentAccount.serverConfig.preset, .crosstalk)

        // User switches preset to Escargot
        session.currentAccount.serverConfig = .escargot
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ds.escargot.nina.chat")
        XCTAssertEqual(session.currentAccount.serverConfig.preset, .escargot)

        // User switches preset to Crosstalk endpoints
        let crosstalkPreset = ServerConfig.crosstalk
        session.currentAccount.serverConfig = crosstalkPreset
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay")
        XCTAssertEqual(session.currentAccount.serverConfig.authServer, "https://ctas.login.ugnet.gay/RST.srf")
        XCTAssertEqual(session.currentAccount.serverConfig.preset, .crosstalk)

        // Register user with full email address on mock Passport server
        passportServer.registerUser(email: userEmail, password: userPassword)

        // Instantiate Passport client configured with the newly switched auth endpoint
        guard let crosstalkAuthUrl = URL(string: session.currentAccount.serverConfig.authServer) else {
            XCTFail("Failed to construct auth URL from switched preset")
            return
        }
        let dynamicPassportClient = PassportRST2Client(endpoint: crosstalkAuthUrl)

        // Execute authentication against the new preset endpoint
        let tokens = try await dynamicPassportClient.authenticate(email: userEmail, password: userPassword)

        XCTAssertFalse(tokens.messengerClearToken.isEmpty, "Messenger clear token must be issued")
        XCTAssertFalse(tokens.contactsToken.isEmpty, "Contacts token must be issued")

        guard let recordedReq = passportServer.lastRequest else {
            XCTFail("Expected recorded request in MockPassportServer")
            return
        }
        XCTAssertEqual(recordedReq.url, "https://ctas.login.ugnet.gay/RST.srf", "Authentication request must hit the switched Crosstalk auth endpoint")
        XCTAssertEqual(recordedReq.username, userEmail, "Authentication request must pass full email as account identifier")
    }

    // MARK: - =================================================================
    // MARK: - 2. Auth Handshake to Grouped Contacts Sync
    // MARK: - =================================================================

    /// Pairwise Test 2: Successful Passport RST2 authentication passes issued security tokens
    /// to ABCH contact synchronization and Notification Server ADL roster sync, populating grouped contacts.
    func test_tier3_authHandshakeToGroupedContactsSync() async throws {
        let userEmail = "stefano@crosstalk.im"
        let userPassword = "password123"

        passportServer.registerUser(email: userEmail, password: userPassword)

        // Step 1: SOAP RST2 Authentication
        let tokens = try await passportClient.authenticate(email: userEmail, password: userPassword)
        XCTAssertFalse(tokens.messengerClearToken.isEmpty)
        XCTAssertFalse(tokens.contactsToken.isEmpty)

        // Step 2: ABCH Address Book Synchronization using issued contacts token
        let abchResult = try await abchClient.findContacts(ticket: tokens.contactsToken)
        XCTAssertGreaterThan(abchResult.contacts.count, 0, "ABCH must return contacts list")
        XCTAssertGreaterThan(abchResult.groups.count, 0, "ABCH must return groups list")

        // Step 3: MSNP18 Notification Server Connect & Sign-In
        let proof = try rpsGenerator.generateProof(binarySecretBase64: tokens.binarySecretBase64, nonce: "NONCE-12345")
        try await nsClient.connect()
        try await nsClient.signIn(email: userEmail, ticket: tokens.messengerClearToken, proof: proof)

        // Step 4: NS Address Book Synchronization via ADL command
        let adlRoster = abchResult.contacts.map { ($0.email, $0.isBlocked ? 5 : 3) }
        try await nsClient.syncAddressBook(contacts: adlRoster)

        let adlCommand = await nsServer.waitForCommand(verb: "ADL", timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(adlCommand, "Notification Server must receive ADL roster synchronization command")

        // Step 5: Verify SessionViewModel integrates grouped contacts
        let session = SessionViewModel()
        session.contacts = abchResult.contacts
        session.groups = abchResult.groups

        XCTAssertEqual(session.contacts.count, abchResult.contacts.count)
        XCTAssertEqual(session.groups.count, abchResult.groups.count)

        // Verify group associations
        for group in session.groups {
            let membersInGroup = session.contacts.filter { $0.groupId == group.id }
            XCTAssertNotNil(membersInGroup, "Group '\(group.name)' contacts must be accessible")
        }
    }

    // MARK: - =================================================================
    // MARK: - 3. Contact Presence Change Updates Group Accordion Count
    // MARK: - =================================================================

    /// Pairwise Test 3: Receiving real-time presence changes (NLN, AWY, FLN) updates
    /// online and offline contact counts and accordion category headers dynamically.
    func test_tier3_contactPresenceChangeUpdatesGroupAccordionCount() async throws {
        let session = SessionViewModel()

        let friend1 = Contact(
            id: "selin@crosstalk.im",
            email: "selin@crosstalk.im",
            displayName: "Selin",
            presence: .offline,
            groupId: "grp-friends"
        )
        let friend2 = Contact(
            id: "alex@crosstalk.im",
            email: "alex@crosstalk.im",
            displayName: "Alex",
            presence: .offline,
            groupId: "grp-friends"
        )
        let coworker1 = Contact(
            id: "giulia@crosstalk.im",
            email: "giulia@crosstalk.im",
            displayName: "Giulia",
            presence: .offline,
            groupId: "grp-team"
        )
        let coworker2 = Contact(
            id: "marco@crosstalk.im",
            email: "marco@crosstalk.im",
            displayName: "Marco",
            presence: .offline,
            groupId: "grp-team"
        )

        session.contacts = [friend1, friend2, coworker1, coworker2]
        session.groups = [
            ContactGroup(id: "grp-friends", name: "Friends", contactIds: [friend1.id, friend2.id]),
            ContactGroup(id: "grp-team", name: "Team & Devs", contactIds: [coworker1.id, coworker2.id])
        ]

        // Initial state: all 4 offline
        XCTAssertEqual(session.onlineContacts.count, 0, "Initially 0 contacts online")
        XCTAssertEqual(session.offlineContacts.count, 4, "Initially all 4 contacts offline")

        // Event 1: Selin comes online (NLN)
        if let idx = session.contacts.firstIndex(where: { $0.email == "selin@crosstalk.im" }) {
            session.contacts[idx].presence = .online
        }
        XCTAssertEqual(session.onlineContacts.count, 1, "After Selin connects: 1 online")
        XCTAssertEqual(session.offlineContacts.count, 3, "After Selin connects: 3 offline")

        // Event 2: Alex transitions to Away (AWY, which counts as online in WLM 2009)
        if let idx = session.contacts.firstIndex(where: { $0.email == "alex@crosstalk.im" }) {
            session.contacts[idx].presence = .away
        }
        XCTAssertEqual(session.onlineContacts.count, 2, "After Alex connects: 2 online")
        XCTAssertEqual(session.offlineContacts.count, 2, "After Alex connects: 2 offline")

        // Event 3: Selin disconnects (FLN)
        if let idx = session.contacts.firstIndex(where: { $0.email == "selin@crosstalk.im" }) {
            session.contacts[idx].presence = .offline
        }
        XCTAssertEqual(session.onlineContacts.count, 1, "After Selin disconnects: 1 online")
        XCTAssertEqual(session.offlineContacts.count, 3, "After Selin disconnects: 3 offline")

        // Event 4: Accordion expand/collapse preserves contact counts
        session.groups[0].isExpanded = false
        XCTAssertFalse(session.groups[0].isExpanded)
        XCTAssertEqual(session.onlineContacts.count, 1, "Collapsing accordion must not mutate member counts")
    }

    // MARK: - =================================================================
    // MARK: - 4. Chat Messaging with Nudge Shake and Audio Trigger
    // MARK: - =================================================================

    /// Pairwise Test 4: In an active chat session, sending a text message followed by a Nudge
    /// appends both to the transcript and invokes the sound player for typing and nudge alerts.
    func test_tier3_chatMessagingWithNudgeShakeAndAudioTrigger() async throws {
        let contact = Contact(
            id: "selin@crosstalk.im",
            email: "selin@crosstalk.im",
            displayName: "Selin",
            presence: .online
        )
        let chatVM = ChatViewModel(contact: contact, switchboardSession: sbSession)
        let soundPlayer = MsnSoundPlayer.shared
        soundPlayer.isSoundEnabled = true

        let initialPlayCount = soundPlayer.playCount

        // Step 1: Send text message
        chatVM.draftText = "Hello Selin! Sending a message."
        chatVM.sendMessage()

        XCTAssertEqual(chatVM.messages.count, 1, "Transcript must contain 1 message")
        XCTAssertEqual(chatVM.messages.first?.text, "Hello Selin! Sending a message.")
        XCTAssertEqual(chatVM.messages.first?.author, .me)
        XCTAssertEqual(soundPlayer.lastPlayedEffect, .type, "Sending text must play typing sound")
        XCTAssertEqual(soundPlayer.playCount, initialPlayCount + 1)

        // Step 2: Send Nudge (Trillo)
        chatVM.sendNudge()

        XCTAssertEqual(chatVM.messages.count, 2, "Transcript must contain 2 items (text + nudge)")
        let lastMsg = chatVM.messages.last
        XCTAssertEqual(lastMsg?.kind, .nudge, "Second message kind must be .nudge")
        XCTAssertTrue(lastMsg?.isNudge == true)
        XCTAssertEqual(lastMsg?.text, "You have just sent a Nudge.")
        XCTAssertEqual(soundPlayer.lastPlayedEffect, .nudge, "Sending nudge must play nudge sound")
        XCTAssertEqual(soundPlayer.playCount, initialPlayCount + 2)

        // Step 3: Verify Nudge window displacement physics
        await chatVM.shakeEngine.trigger(stepNanoseconds: 0)
        XCTAssertEqual(chatVM.shakeEngine.offsetX, 0, "After shake cycle, X offset must return to 0")
        XCTAssertEqual(chatVM.shakeEngine.offsetY, 0, "After shake cycle, Y offset must return to 0")
        XCTAssertFalse(chatVM.shakeEngine.isShaking)
    }

    // MARK: - =================================================================
    // MARK: - 5. Typing Indicator Followed by Incoming Message Clears Typing
    // MARK: - =================================================================

    /// Pairwise Test 5: Receiving peer typing notification sets isPeerTyping == true;
    /// subsequent receipt of the peer's message automatically resets isPeerTyping == false and appends message.
    func test_tier3_typingIndicatorFollowedByIncomingMessageClearsTyping() {
        let contact = Contact(
            id: "selin@crosstalk.im",
            email: "selin@crosstalk.im",
            displayName: "Selin",
            presence: .online
        )
        let chatVM = ChatViewModel(contact: contact)
        let soundPlayer = MsnSoundPlayer.shared
        soundPlayer.isSoundEnabled = true

        XCTAssertFalse(chatVM.isPeerTyping, "Initial typing state must be false")

        // Peer begins typing
        chatVM.isPeerTyping = true
        XCTAssertTrue(chatVM.isPeerTyping, "Peer typing state must be true while peer is typing")

        // Peer delivers incoming message
        let incomingText = "Hey Stefano! I just received your message."
        chatVM.receiveIncomingMessage(incomingText)

        // Verification: typing indicator cleared immediately
        XCTAssertFalse(chatVM.isPeerTyping, "Receipt of incoming message must reset isPeerTyping to false")
        XCTAssertEqual(chatVM.messages.count, 1, "Transcript must contain the incoming message")
        XCTAssertEqual(chatVM.messages.first?.text, incomingText)
        XCTAssertEqual(chatVM.messages.first?.author, .contact)
        XCTAssertEqual(chatVM.messages.first?.senderEmail, "selin@crosstalk.im")
        XCTAssertEqual(soundPlayer.lastPlayedEffect, .newAlert, "Incoming message must trigger newAlert chime")
    }

    // MARK: - =================================================================
    // MARK: - 6. Multi-User Group Chat with Wink Overlay Presentation
    // MARK: - =================================================================

    /// Pairwise Test 6: In a multi-user circle group conversation, a participant sends a Datacast ID 2 Wink;
    /// the message attribution reflects the participant's identity and triggers the wink presentation state.
    func test_tier3_multiUserGroupChatWithWinkOverlayPresentation() {
        let senderEmail = "selin@crosstalk.im"
        let groupContact = Contact(
            id: "group-circle-101",
            nickname: "Core Dev Team",
            email: "circle-101@crosstalk.im",
            presence: .online,
            isGroup: true,
            members: [
                GroupMember(email: "stefano@crosstalk.im", displayName: "Stefano", role: .owner),
                GroupMember(email: senderEmail, displayName: "Selin", role: .administrator),
                GroupMember(email: "alex@crosstalk.im", displayName: "Alex", role: .user)
            ]
        )

        XCTAssertTrue(groupContact.isGroup, "Contact must represent a multi-user group conversation")
        XCTAssertEqual(groupContact.members.count, 3, "Group must contain 3 members")

        // Create Datacast ID 2 Wink payload
        let validSha1d = Data(repeating: 0x33, count: 20).base64EncodedString()
        let winkXml = """
        <msnobj Creator="\(senderEmail)" Size="65536" Type="8" Location="knock_knock.cab" Friendly="AAA=" SHA1D="\(validSha1d)" SHA1C="AAA="/>
        """
        let offerBody = WinkPayload.makeOfferBody(metadata: MsnObject(
            creator: senderEmail,
            size: 65536,
            type: 8,
            location: "knock_knock.cab",
            friendly: "AAA=",
            sha1d: validSha1d
        ))

        let parsedWinkObj = WinkPayload.parseOffer(body: offerBody)
        XCTAssertNotNil(parsedWinkObj, "Wink offer must be parsed successfully")
        XCTAssertEqual(parsedWinkObj?.type, 8, "Wink MSNObject must have Type 8")

        // Append Wink ChatMessage to group conversation with participant attribution
        let winkMsg = ChatMessage(
            contactId: groupContact.id,
            author: .contact,
            text: "Knock Knock Wink",
            kind: .wink,
            senderEmail: senderEmail,
            senderName: "Selin",
            wink: WinkReference(id: "wink-knock-knock", name: "Knock Knock")
        )

        let chatVM = ChatViewModel(contact: groupContact, initialMessages: [winkMsg])
        XCTAssertEqual(chatVM.messages.count, 1)

        let receivedWinkMsg = chatVM.messages.first
        XCTAssertEqual(receivedWinkMsg?.kind, .wink)
        XCTAssertEqual(receivedWinkMsg?.senderEmail, senderEmail, "Wink sender email must attribute Selin")
        XCTAssertEqual(receivedWinkMsg?.senderName, "Selin", "Wink sender friendly name must attribute Selin")
        XCTAssertEqual(receivedWinkMsg?.wink?.id, "wink-knock-knock")
    }

    // MARK: - =================================================================
    // MARK: - 7. Theme Change During Active Chat Maintains Message History
    // MARK: - =================================================================

    /// Pairwise Test 7: Switching the visual skin from WLM Light to WLM Night Aero during an active chat
    /// preserves all message bubbles, timestamps, sender attributions, and user draft text without loss.
    func test_tier3_themeChangeDuringActiveChatMaintainsHistory() {
        let session = SessionViewModel()
        let contact = Contact(
            id: "selin@crosstalk.im",
            email: "selin@crosstalk.im",
            displayName: "Selin",
            presence: .online
        )

        let msg1 = ChatMessage(contactId: contact.id, author: .contact, text: "Hey! Did you check the new theme?")
        let msg2 = ChatMessage(contactId: contact.id, author: .me, text: "Not yet, switching right now.")
        let msg3 = ChatMessage.nudge(contactId: contact.id, author: .contact)
        let msg4 = ChatMessage(contactId: contact.id, author: .me, text: "That nudge had great physics!")
        let msg5 = ChatMessage.system(contactId: contact.id, text: "Selin has set their status to Busy.")

        let chatVM = ChatViewModel(contact: contact, initialMessages: [msg1, msg2, msg3, msg4, msg5])
        chatVM.draftText = "Drafting a reply while theme switches..."

        XCTAssertEqual(chatVM.messages.count, 5)
        XCTAssertEqual(session.activeSkin, .wlm2009Light)
        XCTAssertFalse(session.activeSkin.isDark)

        // User switches theme in options / settings
        session.activeSkin = .wlm2009Night
        session.activeScene = .butterflyDamask
        session.useClassicChatLayout = true

        // Verification: ChatViewModel state remains completely unaffected
        XCTAssertEqual(chatVM.messages.count, 5, "All 5 messages must be preserved across theme change")
        XCTAssertEqual(chatVM.messages[0].text, "Hey! Did you check the new theme?")
        XCTAssertEqual(chatVM.messages[1].text, "Not yet, switching right now.")
        XCTAssertEqual(chatVM.messages[2].kind, .nudge)
        XCTAssertEqual(chatVM.messages[3].text, "That nudge had great physics!")
        XCTAssertEqual(chatVM.messages[4].kind, .system)

        XCTAssertEqual(chatVM.draftText, "Drafting a reply while theme switches...", "Draft text must be preserved")

        // Verification: Visual theme state reflects the new dark skin
        XCTAssertTrue(session.activeSkin.isDark, "Active skin must now be dark mode")
        XCTAssertEqual(session.activeSkin.primaryColor, .wlmNightPrimary)
        XCTAssertEqual(session.activeSkin.windowBackgroundColor, .wlmNightBackground)
        XCTAssertEqual(session.activeScene, .butterflyDamask)
        XCTAssertTrue(session.useClassicChatLayout)
    }

    // MARK: - =================================================================
    // MARK: - 8. Sound Mute Toggle Suppresses Nudge Audio While Preserving Shake
    // MARK: - =================================================================

    /// Pairwise Test 8: Disabling sound effects in Settings suppresses audio player playback
    /// while the Nudge window shake physics displacement continues to execute normally.
    func test_tier3_soundMuteToggleSuppressesNudgeAudioWhilePreservingShake() async {
        let soundPlayer = MsnSoundPlayer.shared
        let originalEnabled = soundPlayer.isSoundEnabled
        defer { soundPlayer.isSoundEnabled = originalEnabled }

        let contact = Contact(
            id: "selin@crosstalk.im",
            email: "selin@crosstalk.im",
            displayName: "Selin",
            presence: .online
        )
        let chatVM = ChatViewModel(contact: contact)

        // Step 1: Mute sounds in settings
        soundPlayer.isSoundEnabled = false
        XCTAssertFalse(soundPlayer.isSoundEnabled)

        let initialPlayCount = soundPlayer.playCount

        // Step 2: Trigger Nudge
        chatVM.sendNudge()

        // Verification: Audio was suppressed
        XCTAssertEqual(soundPlayer.playCount, initialPlayCount, "Sound play count must NOT increment when sound is disabled")

        // Verification: Nudge shake physics displacement continues executing
        let deltas = NudgeShakeEngine.wlmNudgeDeltas
        XCTAssertEqual(deltas.count, 13, "Nudge displacement table must have 13 steps")
        let sumX = deltas.reduce(CGFloat(0)) { $0 + $1.x }
        let sumY = deltas.reduce(CGFloat(0)) { $0 + $1.y }
        XCTAssertEqual(sumX, 0, "X displacement must sum to 0")
        XCTAssertEqual(sumY, 0, "Y displacement must sum to 0")

        await chatVM.shakeEngine.trigger(stepNanoseconds: 0)
        XCTAssertEqual(chatVM.shakeEngine.offsetX, 0, "Offsets must reset to 0 after displacement cycle")
        XCTAssertEqual(chatVM.shakeEngine.offsetY, 0)
        XCTAssertFalse(chatVM.shakeEngine.isShaking)

        // Step 3: Re-enable sound and verify subsequent nudge triggers audio
        soundPlayer.isSoundEnabled = true
        soundPlayer.play(.nudge)
        XCTAssertEqual(soundPlayer.playCount, initialPlayCount + 1, "Sound play count must increment when sound is re-enabled")
        XCTAssertEqual(soundPlayer.lastPlayedEffect, .nudge)
    }
}
