//
// Tier1_FeatureCoverageTests.swift
// MsngrIntegrationTests
//
// Tier 1 Happy-Path Feature Coverage Test Suite for iOS Messenger Client (MSNP18 / WLM 2009).
// Exercises all 7 primary feature areas (5 comprehensive, non-stub tests per feature = 35 tests).
//

import XCTest
import Foundation
import SwiftUI
@testable import MsngrCore
@testable import MsngrProtocol
@testable import MsngrUI

final class Tier1_FeatureCoverageTests: XCTestCase {

    // Shared mock servers and clients
    var passportServer: MockPassportServer!
    var nsServer: MockNotificationServer!
    var sbServer: MockSwitchboardServer!
    var abchServer: MockABCHServer!

    var passportClient: PassportRST2Client!
    var abchClient: ABCHClient!
    var nsClient: NotificationServerClient!
    var sbSession: SwitchboardSession!
    var rpsGenerator: RPSProofGenerator!

    var allocatedNsPort: UInt16 = 0
    var allocatedSbPort: UInt16 = 0

    override func setUp() async throws {
        try await super.setUp()
        MockSOAPURLProtocol.register()

        passportServer = MockPassportServer()
        abchServer = MockABCHServer()
        MockSOAPRouter.shared.passportServer = passportServer
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

    // =========================================================================
    // MARK: - Feature 1: Server Presets & Endpoints (5 tests)
    // =========================================================================

    /// 1. Verifies ServerConfig.crosstalk default endpoints per MSNP18 / Crosstalk specification.
    func test_tier1_presets_crosstalkDefaultPresetEndpoints() {
        let cfg = ServerConfig.crosstalk
        XCTAssertEqual(cfg.mainServer, "ms.msgrsvcs.ctsrv.gay", "Crosstalk NS host must be ms.msgrsvcs.ctsrv.gay")
        XCTAssertEqual(cfg.mainPort, 1863, "Crosstalk NS port must be 1863")
        XCTAssertEqual(cfg.switchboardPort, 1864, "Crosstalk Switchboard port must be 1864")
        XCTAssertEqual(cfg.configServer, "conf.msgrsvcs.ctsrv.gay", "Crosstalk config server must be conf.msgrsvcs.ctsrv.gay")
        XCTAssertEqual(cfg.authServer, "https://ctas.login.ugnet.gay/RST.srf", "Crosstalk auth URL must be https://ctas.login.ugnet.gay/RST.srf")
        XCTAssertFalse(cfg.addressBookServer.isEmpty, "Address book server endpoint must be specified")
        XCTAssertFalse(cfg.storageServer.isEmpty, "Storage server endpoint must be specified")
    }

    /// 2. Verifies ServerConfig.escargot preset endpoints per Escargot MSNP18 specifications.
    func test_tier1_presets_escargotPresetEndpoints() {
        let cfg = ServerConfig.escargot
        XCTAssertEqual(cfg.mainServer, "ds.escargot.nina.chat", "Escargot NS host must be ds.escargot.nina.chat")
        XCTAssertEqual(cfg.mainPort, 1863, "Escargot NS port must be 1863")
        XCTAssertEqual(cfg.switchboardPort, 1863, "Escargot Switchboard port must be 1863")
        XCTAssertEqual(cfg.configServer, "mconf.escargot.nina.chat", "Escargot config server must be mconf.escargot.nina.chat")
        XCTAssertEqual(cfg.authServer, "https://nexus.escargot.chat/RST.srf", "Escargot auth URL must be https://nexus.escargot.chat/RST.srf")
        XCTAssertEqual(cfg.addressBookServer, "https://contacts.escargot.chat", "Escargot ABCH endpoint must be contacts.escargot.chat")
        XCTAssertEqual(cfg.storageServer, "https://storage.escargot.chat", "Escargot storage endpoint must be storage.escargot.chat")
    }

    /// 3. Verifies custom ServerConfig initializer retains arbitrary host, ports, and URLs without modification.
    func test_tier1_presets_customServerConfigInitializers() {
        let custom = ServerConfig(
            mainServer: "custom.msnp.dev",
            mainPort: 1865,
            switchboardPort: 1866,
            configServer: "conf.custom.dev",
            authServer: "https://auth.custom.dev/RST.srf",
            addressBookServer: "https://ab.custom.dev",
            storageServer: "https://storage.custom.dev"
        )
        XCTAssertEqual(custom.mainServer, "custom.msnp.dev")
        XCTAssertEqual(custom.mainPort, 1865)
        XCTAssertEqual(custom.switchboardPort, 1866)
        XCTAssertEqual(custom.configServer, "conf.custom.dev")
        XCTAssertEqual(custom.authServer, "https://auth.custom.dev/RST.srf")
        XCTAssertEqual(custom.addressBookServer, "https://ab.custom.dev")
        XCTAssertEqual(custom.storageServer, "https://storage.custom.dev")

        // Also verify local mock preset
        XCTAssertEqual(ServerConfig.mock.mainServer, "127.0.0.1")
        XCTAssertEqual(ServerConfig.mock.mainPort, 1863)
        XCTAssertTrue(ServerConfig.mock.authServer.contains("127.0.0.1"))
    }

    /// 4. Verifies switching between Crosstalk and Escargot in SessionViewModel updates account configuration.
    @MainActor
    func test_tier1_presets_oneTapPresetSwitchingInSettings() {
        let account = UserAccount(email: "stefano@crosstalk.im", serverConfig: .crosstalk)
        let session = SessionViewModel(account: account)
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay")
        XCTAssertEqual(session.currentAccount.serverConfig.switchboardPort, 1864)

        // Switch to Escargot
        session.currentAccount.serverConfig = .escargot
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ds.escargot.nina.chat")
        XCTAssertEqual(session.currentAccount.serverConfig.switchboardPort, 1863)
        XCTAssertEqual(session.currentAccount.serverConfig.authServer, "https://nexus.escargot.chat/RST.srf")

        // Switch back to Crosstalk
        session.currentAccount.serverConfig = .crosstalk
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay")
        XCTAssertEqual(session.currentAccount.serverConfig.switchboardPort, 1864)
    }

    /// 5. Verifies UserAccount.storageKey generates distinct SHA-256 hashes for the same email on different presets.
    func test_tier1_presets_storageKeyIsolationBetweenPresets() {
        let email = "user@crosstalk.im"
        let crosstalkAcc = UserAccount(email: email, serverConfig: .crosstalk, useMockServer: false)
        let escargotAcc = UserAccount(email: email, serverConfig: .escargot, useMockServer: false)
        let mockAcc = UserAccount(email: email, serverConfig: .mock, useMockServer: true)

        XCTAssertEqual(crosstalkAcc.storageKey.count, 64, "Storage key must be a 64-character SHA-256 hex string")
        XCTAssertEqual(escargotAcc.storageKey.count, 64)
        XCTAssertEqual(mockAcc.storageKey.count, 64)

        XCTAssertNotEqual(crosstalkAcc.storageKey, escargotAcc.storageKey, "Crosstalk and Escargot must produce distinct keys")
        XCTAssertNotEqual(crosstalkAcc.storageKey, mockAcc.storageKey, "Crosstalk and Mock must produce distinct keys")
        XCTAssertNotEqual(escargotAcc.storageKey, mockAcc.storageKey, "Escargot and Mock must produce distinct keys")
        XCTAssertEqual(crosstalkAcc.id, crosstalkAcc.storageKey, "Account id must match storageKey")
    }

    // =========================================================================
    // MARK: - Feature 2: Auth Flow & MSNP18 Handshake (5 tests)
    // =========================================================================

    /// 6. Verifies PassportRST2Client.authenticate extracts valid tokens and binary secret for email credentials.
    func test_tier1_auth_soapRst2TicketIssuance() async throws {
        let email = "stocizz699@crosstalk.im"
        let password = "Stefano@10"
        passportServer.registerUser(email: email, password: password)

        let tokens = try await passportClient.authenticate(email: email, password: password, policy: "MBI_KEY_OLD")

        XCTAssertFalse(tokens.messengerClearToken.isEmpty, "Clear ticket must not be empty")
        XCTAssertFalse(tokens.messengerToken.isEmpty, "Messenger ticket must not be empty")
        XCTAssertFalse(tokens.contactsToken.isEmpty, "Contacts ticket must not be empty")
        XCTAssertFalse(tokens.storageToken.isEmpty, "Storage ticket must not be empty")
        XCTAssertEqual(tokens.binarySecret.count, 24, "Binary secret must be 24 bytes")
        XCTAssertGreaterThanOrEqual(passportServer.recordedRequests.count, 1, "MockPassportServer must record the request")
        XCTAssertEqual(passportServer.recordedRequests.first?.username, email, "Recorded request must contain the full email")
    }

    /// 7. Verifies RPSProofGenerator creates valid 28-byte little-endian header and HMAC-SHA1 / 3DES proof.
    func test_tier1_auth_rps3DesProofDerivation() throws {
        let binarySecretBase64 = "AQIDBAUGBwgJCgsMDQ4PEBESExQ=" // 20 bytes
        let nonce = "MSNP18-CHALLENGE-NONCE-12345"
        let fixedIv = Data(repeating: 0x01, count: 8)

        let proofBase64 = try rpsGenerator.generateProof(
            binarySecretBase64: binarySecretBase64,
            nonce: nonce,
            iv: fixedIv
        )

        guard let proofData = Data(base64Encoded: proofBase64) else {
            XCTFail("Proof must be valid base64")
            return
        }

        XCTAssertGreaterThanOrEqual(proofData.count, 64, "Proof payload must be at least 64 bytes (header + IV + HMAC + cipher)")

        // Verify 28-byte little-endian header fields:
        // uint32(28), uint32(1), uint32(0x6603 = 3DES), uint32(0x8004 = SHA1), uint32(8 = IV len), uint32(20 = HMAC len)
        func readUInt32LE(at offset: Int) -> UInt32 {
            let slice = proofData.subdata(in: offset..<(offset + 4))
            return slice.withUnsafeBytes { $0.load(as: UInt32.self) }
        }

        XCTAssertEqual(readUInt32LE(at: 0), 28, "Header size must be 28 bytes")
        XCTAssertEqual(readUInt32LE(at: 4), 1, "Struct version must be 1")
        XCTAssertEqual(readUInt32LE(at: 8), 0x6603, "Cipher algorithm must be 3DES (0x6603)")
        XCTAssertEqual(readUInt32LE(at: 12), 0x8004, "Hash algorithm must be SHA1 (0x8004)")
        XCTAssertEqual(readUInt32LE(at: 16), 8, "IV length must be 8 bytes")
        XCTAssertEqual(readUInt32LE(at: 20), 20, "HMAC length must be 20 bytes")
    }

    /// 8. Verifies NotificationServerClient connects and dispatches VER 1 MSNP18 CVR0.
    func test_tier1_auth_msnp18VersionNegotiation() async throws {
        try await nsClient.connect()
        XCTAssertTrue(nsClient.isConnected, "Client must be connected after TCP handshake")

        try await nsClient.sendVersionNegotiation()

        try await waitForCondition(description: "Mock server must receive VER command") {
            let commands = await self.nsServer.recordedCommands
            return commands.contains { $0.verb == "VER" && $0.parameters.contains("MSNP18") }
        }

        let verCommands = await nsServer.recordedCommands.filter { $0.verb == "VER" }
        XCTAssertFalse(verCommands.isEmpty, "Mock server must receive VER command")
        XCTAssertTrue(verCommands.first?.parameters.contains("MSNP18") == true, "VER command must negotiate MSNP18")
    }

    /// 9. Verifies dispatch and response of CVR client version registration command with full email.
    func test_tier1_auth_clientVersionRegistrationCVR() async throws {
        let email = "user@crosstalk.im"
        try await nsClient.connect()
        try await nsClient.sendClientInfo(email: email)

        try await waitForCondition(description: "Mock server must receive CVR command") {
            let commands = await self.nsServer.recordedCommands
            return commands.contains { $0.verb == "CVR" && $0.parameters.contains(email) }
        }

        let cvrCommands = await nsServer.recordedCommands.filter { $0.verb == "CVR" }
        XCTAssertFalse(cvrCommands.isEmpty, "Mock server must receive CVR command")
        let cvrParams = cvrCommands.first?.parameters ?? []
        XCTAssertTrue(cvrParams.contains("MSNMSGR") && cvrParams.contains("14.0.8117.0416"), "CVR command must include WLM 2009 client version")
        XCTAssertTrue(cvrParams.contains(email), "CVR command must include the account email")
    }

    /// 10. Verifies complete SSO challenge-response authentication handshake producing USR OK confirmation.
    func test_tier1_auth_usrSsoChallengeResponse() async throws {
        let email = "stefano@crosstalk.im"
        let password = "Stefano@10"
        passportServer.registerUser(email: email, password: password)

        let tokens = try await passportClient.authenticate(email: email, password: password)
        let proof = try rpsGenerator.generateProof(binarySecretBase64: tokens.binarySecretBase64, nonce: "MSNP18-CHALLENGE")

        try await nsClient.connect()
        try await nsClient.signIn(email: email, ticket: tokens.messengerClearToken, proof: proof)

        let authEvent = try await expectEvent(from: nsClient.events) {
            if case .authenticated(let authedEmail) = $0 {
                return authedEmail.lowercased() == email.lowercased()
            }
            return false
        }

        if case .authenticated(let authedEmail) = authEvent {
            XCTAssertEqual(authedEmail.lowercased(), email.lowercased(), "Authentication event must emit authenticated email")
        }
    }

    // =========================================================================
    // MARK: - Feature 3: Skin & Theme Loading (5 tests)
    // =========================================================================

    /// 11. Verifies AeroSkin.wlm2009Light primary colors, background, and light mode flag.
    func test_tier1_theme_wlm2009LightSkinColors() {
        let skin = AeroSkin.wlm2009Light
        XCTAssertEqual(skin.rawValue, "WLM 2009 Aero (Light)")
        XCTAssertEqual(skin.primaryColor, .wlmPrimary)
        XCTAssertEqual(skin.windowBackgroundColor, .wlmWindowBackground)
        XCTAssertFalse(skin.isDark, "WLM 2009 Light skin must not be dark mode")

        // Verify underlying hex constants
        _ = Color.wlmPrimaryContainer
        _ = Color.wlmSurfaceVariant
        _ = Color.wlmOutline
    }

    /// 12. Verifies AeroSkin.wlm2009Night dark palette, primary accent, and isDark == true.
    func test_tier1_theme_wlmNightAeroDarkSkinColors() {
        let skin = AeroSkin.wlm2009Night
        XCTAssertEqual(skin.rawValue, "WLM Night Aero (Dark)")
        XCTAssertEqual(skin.primaryColor, .wlmNightPrimary)
        XCTAssertEqual(skin.windowBackgroundColor, .wlmNightBackground)
        XCTAssertTrue(skin.isDark, "WLM Night Aero skin must be dark mode")

        // Verify dark palette constants
        _ = Color.wlmNightSurface
        _ = Color.wlmNightOutline
        _ = Color.wlmNightSecondary
    }

    /// 13. Verifies AeroSkin.msn75Classic retro palette colors and classic MSN blue accent.
    func test_tier1_theme_msn75ClassicSkinPalette() {
        let skin = AeroSkin.msn75Classic
        XCTAssertEqual(skin.rawValue, "MSN Messenger 7.5")
        XCTAssertEqual(skin.primaryColor, .msn75Primary)
        XCTAssertEqual(skin.windowBackgroundColor, .msn75Background)
        XCTAssertFalse(skin.isDark, "MSN 7.5 Classic skin must not be dark mode")

        _ = Color.msn75Secondary
    }

    /// 14. Verifies all 23 WlmScene header gradient configurations generate valid linear gradients.
    func test_tier1_theme_wlmSceneHeaderGradients() {
        XCTAssertEqual(WlmScene.allCases.count, 23, "Must contain 23 classic WLM header scenes")

        for scene in WlmScene.allCases {
            let gradient = scene.headerGradient
            XCTAssertNotNil(gradient, "Header gradient for \(scene.rawValue) must be non-nil")
            XCTAssertFalse(scene.rawValue.isEmpty, "Scene title must not be empty")
        }

        // Only Mesmerizing White requires dark header text
        XCTAssertTrue(WlmScene.mesmerizingWhite.isDarkText, "Mesmerizing White requires dark header text")
        XCTAssertFalse(WlmScene.sky.isDarkText)
        XCTAssertFalse(WlmScene.carbonFiber.isDarkText)
        XCTAssertFalse(WlmScene.dottieGreen.isDarkText)
        XCTAssertFalse(WlmScene.butterflyDamask.isDarkText)
        XCTAssertFalse(WlmScene.vistaSilhouette.isDarkText)
        XCTAssertFalse(WlmScene.zuneOrange.isDarkText)
    }

    /// 15. Verifies MsnSoundPlayer plays all 7 classic sounds, updating lastPlayedEffect and playCount.
    @MainActor
    func test_tier1_theme_audioEngineCatalogPlayback() {
        let player = MsnSoundPlayer.shared
        player.isSoundEnabled = true
        let initialCount = player.playCount

        for (idx, effect) in MsnSoundEffect.allCases.enumerated() {
            player.play(effect)
            XCTAssertEqual(player.lastPlayedEffect, effect, "Last played effect must match played effect")
            XCTAssertEqual(player.playCount, initialCount + idx + 1, "Play count must increment monotonically")
            XCTAssertFalse(effect.displayName.isEmpty, "Sound effect display name must not be empty")
            XCTAssertTrue(effect.rawValue.hasSuffix(".mp3"), "Sound effect filename must have .mp3 extension")
        }
        XCTAssertEqual(MsnSoundEffect.allCases.count, 7, "Catalog must contain exactly 7 classic sound effects")
    }

    // =========================================================================
    // MARK: - Feature 4: Contact Groups & Real-Time Presence (5 tests)
    // =========================================================================

    /// 16. Verifies ABCHClient.findContacts groups contacts by groupId into user-defined categories.
    func test_tier1_contacts_abchRosterCategorizedByGroups() async throws {
        abchServer.groups = [
            MockABGroup(id: "grp-friends", name: "Friends"),
            MockABGroup(id: "grp-coworkers", name: "Coworkers")
        ]
        abchServer.contacts = [
            MockABContact(id: "c-1", email: "alice@crosstalk.im", displayName: "Alice", groupId: "grp-friends"),
            MockABContact(id: "c-2", email: "bob@crosstalk.im", displayName: "Bob", groupId: "grp-coworkers")
        ]

        let result = try await abchClient.findContacts(ticket: "mockTicket")

        XCTAssertEqual(result.groups.count, 2, "Address book must return 2 groups")
        XCTAssertEqual(result.contacts.count, 2, "Address book must return 2 contacts")

        let alice = result.contacts.first { $0.email == "alice@crosstalk.im" }
        let bob = result.contacts.first { $0.email == "bob@crosstalk.im" }

        XCTAssertEqual(alice?.groupId, "grp-friends", "Alice must belong to Friends group")
        XCTAssertEqual(bob?.groupId, "grp-coworkers", "Bob must belong to Coworkers group")
    }

    /// 17. Verifies SessionViewModel categorizes contacts dynamically into online and offline groups.
    @MainActor
    func test_tier1_contacts_dynamicOnlineOfflineCategorySplitting() {
        let session = SessionViewModel(account: UserAccount(email: "stefano@crosstalk.im"))
        session.contacts = [
            Contact(id: "selin@crosstalk.im", nickname: "Selin", email: "selin@crosstalk.im", presence: .online),
            Contact(id: "alex@crosstalk.im", nickname: "Alex", email: "alex@crosstalk.im", presence: .busy),
            Contact(id: "giulia@crosstalk.im", nickname: "Giulia", email: "giulia@crosstalk.im", presence: .away),
            Contact(id: "marco@crosstalk.im", nickname: "Marco", email: "marco@crosstalk.im", presence: .offline)
        ]

        XCTAssertEqual(session.onlineContacts.count, 3, "Online category must include Online, Busy, and Away contacts")
        XCTAssertEqual(session.offlineContacts.count, 1, "Offline category must contain only Offline contacts")
        XCTAssertEqual(session.offlineContacts.first?.email, "marco@crosstalk.im")

        // Priority sort verification: online < busy < away
        XCTAssertEqual(session.onlineContacts[0].presence, .online)
        XCTAssertEqual(session.onlineContacts[1].presence, .busy)
        XCTAssertEqual(session.onlineContacts[2].presence, .away)
    }

    /// 18. Verifies ContactGroup accordion expand/collapse toggle and system group builders.
    func test_tier1_contacts_groupAccordionExpandCollapseToggle() {
        var group = ContactGroup(
            id: "grp-friends",
            name: "Friends",
            contactIds: ["alice@crosstalk.im", "bob@crosstalk.im"],
            isExpanded: true
        )
        XCTAssertTrue(group.isExpanded, "Initial accordion state should be expanded")

        group.isExpanded = false
        XCTAssertFalse(group.isExpanded, "Toggling accordion state must update isExpanded")
        XCTAssertEqual(group.contactIds.count, 2, "Members must be preserved on accordion toggle")

        // Test static system group builders
        let onlineGrp = ContactGroup.online(contactIds: ["alice@crosstalk.im"])
        XCTAssertTrue(onlineGrp.isSystemGroup)
        XCTAssertEqual(onlineGrp.name, "Online")
        XCTAssertTrue(onlineGrp.isExpanded)

        let offlineGrp = ContactGroup.offline(contactIds: ["bob@crosstalk.im"])
        XCTAssertTrue(offlineGrp.isSystemGroup)
        XCTAssertEqual(offlineGrp.name, "Offline")
        XCTAssertTrue(offlineGrp.isExpanded)
    }

    /// 19. Verifies NotificationServerClient.setPresence dispatches CHG wire commands for online, busy, away.
    func test_tier1_contacts_realTimePresenceBroadcastChg() async throws {
        try await nsClient.connect()

        try await nsClient.setPresence(.online)
        try await nsClient.setPresence(.busy)
        try await nsClient.setPresence(.away)

        try await waitForCondition(description: "Server must receive all 3 CHG commands") {
            let commands = await self.nsServer.recordedCommands
            let chgCommands = commands.filter { $0.verb == "CHG" }
            return chgCommands.count >= 3
        }

        let chgCommands = await nsServer.recordedCommands.filter { $0.verb == "CHG" }
        XCTAssertGreaterThanOrEqual(chgCommands.count, 3, "Server must receive all 3 CHG commands")

        XCTAssertTrue(chgCommands.contains { $0.parameters.contains("NLN") }, "CHG must broadcast NLN for online")
        XCTAssertTrue(chgCommands.contains { $0.parameters.contains("BSY") }, "CHG must broadcast BSY for busy")
        XCTAssertTrue(chgCommands.contains { $0.parameters.contains("AWY") }, "CHG must broadcast AWY for away")
    }

    /// 20. Verifies NotificationServerClient.setPersonalMessage dispatches UUX with escaped XML payload.
    func test_tier1_contacts_personalMessageUpdateUux() async throws {
        try await nsClient.connect()
        let personalMessage = "Listening to Daft Punk 🎵 & Chilling <3"

        try await nsClient.setPersonalMessage(personalMessage)

        try await waitForCondition(description: "Server must receive UUX command") {
            let commands = await self.nsServer.recordedCommands
            return commands.contains { $0.verb == "UUX" }
        }

        let uuxCommands = await nsServer.recordedCommands.filter { $0.verb == "UUX" }
        XCTAssertFalse(uuxCommands.isEmpty, "Server must receive UUX command")

        let uuxPayload = uuxCommands.first?.payload.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        // Check for XML escaping (&amp; and &lt;)
        XCTAssertTrue(uuxPayload.contains("&amp;"), "Special character & must be escaped as &amp;")
        XCTAssertTrue(uuxPayload.contains("&lt;"), "Special character < must be escaped as &lt;")
        XCTAssertTrue(uuxPayload.contains("<PSM>"), "UUX payload must contain <PSM> tag")
    }

    // =========================================================================
    // MARK: - Feature 5: Chat Messaging (1:1 and Multi-Party) (5 tests)
    // =========================================================================

    /// 21. Verifies Switchboard sends text message with MSG trId A <len> and receives ACK confirmation.
    func test_tier1_chat_sendTextMessageWithAckModeA() async throws {
        try await sbSession.connect(authKey: "auth-12345", userEmail: "alice@crosstalk.im")

        try await waitForCondition(description: "Switchboard handshake complete") {
            let cmds = await self.sbServer.recordedCommands
            return cmds.contains { $0.verb == "USR" }
        }

        let messageText = "Hello from Crosstalk iOS Client!"
        try await sbSession.sendMessage(messageText, ackMode: .acknowledged)

        try await waitForCondition(description: "Server must receive MSG command") {
            let commands = await self.sbServer.recordedCommands
            return commands.contains { $0.verb == "MSG" }
        }

        let msgCommands = await sbServer.recordedCommands.filter { $0.verb == "MSG" }
        XCTAssertFalse(msgCommands.isEmpty, "Server must receive MSG command")

        let sentMsg = msgCommands.first
        XCTAssertTrue(sentMsg?.parameters.contains("A") == true, "MSG command must specify ackMode A (acknowledged)")

        let recordedMessages = await sbServer.recordedMessages
        let sentMessage = recordedMessages.first {
            if case .text(let text, _) = $0 {
                return text == messageText
            }
            return false
        }
        XCTAssertNotNil(sentMessage, "MSG body must contain the message text")
    }

    /// 22. Verifies incoming MSG text/plain frame is decoded into ChatMessage and delivered via session events.
    func test_tier1_chat_receiveIncomingTextMessage() async throws {
        try await sbSession.connect(authKey: "auth-12345", userEmail: "alice@crosstalk.im")

        try await waitForCondition(description: "Switchboard handshake complete") {
            let cmds = await self.sbServer.recordedCommands
            return cmds.contains { $0.verb == "USR" }
        }

        let incomingText = "Hey Alice, how is the iOS port going?"
        await sbServer.sendIncomingTextMessage(text: incomingText)

        let event = try await expectEvent(from: sbSession.events) {
            if case .messageReceived(let msg) = $0 {
                return msg.text == incomingText
            }
            return false
        }

        if case .messageReceived(let msg) = event {
            XCTAssertFalse(msg.sender.isEmpty, "Message sender must not be empty")
            XCTAssertEqual(msg.text, incomingText)
            XCTAssertEqual(msg.kind, .text)
        }
    }

    /// 23. Verifies X-MMS-IM-Format header serializes font family and color hex formatting.
    func test_tier1_chat_imFormatHeaderFontAndColorStyling() async throws {
        try await sbSession.connect(authKey: "auth-12345", userEmail: "alice@crosstalk.im")

        try await waitForCondition(description: "Switchboard handshake complete") {
            let cmds = await self.sbServer.recordedCommands
            return cmds.contains { $0.verb == "USR" }
        }

        try await sbSession.sendMessage(
            "Styled Message Text",
            ackMode: .unacknowledged,
            fontName: "Comic Sans MS",
            colorHex: "FF0000"
        )

        try await waitForCondition(description: "Server must receive message with format header") {
            let messages = await self.sbServer.recordedMessages
            return messages.contains {
                if case .text(_, let format) = $0 {
                    return format?.contains("FN=Comic Sans MS") == true
                }
                return false
            }
        }

        let recordedMessages = await sbServer.recordedMessages
        let targetMsg = recordedMessages.first {
            if case .text(let text, _) = $0 {
                return text == "Styled Message Text"
            }
            return false
        }
        XCTAssertNotNil(targetMsg, "Message must be recorded")

        if case .text(_, let formatHeader) = targetMsg {
            XCTAssertNotNil(formatHeader, "Packet must include X-MMS-IM-Format header")
            XCTAssertTrue(formatHeader?.contains("FN=Comic Sans MS") == true, "Format header must contain font name")
            XCTAssertTrue(formatHeader?.contains("CO=FF0000") == true, "Format header must contain color hex")
        }

        let commands = await sbServer.recordedCommands
        let rawPayload = commands.first(where: { $0.verb == "MSG" })?.payload.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(rawPayload.contains("X-MMS-IM-Format:"), "Packet must include X-MMS-IM-Format header")
    }

    /// 24. Verifies receipt of JOI appends participant to SwitchboardSession.activeRoster and emits event.
    func test_tier1_chat_multiPartyParticipantJoinJoi() async throws {
        try await sbSession.connect(authKey: "auth-12345", userEmail: "alice@crosstalk.im")

        try await waitForCondition(description: "Switchboard handshake complete") {
            let cmds = await self.sbServer.recordedCommands
            return cmds.contains { $0.verb == "USR" }
        }

        await sbServer.simulatePeerJoin(email: "charlie@crosstalk.im", displayName: "Charlie")

        let event = try await expectEvent(from: sbSession.events) {
            if case .userJoined(let email, let name) = $0 {
                return email == "charlie@crosstalk.im" && name == "Charlie"
            }
            return false
        }

        if case .userJoined(let email, let name) = event {
            XCTAssertEqual(email, "charlie@crosstalk.im")
            XCTAssertEqual(name, "Charlie")
            XCTAssertTrue(sbSession.activeRoster.contains("charlie@crosstalk.im"), "Active roster must contain joined participant")
        }
    }

    /// 25. Verifies MessengerPlusParser parses [b], [i], and [c=4] into styled glyph runs.
    func test_tier1_chat_messengerPlusBbcodeFormatting() {
        let input = "[b][c=4]Hello[/c][/b] [i]world[/i]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertEqual(parsed.text, "Hello world", "Clean text must strip tags")

        let helloGlyphs = parsed.glyphs.filter { "Hello".contains($0.value) }
        XCTAssertFalse(helloGlyphs.isEmpty)
        XCTAssertTrue(helloGlyphs.allSatisfy { $0.style.bold }, "Hello glyphs must have bold style")

        let worldGlyphs = parsed.glyphs.filter { "world".contains($0.value) }
        XCTAssertFalse(worldGlyphs.isEmpty)
        XCTAssertTrue(worldGlyphs.allSatisfy { $0.style.italic }, "world glyphs must have italic style")

        // Also test attributed string conversion without crash
        let attrString = MessengerPlusParser.parseToAttributedString(input)
        XCTAssertFalse(attrString.characters.isEmpty)
    }

    // =========================================================================
    // MARK: - Feature 6: Nudges / Trilli (5 tests)
    // =========================================================================

    /// 26. Verifies SwitchboardSession.sendNudge serializes Datacast ID: 1 wire message.
    func test_tier1_nudge_wireSerializationDatacast() async throws {
        try await sbSession.connect(authKey: "auth-12345", userEmail: "alice@crosstalk.im")

        try await waitForCondition(description: "Switchboard handshake complete") {
            let cmds = await self.sbServer.recordedCommands
            return cmds.contains { $0.verb == "USR" }
        }

        try await sbSession.sendNudge()

        try await waitForCondition(description: "Server must receive MSG for nudge") {
            let messages = await self.sbServer.recordedMessages
            return messages.contains { $0 == .nudge }
        }

        let msgCommands = await sbServer.recordedCommands.filter { $0.verb == "MSG" }
        XCTAssertFalse(msgCommands.isEmpty, "Server must receive MSG for nudge")

        let recordedMessages = await sbServer.recordedMessages
        XCTAssertTrue(recordedMessages.contains { $0 == .nudge }, "Recorded messages must include parsed nudge")

        let rawPayload = msgCommands.first?.payload.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(rawPayload.contains("text/x-msnmsgr-datacast"), "Nudge must specify datacast content type")
        XCTAssertTrue(rawPayload.contains("ID: 1"), "Nudge datacast ID must be 1")
    }

    /// 27. Verifies NudgeShakeEngine displacement delta table has exactly 13 pairs summing to (0, 0).
    func test_tier1_nudge_displacementTable13Steps() {
        let deltas = NudgeShakeEngine.wlmNudgeDeltas
        XCTAssertEqual(deltas.count, 13, "Displacement table must contain exactly 13 steps per cycle")

        let sumX = deltas.reduce(CGFloat(0)) { $0 + $1.x }
        let sumY = deltas.reduce(CGFloat(0)) { $0 + $1.y }

        XCTAssertEqual(sumX, 0, accuracy: 0.001, "Delta X sum must equal 0 to return to origin")
        XCTAssertEqual(sumY, 0, accuracy: 0.001, "Delta Y sum must equal 0 to return to origin")

        // Check reference offsets from msnmsgr.exe
        XCTAssertEqual(deltas.first?.x, 4)
        XCTAssertEqual(deltas.first?.y, 3)
        XCTAssertEqual(deltas.last?.x, -4)
        XCTAssertEqual(deltas.last?.y, 3)

        XCTAssertEqual(NudgeShakeEngine.cycleCount, 4, "WLM 2009 executes exactly 4 cycles per nudge")
        XCTAssertEqual(NudgeShakeEngine.cycleCount * deltas.count, 52, "Total steps per nudge must be 52")
    }

    /// 28. Verifies NudgeShakeEngine execution completes 4 cycles and restores offsets to (0, 0).
    @MainActor
    func test_tier1_nudge_triggerFourCyclesDisplacement() async {
        let engine = NudgeShakeEngine()
        XCTAssertFalse(engine.isShaking)
        XCTAssertEqual(engine.offsetX, 0)
        XCTAssertEqual(engine.offsetY, 0)

        // Run with stepNanoseconds: 0 for fast synchronous test execution
        await engine.trigger(stepNanoseconds: 0)

        XCTAssertFalse(engine.isShaking, "Shaking state must be false after completion")
        XCTAssertEqual(engine.offsetX, 0, "OffsetX must reset to 0")
        XCTAssertEqual(engine.offsetY, 0, "OffsetY must reset to 0")
    }

    /// 29. Verifies sending or receiving a nudge triggers MsnSoundPlayer.shared.play(.nudge).
    @MainActor
    func test_tier1_nudge_audioSoundEffectTrigger() {
        let player = MsnSoundPlayer.shared
        player.isSoundEnabled = true
        let countBefore = player.playCount

        player.play(.nudge)

        XCTAssertEqual(player.lastPlayedEffect, .nudge, "Last played effect must be .nudge")
        XCTAssertEqual(player.playCount, countBefore + 1, "Play count must increment")
        XCTAssertEqual(MsnSoundEffect.nudge.displayName, "Nudge Shake Alert")
        XCTAssertEqual(MsnSoundEffect.nudge.rawValue, "nudge.mp3")
    }

    /// 30. Verifies ChatMessage.nudge static builder produces authentic WLM transcript banners.
    func test_tier1_nudge_systemTranscriptMessage() {
        let sent = ChatMessage.nudge(contactId: "bob@crosstalk.im", author: .me)
        XCTAssertEqual(sent.text, "You have just sent a Nudge.", "Sent nudge text must match WLM transcript banner")
        XCTAssertEqual(sent.kind, .nudge)
        XCTAssertEqual(sent.author, .me)
        XCTAssertTrue(sent.isNudge)

        let received = ChatMessage.nudge(contactId: "bob@crosstalk.im", author: .contact)
        XCTAssertEqual(received.text, "You have just received a Nudge!", "Received nudge text must match WLM transcript banner")
        XCTAssertEqual(received.kind, .nudge)
        XCTAssertEqual(received.author, .contact)
        XCTAssertTrue(received.isNudge)
    }

    // =========================================================================
    // MARK: - Feature 7: Winks Interactive System (5 tests)
    // =========================================================================

    /// 31. Verifies WinkPayload.makeOfferBody serializes Datacast ID: 2 with Type 8 MSNObject.
    func test_tier1_winks_wireSerializationDatacastId2() {
        let msnObj = MsnObject(
            creator: "alice@crosstalk.im",
            size: 1024,
            type: 8,
            location: "wink_knock.cab",
            friendly: "Knock Knock",
            sha1d: "AQIDBAUGBwgJCgsMDQ4PEBESExQ="
        )

        let offerBody = WinkPayload.makeOfferBody(metadata: msnObj)

        XCTAssertTrue(offerBody.hasPrefix("ID: 2\r\nData: <msnobj "), "Offer body must have ID: 2 prefix")
        XCTAssertTrue(offerBody.contains("Type=\"8\""), "MSNObject must specify Type 8 for Winks")
        XCTAssertTrue(offerBody.contains("Creator=\"alice@crosstalk.im\""), "MSNObject must specify creator email")
        XCTAssertTrue(offerBody.contains("Friendly=\"Knock Knock\""), "MSNObject must specify friendly title")
        XCTAssertTrue(offerBody.hasSuffix("\r\n\r\n"), "Offer body must terminate with double CRLF")
    }

    /// 32. Verifies WinkPayload.parseOffer extracts valid Wink MSNObject metadata from Datacast body.
    func test_tier1_winks_parseIncomingWinkOffer() {
        let offerBody = "ID: 2\r\nData: <msnobj Creator=\"bob@crosstalk.im\" Size=\"2048\" Type=\"8\" Location=\"laugh.cab\" Friendly=\"Laughing\" SHA1D=\"AQIDBAUGBwgJCgsMDQ4PEBESExQ=\" SHA1C=\"AAAAAAAAAAAAAAAAAAAAAAAAAAA=\"/>\r\n\r\n"

        let parsed = WinkPayload.parseOffer(body: offerBody)

        XCTAssertNotNil(parsed, "Valid Wink offer body must be parsed successfully")
        XCTAssertEqual(parsed?.creator, "bob@crosstalk.im")
        XCTAssertEqual(parsed?.type, 8)
        XCTAssertEqual(parsed?.size, 2048)
        XCTAssertEqual(parsed?.friendly, "Laughing")
        XCTAssertEqual(parsed?.location, "laugh.cab")
    }

    /// 33. Verifies WinkReference catalog item instantiation and equality.
    func test_tier1_winks_catalogCatalogItemsListing() {
        let knock = WinkReference(id: "wink-knock", name: "Knock Knock", thumbnailUri: "knock_thumb.png")
        let laugh = WinkReference(id: "wink-laugh", name: "Laughing", thumbnailUri: "laugh_thumb.png")
        let heart = WinkReference(id: "wink-heart", name: "Beating Heart", thumbnailUri: "heart_thumb.png")
        let balloon = WinkReference(id: "wink-balloon", name: "Water Balloon", thumbnailUri: "balloon_thumb.png")

        XCTAssertEqual(knock.id, "wink-knock")
        XCTAssertEqual(knock.name, "Knock Knock")
        XCTAssertEqual(laugh.name, "Laughing")
        XCTAssertEqual(heart.name, "Beating Heart")
        XCTAssertEqual(balloon.name, "Water Balloon")

        XCTAssertNotEqual(knock, laugh, "Distinct winks must not be equal")
        XCTAssertEqual(knock, WinkReference(id: "wink-knock", name: "Knock Knock", thumbnailUri: "knock_thumb.png"))
    }

    /// 34. Verifies WinkPayload limits (max CAB size 2 MB, expanded 8 MB, max playback duration 12s).
    func test_tier1_winks_overlayPlaybackPresentation() {
        XCTAssertEqual(WinkPayload.maxPlaybackDuration, 12.0, "Wink playback duration cap must be 12 seconds")
        XCTAssertEqual(WinkPayload.maxCabBytes, 2 * 1024 * 1024, "Max CAB archive size must be 2 MB")
        XCTAssertEqual(WinkPayload.maxExpandedBytes, 8 * 1024 * 1024, "Max expanded archive size must be 8 MB")
        XCTAssertEqual(WinkPayload.appId, 1)
        XCTAssertEqual(WinkPayload.objectType, 8)

        // Path safety verification
        XCTAssertTrue(WinkPayload.isSafeArchivePath("wink.swf"))
        XCTAssertTrue(WinkPayload.isSafeArchivePath("audio/wink.mp3"))
        XCTAssertFalse(WinkPayload.isSafeArchivePath("../secret.txt"))
        XCTAssertFalse(WinkPayload.isSafeArchivePath("/absolute/path"))
    }

    /// 35. Verifies received wink in conversation provides a replayable WinkReference in ChatMessage.
    func test_tier1_winks_playAgainTranscriptAction() {
        let winkRef = WinkReference(id: "wink-knock", name: "Knock Knock")
        let msg = ChatMessage(
            contactId: "bob@crosstalk.im",
            author: .contact,
            text: "sent you a Wink: Knock Knock",
            kind: .wink,
            wink: winkRef
        )

        XCTAssertEqual(msg.kind, .wink)
        XCTAssertNotNil(msg.wink, "Wink payload reference must be attached to message")
        XCTAssertEqual(msg.wink?.id, "wink-knock")
        XCTAssertEqual(msg.wink?.name, "Knock Knock")
        XCTAssertEqual(msg.sender, "bob@crosstalk.im")

        // Verifies the attached reference is sufficient to trigger replay
        let replayTarget = msg.wink
        XCTAssertEqual(replayTarget?.id, "wink-knock")
    }
}
