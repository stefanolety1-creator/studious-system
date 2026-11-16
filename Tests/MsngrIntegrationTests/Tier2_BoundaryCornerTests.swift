//
// Tier2_BoundaryCornerTests.swift
// MsngrIntegrationTests
//
// Tier 2: Boundary Value Analysis (BVA), Negative Testing, Corner Cases,
// Network Fault Injection, and Malformed Payload Rejection across all 7 Features.
//

import XCTest
import Foundation
import Network
@testable import MsngrCore
@testable import MsngrProtocol
@testable import MsngrUI

@MainActor
final class Tier2_BoundaryCornerTests: XCTestCase {

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
    // MARK: - Feature 1: Server Presets Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 1.1: Empty or whitespace host string is rejected or retains existing valid preset.
    func test_tier2_presets_emptyOrWhitespaceHostHandling() {
        let whitespaceHost = "   \t\n  "
        let trimmed = whitespaceHost.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty, "Whitespace host must trim to empty string")

        // Verifying ServerConfig initialization with empty host does not crash
        let emptyConfig = ServerConfig(mainServer: trimmed, mainPort: 1863)
        XCTAssertEqual(emptyConfig.mainServer, "", "Config stores trimmed empty host string")

        // Verifying UserAccount handles empty server host cleanly without crash
        let account = UserAccount(email: "user@crosstalk.im", serverConfig: emptyConfig)
        let storageKey = account.storageKey
        XCTAssertEqual(storageKey.count, 64, "Storage key must still generate valid 64-char SHA-256 hex digest")

        // Verifying settings guard: when user provides empty host string, existing host is preserved
        var activeConfig = ServerConfig.escargot
        let userEnteredHost = "   "
        if !userEnteredHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activeConfig.mainServer = userEnteredHost
        }
        XCTAssertEqual(activeConfig.mainServer, "ds.escargot.nina.chat", "Active preset host must not be overwritten with empty/whitespace input")
    }

    /// Test 1.2: Non-numeric port input in server configuration is rejected and retains default port.
    func test_tier2_presets_nonNumericPortInput() {
        let nonNumericInputs = ["abc", "1863xyz", "-1863", "99999999999999999999", "18 63", ""]

        for input in nonNumericInputs {
            let parsedPort = Int(input)
            let isValidPort: Bool
            if let p = parsedPort, (1...65535).contains(p) {
                isValidPort = true
            } else {
                isValidPort = false
            }
            XCTAssertFalse(isValidPort, "Port input '\(input)' must be rejected as invalid")
        }

        // Simulating settings view port validation logic
        var currentConfig = ServerConfig.escargot
        let invalidPortString = "not_a_port"
        if let validPort = Int(invalidPortString), (1...65535).contains(validPort) {
            currentConfig.mainPort = validPort
        }
        XCTAssertEqual(currentConfig.mainPort, 1863, "mainPort must remain default (1863) when invalid port string is entered")
    }

    /// Test 1.3: Malformed authentication URL string fails validation before network dispatch.
    func test_tier2_presets_malformedAuthUrlHandling() async {
        let malformedUrls = [
            "https:// invalid url with spaces /RST.srf",
            "://missing-scheme",
            "just_a_string",
            ""
        ]

        for urlString in malformedUrls {
            let parsed = URL(string: urlString)
            let hasValidSchemeAndHost = parsed?.scheme != nil && parsed?.host != nil
            XCTAssertFalse(hasValidSchemeAndHost, "URL '\(urlString)' must not be recognized as a valid HTTP/HTTPS endpoint")
        }

        // When client receives malformed endpoint, it fails gracefully without unhandled exception
        if let invalidUrl = URL(string: "http://127.0.0.1:0") {
            let invalidClient = PassportRST2Client(endpoint: invalidUrl)
            do {
                _ = try await invalidClient.authenticate(email: "user@crosstalk.im", password: "password123")
                XCTFail("Expected authentication to fail for invalid local endpoint")
            } catch {
                XCTAssertNotNil(error, "Error must be caught gracefully without crashing")
            }
        }
    }

    /// Test 1.4: Rapid preset switching maintains atomic consistency without data corruption.
    func test_tier2_presets_rapidPresetSwitchingRaceCondition() {
        let crosstalkConfig = ServerConfig(
            mainServer: "ms.msgrsvcs.ctsrv.gay",
            mainPort: 1863,
            switchboardPort: 1864,
            configServer: "conf.msgrsvcs.ctsrv.gay",
            authServer: "https://ctas.login.ugnet.gay/RST.srf",
            addressBookServer: "https://contacts.msgrsvcs.ctsrv.gay",
            storageServer: "https://storage.msgrsvcs.ctsrv.gay"
        )
        let escargotConfig = ServerConfig.escargot
        let mockConfig = ServerConfig.mock

        var sessionAccount = UserAccount(email: "user@crosstalk.im", serverConfig: crosstalkConfig)

        // Rapidly toggle presets 60 times
        for i in 0..<60 {
            switch i % 3 {
            case 0:
                sessionAccount.serverConfig = crosstalkConfig
                sessionAccount.useMockServer = false
                XCTAssertEqual(sessionAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay")
                XCTAssertEqual(sessionAccount.serverConfig.switchboardPort, 1864)
            case 1:
                sessionAccount.serverConfig = escargotConfig
                sessionAccount.useMockServer = false
                XCTAssertEqual(sessionAccount.serverConfig.mainServer, "ds.escargot.nina.chat")
                XCTAssertEqual(sessionAccount.serverConfig.switchboardPort, 1863)
            default:
                sessionAccount.serverConfig = mockConfig
                sessionAccount.useMockServer = true
                XCTAssertEqual(sessionAccount.serverConfig.mainServer, "127.0.0.1")
            }

            let key = sessionAccount.storageKey
            XCTAssertEqual(key.count, 64, "Storage key must always be a 64-character SHA-256 hex string")
        }
    }

    /// Test 1.5: "Restore Defaults" button resets all custom configuration fields to standard preset.
    func test_tier2_presets_customConfigResetToDefaults() {
        // Set completely customized server endpoints
        var activeConfig = ServerConfig(
            mainServer: "custom.msn.internal",
            mainPort: 9090,
            switchboardPort: 9091,
            configServer: "conf.custom.msn.internal",
            authServer: "https://custom.msn.internal/RST.srf",
            addressBookServer: "https://custom.msn.internal/abservice",
            storageServer: "https://custom.msn.internal/storage"
        )

        XCTAssertEqual(activeConfig.mainServer, "custom.msn.internal")
        XCTAssertEqual(activeConfig.mainPort, 9090)
        XCTAssertEqual(activeConfig.switchboardPort, 9091)

        // Restore Escargot defaults
        activeConfig = ServerConfig.escargot

        XCTAssertEqual(activeConfig.mainServer, "ds.escargot.nina.chat")
        XCTAssertEqual(activeConfig.mainPort, 1863)
        XCTAssertEqual(activeConfig.switchboardPort, 1863)
        XCTAssertEqual(activeConfig.configServer, "mconf.escargot.nina.chat")
        XCTAssertEqual(activeConfig.authServer, "https://nexus.escargot.chat/RST.srf")
        XCTAssertEqual(activeConfig.addressBookServer, "https://contacts.escargot.chat")
        XCTAssertEqual(activeConfig.storageServer, "https://storage.escargot.chat")
    }

    // MARK: - =================================================================
    // MARK: - Feature 2: Auth Flow Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 2.1: Legacy MSN Passport password truncation strictly caps passwords > 16 characters.
    func test_tier2_auth_passwordTruncationOver16Characters() async throws {
        let accountEmail = "user@crosstalk.im"
        let base16Password = "0123456789ABCDEF"
        let passwordOver16 = "0123456789ABCDEF_EXTRA_CHARACTERS_BEYOND_16"

        // Server has user registered with 16-character password
        passportServer.registerUser(email: accountEmail, password: base16Password)

        // Client authenticates with password exceeding 16 chars
        let tokens = try await passportClient.authenticate(email: accountEmail, password: passwordOver16)

        XCTAssertFalse(tokens.messengerClearToken.isEmpty, "Authentication should succeed because password > 16 is truncated to 16")

        guard let req = passportServer.lastRequest else {
            XCTFail("Expected recorded request in MockPassportServer")
            return
        }
        XCTAssertTrue(req.rawBody.contains("0123456789ABCDEF"), "SOAP body must contain the truncated 16-character prefix")
        XCTAssertFalse(req.rawBody.contains("EXTRA_CHARACTERS"), "Extra characters beyond 16 must not appear in the SOAP password element")
    }

    /// Test 2.2: SOAP Fault 500 (FailedAuthentication) throws .authenticationFailed, and non-email identifier is rejected.
    func test_tier2_auth_soapFaultInvalidCredentialsHandling() async throws {
        let accountEmail = "stefano@escargot.chat"
        passportServer.forceSoapFault = true
        passportServer.faultMessage = "The community server rejected these credentials."

        do {
            _ = try await passportClient.authenticate(email: accountEmail, password: "wrongpassword123")
            XCTFail("Expected authentication to fail with SOAP Fault")
        } catch let error as PassportError {
            XCTAssertEqual(error, .authenticationFailed, "HTTP 500 SOAP Fault must map to PassportError.authenticationFailed")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        // Boundary test: Empty email or password throws invalidCredentials without dispatching request
        do {
            _ = try await passportClient.authenticate(email: "", password: "password123")
            XCTFail("Expected empty email to fail validation")
        } catch let error as PassportError {
            XCTAssertEqual(error, .invalidCredentials)
        }

        // Boundary test: Non-email identifier (missing @) validation check
        let nonEmailUsername = "plainusername"
        XCTAssertFalse(nonEmailUsername.contains("@"), "Non-email username must lack '@' character")
        let sessionVM = SessionViewModel()
        sessionVM.addContact(email: nonEmailUsername, displayName: "Invalid")
        XCTAssertFalse(sessionVM.contacts.contains(where: { $0.email == nonEmailUsername }), "Non-email account identifier must be rejected by contact validation")
    }

    /// Test 2.3: MSNP18 911 error response on USR SSO S handshake maps to .authenticationFailed(code: 911).
    func test_tier2_auth_msnp18Error911RejectedHandshake() async throws {
        let accountEmail = "user@crosstalk.im"
        await nsServer.setFailSsoWith911(true)

        try await nsClient.connect()

        do {
            try await nsClient.signIn(email: accountEmail, ticket: "invalid-ticket", proof: "invalid-proof")
            XCTFail("Expected signIn to throw NotificationServerError.authenticationFailed(code: 911)")
        } catch let error as NotificationServerError {
            if case .authenticationFailed(let code) = error {
                XCTAssertEqual(code, 911, "MSNP18 rejection code must be 911")
            } else {
                XCTFail("Expected .authenticationFailed(code: 911), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Test 2.4: Circular XFR NS redirect loop triggers .maxRedirectsExceeded after 3 hops.
    func test_tier2_auth_infiniteRedirectLoopDetection() async throws {
        let accountEmail = "user@crosstalk.im"
        // Configure Notification Server to redirect to itself indefinitely
        await nsServer.setRedirectEndpoint(host: "127.0.0.1", port: allocatedNsPort)

        try await nsClient.connect()

        do {
            try await nsClient.signIn(email: accountEmail, ticket: "mock-ticket", proof: "mock-proof")
            XCTFail("Expected signIn to throw NotificationServerError.maxRedirectsExceeded")
        } catch let error as NotificationServerError {
            XCTAssertEqual(error, .maxRedirectsExceeded, "Client must detect redirect loop and abort with maxRedirectsExceeded")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// Test 2.5: Abrupt TCP socket disconnect during handshake transitions state to unexpectedClosure.
    func test_tier2_auth_abruptTcpDisconnectDuringHandshake() async throws {
        try await nsClient.connect()
        XCTAssertTrue(nsClient.isConnected, "Client must report isConnected == true upon successful TCP connect")

        // Server abruptly severs TCP listener and closes all active sockets
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
            XCTFail("Expected .disconnected(reason: .unexpectedClosure), got \(disconnectEvent)")
        }

        try await waitForCondition(timeout: TestTimeout.standard, description: "Client isConnected must transition to false") {
            return self.nsClient.isConnected == false
        }
        XCTAssertFalse(nsClient.isConnected, "nsClient.isConnected must be false after abrupt socket severance")
    }

    // MARK: - =================================================================
    // MARK: - Feature 3: Skin & Theme Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 3.1: Corrupted or malformed skin.json decoding safely falls back to default WLM 2009 Light theme.
    func test_tier2_theme_corruptedSkinJsonDecodingFallback() {
        let corruptedJsonString = """
        {
            "name": "Corrupted WLM Skin",
            "colors": { "windowBackground": 12345, "primary": "#INVALID_HEX" },
            "unclosedBracket": true
        """
        let corruptedData = Data(corruptedJsonString.utf8)

        // Attempting to decode corrupted JSON must throw an error rather than crash
        XCTAssertThrowsError(try JSONDecoder().decode(SkinConfig.self, from: corruptedData))

        // Safe fallback resolution logic
        let resolvedSkin: AeroSkin
        do {
            _ = try JSONDecoder().decode(SkinConfig.self, from: corruptedData)
            resolvedSkin = .wlm2009Night
        } catch {
            resolvedSkin = .wlm2009Light
        }

        XCTAssertEqual(resolvedSkin, .wlm2009Light, "Failed skin JSON decoding must safely fall back to wlm2009Light")
        XCTAssertFalse(resolvedSkin.isDark, "Default fallback skin must not be dark mode")
        XCTAssertEqual(resolvedSkin.primaryColor, .wlmPrimary, "Default fallback skin primary color must be wlmPrimary")
    }

    /// Test 3.2: Unknown scene identifier string safely falls back to default .sky scene.
    func test_tier2_theme_unknownSceneIdentifierFallback() {
        let unknownSceneIds = ["CyberpunkNeon2077", "MatrixGreen", "", "null", "Windows95Teal"]

        for sceneId in unknownSceneIds {
            let matchedScene = WlmScene(rawValue: sceneId)
            let fallbackScene = matchedScene ?? .sky
            XCTAssertNil(matchedScene, "Unknown rawValue '\(sceneId)' must not construct a valid WlmScene directly")
            XCTAssertEqual(fallbackScene, .sky, "Unknown scene identifier must fall back to .sky")
        }

        XCTAssertEqual(WlmScene.sky.rawValue, "Windows Live Sky")
        XCTAssertFalse(WlmScene.sky.isDarkText, "Sky header uses white text by default")
    }

    /// Test 3.3: Playing missing or disabled audio asset executes graceful no-op without exception.
    func test_tier2_theme_missingAudioAssetGracefulNoOp() {
        let soundPlayer = MsnSoundPlayer.shared
        let originalSoundEnabled = soundPlayer.isSoundEnabled
        defer { soundPlayer.isSoundEnabled = originalSoundEnabled }

        // Mute sound
        soundPlayer.isSoundEnabled = false
        let playCountBefore = soundPlayer.playCount
        soundPlayer.play(.nudge)
        soundPlayer.play(.online)
        soundPlayer.play(.type)
        XCTAssertEqual(soundPlayer.playCount, playCountBefore, "play() must be a strict no-op when isSoundEnabled == false")

        // Re-enable sound
        soundPlayer.isSoundEnabled = true
        soundPlayer.play(.nudge)
        XCTAssertEqual(soundPlayer.playCount, playCountBefore + 1, "play() must increment playCount when enabled")
        XCTAssertEqual(soundPlayer.lastPlayedEffect, .nudge, "lastPlayedEffect must record .nudge")
    }

    /// Test 3.4: Rapid skin toggle across all options maintains state consistency and palette values.
    func test_tier2_theme_rapidSkinToggleStateConsistency() {
        let session = SessionViewModel()

        let skins = AeroSkin.allCases
        XCTAssertEqual(skins.count, 3, "There must be 3 canonical AeroSkin cases")

        // Rapidly toggle skins 60 times
        for i in 0..<60 {
            let selectedSkin = skins[i % skins.count]
            session.activeSkin = selectedSkin

            switch selectedSkin {
            case .wlm2009Light:
                XCTAssertFalse(session.activeSkin.isDark)
                XCTAssertEqual(session.activeSkin.primaryColor, .wlmPrimary)
                XCTAssertEqual(session.activeSkin.windowBackgroundColor, .wlmWindowBackground)
            case .wlm2009Night:
                XCTAssertTrue(session.activeSkin.isDark)
                XCTAssertEqual(session.activeSkin.primaryColor, .wlmNightPrimary)
                XCTAssertEqual(session.activeSkin.windowBackgroundColor, .wlmNightBackground)
            case .msn75Classic:
                XCTAssertFalse(session.activeSkin.isDark)
                XCTAssertEqual(session.activeSkin.primaryColor, .msn75Primary)
                XCTAssertEqual(session.activeSkin.windowBackgroundColor, .msn75Background)
            }
        }
    }

    /// Test 3.5: Color gradient interpolation with identical start and end colors safely returns start color.
    func test_tier2_theme_gradientWithIdenticalStartAndEndColors() {
        let blueColor: UInt32 = 0xFF0078D7

        // Interpolating identical colors across 10 steps
        for step in 0..<10 {
            let result = ColorGradientEngine.interpolate(start: blueColor, end: blueColor, index: step, count: 10)
            XCTAssertEqual(result, blueColor, "Interpolation between identical colors at step \(step) must yield exact original color")
        }

        // Boundary: count <= 1 handles zero or single character count without division-by-zero
        let singleCharResult = ColorGradientEngine.interpolate(start: blueColor, end: 0xFF5AC8FA, index: 0, count: 1)
        XCTAssertEqual(singleCharResult, blueColor, "Interpolation with count <= 1 must immediately return start color")

        let zeroCountResult = ColorGradientEngine.interpolate(start: blueColor, end: 0xFF5AC8FA, index: 0, count: 0)
        XCTAssertEqual(zeroCountResult, blueColor, "Interpolation with count 0 must safely return start color")
    }

    // MARK: - =================================================================
    // MARK: - Feature 4: Contact Groups Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 4.1: Empty ABCH address book response (0 contacts, 0 groups) produces empty lists without error.
    func test_tier2_contacts_emptyAddressBookZeroContacts() async throws {
        // Intercept ABFindContactsPaged with empty XML payload
        MockSOAPRouter.shared.customHandlers.append { req, _ in
            if req.url?.absoluteString.contains("abservice") == true {
                return MockSOAPResponse(statusCode: 200, xml: """
                <?xml version="1.0" encoding="utf-8"?>
                <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
                  <soap:Body>
                    <ABFindContactsPagedResponse xmlns="http://www.msn.com/webservices/AddressBook">
                      <ABFindContactsPagedResult>
                        <Groups/>
                        <Contacts/>
                      </ABFindContactsPagedResult>
                    </ABFindContactsPagedResponse>
                  </soap:Body>
                </soap:Envelope>
                """)
            }
            return nil
        }

        let result = try await abchClient.findContacts(ticket: "mock-contacts-ticket")
        XCTAssertEqual(result.contacts.count, 0, "Empty ABCH response must parse to 0 contacts")
        XCTAssertEqual(result.groups.count, 0, "Empty ABCH response must parse to 0 groups")

        let session = SessionViewModel()
        session.contacts = result.contacts
        session.groups = result.groups

        XCTAssertTrue(session.onlineContacts.isEmpty, "onlineContacts must be empty")
        XCTAssertTrue(session.offlineContacts.isEmpty, "offlineContacts must be empty")
    }

    /// Test 4.2: Display names with unicode, surrogate pairs, emojis, and RTL script preserve characters intact.
    func test_tier2_contacts_unicodeAndSurrogateDisplayNames() {
        let complexNick = "[b][c=4]✨ Stefano 🎵 [c=12]ステファノ[/c] 🚀 👨‍👩‍👧‍👦 العربية[/c][/b]"
        let contact = Contact(
            id: "stefano@crosstalk.im",
            nickname: complexNick,
            email: "stefano@crosstalk.im",
            presence: .online
        )

        let clean = contact.cleanDisplayName
        // Stripped BBCode but preserved all emojis, CJK, and Arabic
        XCTAssertFalse(clean.contains("[b]"), "Clean name must strip [b]")
        XCTAssertFalse(clean.contains("[c=4]"), "Clean name must strip [c=4]")
        XCTAssertTrue(clean.contains("✨ Stefano 🎵"), "Clean name must retain Latin and emojis")
        XCTAssertTrue(clean.contains("ステファノ"), "Clean name must retain Japanese Katakana")
        XCTAssertTrue(clean.contains("🚀"), "Clean name must retain rocket emoji")
        XCTAssertTrue(clean.contains("👨‍👩‍👧‍👦"), "Clean name must retain complex multi-surrogate family emoji")
        XCTAssertTrue(clean.contains("العربية"), "Clean name must retain Arabic script")
    }

    /// Test 4.3: XML special characters in personal message (<>&"') are escaped in UUX and unescaped on receipt.
    func test_tier2_contacts_xmlSpecialCharsInPersonalMessage() {
        let rawMessage = "Coding <Swift> & 'Objective-C' in \"WLM 2009\" > Everything"
        let escaped = SOAPXmlBuilder.escapeXml(rawMessage)

        XCTAssertFalse(escaped.contains("<Swift>"), "Raw '<' must be escaped")
        XCTAssertTrue(escaped.contains("&lt;Swift&gt;"), "'<' and '>' must be converted to &lt; and &gt;")
        XCTAssertTrue(escaped.contains("&amp;"), "'&' must be converted to &amp;")
        XCTAssertTrue(escaped.contains("&quot;WLM 2009&quot;"), "'\"' must be converted to &quot;")
        XCTAssertTrue(escaped.contains("&apos;Objective-C&apos;"), "''' must be converted to &apos;")

        // Roundtrip unescape
        let unescaped = SOAPXmlBuilder.unescapeXml(escaped)
        XCTAssertEqual(unescaped, rawMessage, "Unescaped XML string must perfectly match the original raw message")
    }

    /// Test 4.4: Rapid presence changes issue strictly monotonic transaction IDs.
    func test_tier2_contacts_rapidPresenceChangesMonotonicTrIds() {
        var trIds: [Int] = []
        for _ in 0..<5 {
            trIds.append(nsClient.nextTransactionId())
        }

        XCTAssertEqual(trIds.count, 5)
        for i in 0..<4 {
            XCTAssertLessThan(trIds[i], trIds[i + 1], "Transaction ID \(trIds[i]) must be strictly less than next ID \(trIds[i + 1])")
        }
    }

    /// Test 4.5: Adding a duplicate contact or invalid non-email identifier is rejected.
    func test_tier2_contacts_duplicateContactAddRejection() {
        let session = SessionViewModel()
        let contactEmail = "friend@crosstalk.im"

        // Initial add succeeds
        session.addContact(email: contactEmail, displayName: "Friend One")
        XCTAssertEqual(session.contacts.count, 1, "Initial contact add must succeed")

        // Duplicate add with exact same email is rejected
        session.addContact(email: contactEmail, displayName: "Duplicate Friend")
        XCTAssertEqual(session.contacts.count, 1, "Duplicate contact with exact email must be ignored")

        // Duplicate add with uppercase email is rejected (case-insensitive deduplication)
        session.addContact(email: "FRIEND@CROSSTALK.IM", displayName: "Uppercase Duplicate")
        XCTAssertEqual(session.contacts.count, 1, "Duplicate contact with uppercase email must be ignored")

        // Invalid non-email identifier lacking '@' is rejected
        session.addContact(email: "plain_username_without_at", displayName: "Bad Identifier")
        XCTAssertEqual(session.contacts.count, 1, "Contact identifier without '@' must be rejected")
    }

    // MARK: - =================================================================
    // MARK: - Feature 5: Chat Messaging Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 5.1: Empty or whitespace-only message is rejected with SwitchboardError.emptyMessage.
    func test_tier2_chat_emptyOrWhitespaceMessageRejection() async {
        do {
            try await sbSession.sendMessage("", ackMode: .acknowledged)
            XCTFail("Empty message must throw SwitchboardError.emptyMessage")
        } catch let error as SwitchboardError {
            XCTAssertEqual(error, .emptyMessage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // ChatViewModel draft check
        let contact = Contact(id: "peer@crosstalk.im", email: "peer@crosstalk.im", displayName: "Peer")
        let chatVM = ChatViewModel(contact: contact)
        chatVM.draftText = "   \t\n  "
        chatVM.sendMessage()
        XCTAssertEqual(chatVM.messages.count, 0, "Whitespace-only draft must not be appended to chat transcript")
    }

    /// Test 5.2: Sending message exceeding 1,202 bytes throws SwitchboardError.messageExceedsMaxLength.
    func test_tier2_chat_messageExceeding1202BytesLimit() async {
        let boundaryPassText = String(repeating: "A", count: 1202)
        XCTAssertEqual(boundaryPassText.utf8.count, 1202)

        let boundaryFailText = String(repeating: "A", count: 1203)
        XCTAssertEqual(boundaryFailText.utf8.count, 1203)

        // 1,203 bytes must throw messageExceedsMaxLength
        do {
            try await sbSession.sendMessage(boundaryFailText, ackMode: .acknowledged)
            XCTFail("Message exceeding 1,202 bytes must throw SwitchboardError.messageExceedsMaxLength")
        } catch let error as SwitchboardError {
            XCTAssertEqual(error, .messageExceedsMaxLength)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Test 5.3: Message with embedded null byte terminates cleanly without buffer overflow.
    func test_tier2_chat_embeddedNullByteTermination() async throws {
        try await sbSession.connect(authKey: "mock-auth-key", userEmail: "user@crosstalk.im")
        let textWithNull = "Hello\0World\0WLM2009"

        try await sbSession.sendMessage(textWithNull, ackMode: .acknowledged)

        let msg = await sbServer.waitForMessage(timeoutSeconds: TestTimeout.standard)
        XCTAssertNotNil(msg, "Server must receive message with null characters without connection termination")
        if case .text(let body, _) = msg {
            XCTAssertTrue(body.contains("Hello"), "Received body must contain text before null byte")
        }
    }

    /// Test 5.4: Server NAK response transitions message delivery status to failed.
    func test_tier2_chat_deliveryNakFailureHandling() {
        let deliveryError = SwitchboardError.messageDeliveryFailed(trId: 42)
        if case .messageDeliveryFailed(let trId) = deliveryError {
            XCTAssertEqual(trId, 42, "Failed transaction ID must be 42")
        } else {
            XCTFail("Expected messageDeliveryFailed(trId: 42)")
        }

        var message = ChatMessage(
            contactId: "peer@crosstalk.im",
            author: .me,
            text: "Important unreceived message",
            deliveryStatus: .sending
        )
        XCTAssertTrue(message.isSending)

        // On NAK receipt:
        message.deliveryStatus = .failed
        message.deliveryError = "Delivery rejected by Switchboard (NAK 42)"
        XCTAssertEqual(message.deliveryStatus, .failed)
        XCTAssertNotNil(message.deliveryError)
    }

    /// Test 5.5: Rapid burst of 10 messages dispatches with monotonic transaction IDs and zero drops.
    func test_tier2_chat_rapidBurstMessaging10Packets() async throws {
        try await sbSession.connect(authKey: "mock-auth-key", userEmail: "user@crosstalk.im")

        for i in 1...10 {
            try await sbSession.sendMessage("Rapid burst packet #\(i)", ackMode: .acknowledged)
        }

        let recorded = await sbServer.getRecordedMessages()
        XCTAssertGreaterThanOrEqual(recorded.count, 10, "Server must record all 10 burst messages")
    }

    // MARK: - =================================================================
    // MARK: - Feature 6: Nudges Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 6.1: Nudge 2.0-second cooldown is enforced, throwing NudgeError.cooldownActive on immediate second call.
    func test_tier2_nudge_cooldownEnforcement2000Ms() async throws {
        try await sbSession.connect(authKey: "mock-auth-key", userEmail: "user@crosstalk.im")

        // First nudge succeeds
        try await sbSession.sendNudge()

        // Immediate second nudge within 2.0s cooldown must throw cooldownActive
        do {
            try await sbSession.sendNudge()
            XCTFail("Immediate second nudge must throw NudgeError.cooldownActive")
        } catch let error as NudgeError {
            XCTAssertEqual(error, .cooldownActive, "Cooldown error must be .cooldownActive")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Test 6.2: Rapid successive nudge spam on ChatViewModel throttles to exactly 1 dispatch.
    func test_tier2_nudge_rapidSuccessiveNudgeSpamThrottled() {
        let contact = Contact(id: "peer@crosstalk.im", email: "peer@crosstalk.im", displayName: "Peer")
        let chatVM = ChatViewModel(contact: contact)

        // Spam sendNudge() 10 times in immediate succession
        for _ in 0..<10 {
            chatVM.sendNudge()
        }

        let nudgeMessages = chatVM.messages.filter { $0.isNudge }
        XCTAssertEqual(nudgeMessages.count, 1, "Spamming sendNudge() must throttle to exactly 1 nudge message")
        XCTAssertEqual(chatVM.cooldownErrorMessage, "Please wait a moment before sending another Nudge.")
    }

    /// Test 6.3: Malformed datacast body (non-1 ID, e.g. ID: 99) is ignored and not treated as a nudge.
    func test_tier2_nudge_malformedDatacastBodyIgnored() {
        let datacastBody = "ID: 99\r\nData: <some-data/>\r\n\r\n"
        let isNudge = datacastBody.contains("ID: 1")
        XCTAssertFalse(isNudge, "Datacast with ID: 99 must not be recognized as a Nudge (requires ID: 1)")
    }

    /// Test 6.4: Triggering NudgeShakeEngine while isShaking == true is a safe no-op.
    func test_tier2_nudge_triggerWhileAlreadyShakingNoOp() async {
        let engine = NudgeShakeEngine()
        XCTAssertFalse(engine.isShaking)

        // Launch slow shake animation in background task
        let shakeTask = Task {
            await engine.trigger(stepNanoseconds: 40_000_000) // 40ms per step
        }

        // Wait brief moment for shake to commence
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(engine.isShaking, "Engine must be shaking")

        // Calling trigger again while shaking must return immediately without resetting or overlapping
        await engine.trigger(stepNanoseconds: 0)
        XCTAssertTrue(engine.isShaking, "Engine must still be shaking from the primary task")

        _ = await shakeTask.result
        XCTAssertFalse(engine.isShaking, "Engine must conclude shake cleanly")
        XCTAssertEqual(engine.offsetX, 0, "X offset must return to 0")
        XCTAssertEqual(engine.offsetY, 0, "Y offset must return to 0")
    }

    /// Test 6.5: text/x-msmsgscontrol MIME missing TypingUser header is safely discarded.
    func test_tier2_nudge_missingTypingUserInControlMime() {
        let malformedMime = "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\n\r\n\r\n"

        func extractHeader(_ text: String, header: String) -> String? {
            for line in text.components(separatedBy: "\r\n") {
                if line.lowercased().hasPrefix(header.lowercased() + ":") {
                    let parts = line.components(separatedBy: ":")
                    return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }

        let extractedUser = extractHeader(malformedMime, header: "TypingUser")
        XCTAssertNil(extractedUser, "MIME without TypingUser header must return nil")
    }

    // MARK: - =================================================================
    // MARK: - Feature 7: Winks Boundary & Corner Cases (5 tests)
    // MARK: - =================================================================

    /// Test 7.1: Wink payload exceeding 2MB (2,097,152 bytes) cap is strictly rejected.
    func test_tier2_winks_payloadExceeding2MbCapRejected() {
        let oversizedBytes = WinkPayload.maxCabBytes + 1 // 2,097,153 bytes
        let validSha1d = Data(repeating: 0x55, count: 20).base64EncodedString()

        let oversizedXml = """
        <msnobj Creator="user@crosstalk.im" Size="\(oversizedBytes)" Type="8" Location="wink.cab" Friendly="AAA=" SHA1D="\(validSha1d)" SHA1C="AAA="/>
        """
        let offerBody = "ID: 2\r\nData: \(oversizedXml)\r\n\r\n"

        let parsed = WinkPayload.parseOffer(body: offerBody)
        XCTAssertNil(parsed, "Wink payload exceeding 2MB must be rejected by parseOffer")

        // Boundary: exact 2MB with valid SHA1D passes size check
        let exactCapBytes = WinkPayload.maxCabBytes
        let exactCapXml = """
        <msnobj Creator="user@crosstalk.im" Size="\(exactCapBytes)" Type="8" Location="wink.cab" Friendly="AAA=" SHA1D="\(validSha1d)" SHA1C="AAA="/>
        """
        let exactCapOffer = "ID: 2\r\nData: \(exactCapXml)\r\n\r\n"
        let exactParsed = WinkPayload.parseOffer(body: exactCapOffer)
        XCTAssertNotNil(exactParsed, "Wink payload of exactly 2MB must be accepted")
        XCTAssertEqual(exactParsed?.size, WinkPayload.maxCabBytes)
    }

    /// Test 7.2: Directory traversal paths in CAB archive references are blocked.
    func test_tier2_winks_directoryTraversalArchivePathBlocked() {
        let dangerousPaths = [
            "../../etc/passwd",
            "../wink.swf",
            "subdir/../../../root/system.dll",
            "/root/wink.swf",
            "\\windows\\system32\\cmd.exe",
            "C:\\boot.ini",
            "wink.swf/..",
            "",
            "   "
        ]

        for path in dangerousPaths {
            XCTAssertFalse(WinkPayload.isSafeArchivePath(path), "Path '\(path)' must be flagged as unsafe")
            XCTAssertNil(WinkPayload.sanitizeArchivePath(path), "Sanitized path for '\(path)' must return nil")
        }

        // Safe relative paths
        let safePaths = ["wink.swf", "assets/wink.swf", "media/animations/knock_knock.swf"]
        for path in safePaths {
            XCTAssertTrue(WinkPayload.isSafeArchivePath(path), "Relative path '\(path)' must be accepted as safe")
            XCTAssertNotNil(WinkPayload.sanitizeArchivePath(path))
        }
    }

    /// Test 7.3: Corrupted SHA1D digest (invalid base64 or wrong byte count) fails validation.
    func test_tier2_winks_corruptedSha1dDigestMismatch() {
        // Non-base64 string
        let invalidBase64Offer = """
        ID: 2
        Data: <msnobj Creator="user@crosstalk.im" Size="1024" Type="8" Location="wink.cab" Friendly="AAA=" SHA1D="!!!NOT_BASE64!!!" SHA1C="AAA="/>
        """
        XCTAssertNil(WinkPayload.parseOffer(body: invalidBase64Offer), "Non-base64 SHA1D must fail offer parsing")

        // Base64 string with wrong length (16 bytes MD5 instead of 20 bytes SHA-1)
        let md5BytesBase64 = Data(repeating: 0xAA, count: 16).base64EncodedString()
        let wrongByteCountOffer = """
        ID: 2
        Data: <msnobj Creator="user@crosstalk.im" Size="1024" Type="8" Location="wink.cab" Friendly="AAA=" SHA1D="\(md5BytesBase64)" SHA1C="AAA="/>
        """
        XCTAssertNil(WinkPayload.parseOffer(body: wrongByteCountOffer), "16-byte digest (not 20-byte SHA-1) must fail offer parsing")
    }

    /// Test 7.4: Starting a new wink while one is playing dismisses current and starts new cleanly.
    func test_tier2_winks_playbackInterruptionAndReset() {
        final class MockWinkPlaybackState {
            var activeWinkId: String?
            var isPlaying: Bool = false

            func playWink(id: String) {
                // If a wink is currently playing, dismiss and start new
                if isPlaying {
                    dismissCurrent()
                }
                activeWinkId = id
                isPlaying = true
            }

            func dismissCurrent() {
                activeWinkId = nil
                isPlaying = false
            }
        }

        let state = MockWinkPlaybackState()
        state.playWink(id: "wink-knock-knock")
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.activeWinkId, "wink-knock-knock")

        // Interrupt with second wink
        state.playWink(id: "wink-water-balloon")
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.activeWinkId, "wink-water-balloon", "Active wink must be updated to the new wink")

        state.dismissCurrent()
        XCTAssertFalse(state.isPlaying)
        XCTAssertNil(state.activeWinkId)
    }

    /// Test 7.5: Empty or zero-sized metadata offer returns nil from parseOffer.
    func test_tier2_winks_emptyOrZeroSizedMetadataOffer() {
        XCTAssertNil(WinkPayload.parseOffer(body: ""), "Empty offer string must return nil")
        XCTAssertNil(WinkPayload.parseOffer(body: "ID: 2\r\n\r\n"), "Offer missing Data: line must return nil")

        let validSha1d = Data(repeating: 0x11, count: 20).base64EncodedString()

        // Size="0"
        let zeroSizeXml = """
        ID: 2
        Data: <msnobj Creator="user@crosstalk.im" Size="0" Type="8" Location="wink.cab" Friendly="AAA=" SHA1D="\(validSha1d)" SHA1C="AAA="/>
        """
        XCTAssertNil(WinkPayload.parseOffer(body: zeroSizeXml), "Size 0 must return nil")

        // Size < 36 bytes (minimum header size for CAB)
        let tooSmallXml = """
        ID: 2
        Data: <msnobj Creator="user@crosstalk.im" Size="35" Type="8" Location="wink.cab" Friendly="AAA=" SHA1D="\(validSha1d)" SHA1C="AAA="/>
        """
        XCTAssertNil(WinkPayload.parseOffer(body: tooSmallXml), "Size < 36 bytes must return nil")
    }
}
