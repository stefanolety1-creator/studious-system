import SwiftUI
import MsngrCore
import MsngrProtocol

/// Connection lifecycle state of the MSNP18 session.
public enum SessionNetworkState: String, Sendable, Equatable {
    case disconnected = "Signed Out"
    case connecting = "Connecting..."
    case authenticating = "Signing In..."
    case synchronizing = "Synchronizing Contacts..."
    case connected = "Connected"
}

/// Primary `@MainActor` ViewModel coordinating authentication, Notification Server, ABCH contacts, and UI state.
@MainActor
public final class SessionViewModel: ObservableObject {
    @Published public var currentAccount: UserAccount
    @Published public var networkState: SessionNetworkState = .disconnected
    @Published public var contacts: [Contact] = []
    @Published public var groups: [ContactGroup] = []
    @Published public var conversations: [String: Conversation] = [:]
    @Published public var selectedContactId: String?
    @Published public var searchQuery: String = ""
    @Published public var activeSkin: AeroSkin = .wlm2009Light
    @Published public var activeScene: WlmScene = .sky
    @Published public var useClassicChatLayout: Bool = false
    @Published public var enableMessengerPlusFormatting: Bool = true
    @Published public var lastErrorMessage: String?
    @Published public var connectionLogs: [String] = []
    @Published public var isLogExpanded: Bool = false

    private var nsClient: NotificationServerClient?
    private var passportClient: PassportRST2Client
    private var abchClient: ABCHClient
    private var rpsGenerator: RPSProofGenerator
    private var eventTask: Task<Void, Never>?

    public init(
        account: UserAccount = UserAccount(
            email: "stefano@escargot.chat",
            displayName: "[c=12]Stefano[/c] ??",
            personalMessage: "Windows Live Messenger 2009 on iOS"
        ),
        passportClient: PassportRST2Client = PassportRST2Client(),
        abchClient: ABCHClient = ABCHClient(),
        rpsGenerator: RPSProofGenerator = RPSProofGenerator()
    ) {
        self.currentAccount = account
        self.passportClient = passportClient
        self.abchClient = abchClient
        self.rpsGenerator = rpsGenerator
    }

    public var onlineContacts: [Contact] {
        filteredContacts
            .filter { $0.presence.isOnline }
            .sorted {
                if $0.presence.priority != $1.presence.priority {
                    return $0.presence.priority < $1.presence.priority
                }
                return $0.cleanDisplayName.localizedCaseInsensitiveCompare($1.cleanDisplayName) == .orderedAscending
            }
    }

    public var offlineContacts: [Contact] {
        filteredContacts
            .filter { !$0.presence.isOnline }
            .sorted {
                $0.cleanDisplayName.localizedCaseInsensitiveCompare($1.cleanDisplayName) == .orderedAscending
            }
    }

    public var filteredContacts: [Contact] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contacts }
        return contacts.filter {
            $0.cleanDisplayName.localizedCaseInsensitiveContains(query) ||
            $0.email.localizedCaseInsensitiveContains(query) ||
            $0.cleanStatusMessage.localizedCaseInsensitiveContains(query)
        }
    }

    /// Signs in using offline demo roster so all WLM 2009 features can be explored without a live Escargot backend.
    public func signInDemoMode(email: String, displayName: String? = nil, initialPresence: PresenceStatus = .online) {
        lastErrorMessage = nil
        currentAccount = UserAccount(
            email: email.isEmpty ? "stefano@escargot.chat" : email,
            displayName: displayName ?? "[b][c=12]Stefano[/c][/b]",
            personalMessage: "Listening to Daft Punk - Digital Love ??",
            presence: initialPresence,
            useMockServer: true,
            lastLoginDate: Date()
        )
        networkState = .connected

        groups = [
            ContactGroup(id: "grp-friends", name: "Friends", orderIndex: 0),
            ContactGroup(id: "grp-coworkers", name: "Team & Devs", orderIndex: 1)
        ]

        let selin = Contact(
            id: "selin@escargot.chat",
            nickname: "[c=4]Selin[/c] ?",
            email: "selin@escargot.chat",
            presence: .online,
            statusMessage: "Coding in SwiftUI on macOS & iOS!",
            unreadCount: 1,
            groupId: "grp-friends"
        )
        let alex = Contact(
            id: "alex@escargot.chat",
            nickname: "Alex [c=3](Gaming)[/c]",
            email: "alex@escargot.chat",
            presence: .busy,
            statusMessage: "Playing Halo 3 - Do Not Disturb",
            groupId: "grp-friends"
        )
        let giulia = Contact(
            id: "giulia@escargot.chat",
            nickname: "Giulia ??",
            email: "giulia@escargot.chat",
            presence: .away,
            statusMessage: "Out for espresso ?",
            groupId: "grp-coworkers"
        )
        let marco = Contact(
            id: "marco@escargot.chat",
            nickname: "Marco",
            email: "marco@escargot.chat",
            presence: .offline,
            statusMessage: "See you tomorrow!",
            groupId: "grp-coworkers"
        )

        contacts = [selin, alex, giulia, marco]

        var welcomeConv = Conversation(
            id: selin.id,
            title: selin.cleanDisplayName,
            participantEmails: [selin.email],
            isSwitchboardConnected: true
        )
        welcomeConv.appendMessage(ChatMessage(
            contactId: selin.id,
            author: .contact,
            text: "Hey! Welcome to [b][c=12]Windows Live Messenger 2009[/c][/b] on iOS!",
            senderEmail: selin.email,
            senderName: selin.cleanDisplayName
        ))
        conversations[selin.id] = welcomeConv
        selectedContactId = selin.id
        MsnSoundPlayer.shared.play(.online)
    }

    public func contacts(for group: ContactGroup) -> [Contact] {
        filteredContacts.filter { $0.groupId == group.id }
    }

    public var ungroupedContacts: [Contact] {
        filteredContacts.filter { c in
            c.groupId == nil || !groups.contains(where: { $0.id == c.groupId })
        }
    }

    public func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        Task { @MainActor in
            self.connectionLogs.append(line)
            if self.connectionLogs.count > 250 {
                self.connectionLogs.removeFirst(self.connectionLogs.count - 250)
            }
        }
    }

    public func clearLogs() {
        connectionLogs.removeAll()
    }

    /// Signs in against a live or local Mock Notification Server + Passport RST2 + ABCH endpoint.
    public func signInLive(email: String, password: String, initialPresence: PresenceStatus = .online) async {
        lastErrorMessage = nil
        clearLogs()
        networkState = .authenticating

        let config = currentAccount.serverConfig
        addLog("?? Starting sign-in for \(email)...")
        addLog("?? Server: \(config.mainServer):\(config.mainPort)")
        addLog("?? Auth Service: \(config.authServer)")

        do {
            let authUrl = URL(string: config.authServer) ?? URL(string: "https://ctas.login.ugnet.gay/RST.srf")!
            let passport = PassportRST2Client(endpoint: authUrl)
            passport.logHandler = { [weak self] msg in
                self?.addLog(msg)
            }
            self.passportClient = passport

            let client = NotificationServerClient(
                host: config.mainServer,
                port: UInt16(config.mainPort)
            )
            client.logHandler = { [weak self] msg in
                self?.addLog(msg)
            }
            self.nsClient = client

            networkState = .connecting
            addLog("?? Negotiating protocol version & SSO challenge...")
            let tokens = try await client.fullSignIn(
                email: email,
                password: password,
                config: config,
                passportClient: passport,
                rpsGenerator: rpsGenerator
            )

            networkState = .synchronizing
            addLog("?? Synchronizing address book contacts...")
            let abchUrl = URL(string: config.addressBookServer) ?? URL(string: "https://ctsvcs.addressbook.ugnet.gay/abservice/abservice.asmx")!
            let abch = ABCHClient(endpoint: abchUrl)
            abch.logHandler = { [weak self] msg in
                self?.addLog(msg)
            }
            self.abchClient = abch

            do {
                let abchResult = try await abch.findContacts(ticket: tokens.contactsToken)
                self.contacts = abchResult.contacts
                self.groups = abchResult.groups
                self.addLog("? Address book loaded (\(abchResult.contacts.count) contacts)")

                let adlRoster = abchResult.contacts.map { ($0.email, $0.isBlocked ? 5 : 3) }
                try? await client.syncAddressBook(contacts: adlRoster)
            } catch {
                self.addLog("?? Address book service notice: \(error.localizedDescription) (continuing)")
            }

            try await client.setPresence(initialPresence)
            addLog("?? Sign-in complete! Online presence set to \(initialPresence.rawValue)")

            currentAccount.presence = initialPresence
            currentAccount.email = email
            networkState = .connected
            MsnSoundPlayer.shared.play(.online)

            startListeningToEvents(client: client)
        } catch {
            addLog("? Sign-in failed: \(error.localizedDescription)")
            if let nsErr = error as? NotificationServerError {
                switch nsErr {
                case .timeout:
                    addLog("?? Connection to \(config.mainServer):\(config.mainPort) timed out.")
                    addLog("?? The retro server or port 1863 appears unreachable from your current network/simulator.")
                    addLog("?? Tip: Tap 'Explore Offline / Demo Mode' below to test all messenger features immediately!")
                case .authenticationFailed(code: let code):
                    addLog("?? Authentication rejected by server (code \(code)). Check your email and password.")
                default:
                    break
                }
            } else if let passErr = error as? PassportError {
                switch passErr {
                case .invalidCredentials:
                    addLog("?? Invalid credentials provided.")
                case .authenticationFailed:
                    addLog("?? Passport authentication failed: \(passportClient.lastFaultString ?? "Unknown fault")")
                case .networkError(let msg):
                    addLog("?? Passport network error: \(msg)")
                default:
                    break
                }
            }
            isLogExpanded = true
            lastErrorMessage = "Sign-in failed: \(error.localizedDescription)"
            networkState = .disconnected
        }
    }

    private func startListeningToEvents(client: NotificationServerClient) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in client.events {
                guard let self = self else { break }
                switch event {
                case .contactPresenceChanged(let email, let status):
                    if let idx = self.contacts.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
                        self.contacts[idx].presence = status
                    }
                case .contactPersonalMessageChanged(let email, let message):
                    if let idx = self.contacts.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) {
                        self.contacts[idx].statusMessage = message
                    }
                case .switchboardInvitation(let sessionId, let host, let port, let authKey, let inviter):
                    self.handleIncomingSwitchboard(sessionId: sessionId, host: host, port: port, authKey: authKey, inviter: inviter)
                case .disconnected:
                    self.networkState = .disconnected
                default:
                    break
                }
            }
        }
    }

    private func handleIncomingSwitchboard(sessionId: String, host: String, port: UInt16, authKey: String, inviter: String) {
        Task {
            let session = SwitchboardSession(host: host, port: port)
            try? await session.answer(authKey: authKey, sessionId: sessionId, userEmail: self.currentAccount.email)
            var conv = self.conversations[inviter] ?? Conversation(
                id: inviter,
                title: inviter,
                participantEmails: [inviter],
                isSwitchboardConnected: true
            )
            conv.isSwitchboardConnected = true
            self.conversations[inviter] = conv
            MsnSoundPlayer.shared.play(.newAlert)
        }
    }

    public func updatePresence(_ status: PresenceStatus) {
        currentAccount.presence = status
        Task {
            try? await nsClient?.setPresence(status)
        }
    }

    public func updatePersonalMessage(_ message: String) {
        currentAccount.personalMessage = message
        Task {
            try? await nsClient?.setPersonalMessage(message)
        }
    }

    public func updateDisplayName(_ name: String) {
        currentAccount.displayName = name
        Task {
            try? await nsClient?.updateDisplayName(name)
        }
    }

    public func addContact(email: String, displayName: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), !contacts.contains(where: { $0.email.lowercased() == trimmed }) else { return }
        let newContact = Contact(
            id: trimmed,
            nickname: displayName.isEmpty ? trimmed : displayName,
            email: trimmed,
            presence: .online,
            statusMessage: "Added on Windows Live Messenger"
        )
        contacts.append(newContact)
    }

    public func signOut() {
        eventTask?.cancel()
        Task {
            try? await nsClient?.signOut()
        }
        networkState = .disconnected
        selectedContactId = nil
    }
}
