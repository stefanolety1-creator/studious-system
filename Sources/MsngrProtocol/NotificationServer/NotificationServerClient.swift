import Foundation
import Network
import MsngrCore

/// Reason for Notification Server disconnection.
public enum DisconnectReason: Sendable, Equatable {
    case cleanSignOut
    case unexpectedClosure
    case serverRevoked
}

/// Inbound events emitted by the MSNP18 Notification Server connection.
public enum MsnpServerEvent: Sendable, Equatable {
    case authenticated(email: String)
    case presenceUpdated(PresenceStatus)
    case personalMessageUpdated(String)
    case contactPresenceChanged(email: String, status: PresenceStatus)
    case contactPersonalMessageChanged(email: String, message: String)
    case switchboardInvitation(sessionId: String, host: String, port: UInt16, authKey: String, inviter: String)
    case disconnected(reason: DisconnectReason)
}

/// Errors emitted by the Notification Server client.
public enum NotificationServerError: Error, Equatable, Sendable {
    case authenticationFailed(code: Int)
    case synchronizationFailed(code: Int)
    case maxRedirectsExceeded
    case unexpectedClosure
    case timeout
}

/// Challenge issued by MSNP18 Notification Server on `USR SSO I` challenge exchange.
public struct SsoChallenge: Sendable, Equatable {
    public let policy: String
    public let nonce: String

    public init(policy: String, nonce: String) {
        self.policy = policy
        self.nonce = nonce
    }
}

/// Endpoint details returned by `XFR SB` for opening a Switchboard chat session.
public struct SwitchboardEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    public let authKey: String

    public init(host: String, port: UInt16, authKey: String) {
        self.host = host
        self.port = port
        self.authKey = authKey
    }
}

/// Protocol abstraction for the MSNP18 Notification Server client.
public protocol NotificationServerClientProtocol: Sendable {
    var events: AsyncStream<MsnpServerEvent> { get }
    var onContactPresenceChanged: ((Contact, PresenceStatus) -> Void)? { get set }
    var onGroupListUpdated: (([ContactGroup]) -> Void)? { get set }

    func connect() async throws
    func signIn(email: String, ticket: String, proof: String, machineGuid: String) async throws
    func finishSignIn(email: String, ticket: String, proof: String, machineGuid: String) async throws
    func negotiate(config: ServerConfig, email: String) async throws -> SsoChallenge
    func setPresence(_ status: PresenceStatus) async throws
    func setPersonalMessage(_ text: String) async throws
    func updateDisplayName(_ name: String) async throws
    func requestSwitchboard(timeout: TimeInterval) async throws -> SwitchboardEndpoint
    func disconnect() async
}

/// Production and mock-compatible MSNP18 Notification Server TCP client using `NWConnection` and `MsnpFrameDecoder`.
public final class NotificationServerClient: NotificationServerClientProtocol, @unchecked Sendable {
    public var host: String
    public var port: UInt16?
    public var switchboardFallbackPort: UInt16

    public var onContactPresenceChanged: ((Contact, PresenceStatus) -> Void)?
    public var onGroupListUpdated: (([ContactGroup]) -> Void)?

    private var connection: NWConnection?
    private let lock = NSLock()
    private var transactionCounter = 0
    private var continuation: AsyncStream<MsnpServerEvent>.Continuation?
    public let events: AsyncStream<MsnpServerEvent>

    private let frameDecoder = MsnpFrameDecoder()
    private var negotiatedVersion: String?
    public private(set) var isConnected: Bool = false
    private var lastRedirectEndpoint: (host: String, port: UInt16)?
    private var pendingTransactionContinuations: [Int: CheckedContinuation<MsnpFrame, Error>] = [:]
    private var pendingXfrRequests: [Int: CheckedContinuation<SwitchboardEndpoint, Error>] = [:]
    private var pendingSsoRequests: [Int: CheckedContinuation<Void, Error>] = [:]
    private var pendingAdlRequests: [Int: CheckedContinuation<Void, Error>] = [:]

    public init(
        host: String = "127.0.0.1",
        port: UInt16? = nil,
        switchboardFallbackPort: UInt16 = 1864
    ) {
        self.host = host
        self.port = port
        self.switchboardFallbackPort = switchboardFallbackPort
        var cont: AsyncStream<MsnpServerEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    public static func parseEndpoint(_ endpoint: String, defaultPort: UInt16 = 1864) -> (host: String, port: UInt16) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(of: ":"), separator != trimmed.startIndex else {
            return (trimmed, defaultPort)
        }
        let hostPart = String(trimmed[..<separator])
        let portPart = String(trimmed[trimmed.index(after: separator)...])
        if let parsedPort = UInt16(portPart) {
            return (hostPart, parsedPort)
        }
        return (trimmed, defaultPort)
    }

    public func nextTransactionId() -> Int {
        lock.lock()
        defer { lock.unlock() }
        transactionCounter += 1
        return transactionCounter
    }

    public func connect() async throws {
        guard let p = port else { throw NotificationServerError.unexpectedClosure }
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: p)!
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let cLock = NSLock()
            var resumed = false

            conn.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    cLock.lock()
                    if !resumed {
                        resumed = true
                        cLock.unlock()
                        self.isConnected = true
                        continuation.resume()
                    } else {
                        cLock.unlock()
                    }
                case .failed(let err):
                    cLock.lock()
                    if !resumed {
                        resumed = true
                        cLock.unlock()
                        self.isConnected = false
                        self.failAllPendingContinuations(with: err)
                        continuation.resume(throwing: err)
                    } else {
                        cLock.unlock()
                    }
                case .cancelled:
                    self.isConnected = false
                    self.continuation?.yield(.disconnected(reason: .unexpectedClosure))
                    self.failAllPendingContinuations(with: NotificationServerError.unexpectedClosure)
                default:
                    break
                }
            }
            let queue = DispatchQueue(label: "com.msngr.ns.client.\(UUID().uuidString)")
            conn.start(queue: queue)
        }
        startReceiveLoop()
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        isConnected = false
        failAllPendingContinuations(with: NotificationServerError.unexpectedClosure)
    }

    private func failAllPendingContinuations(with error: Error) {
        lock.lock()
        let txs = pendingTransactionContinuations
        pendingTransactionContinuations.removeAll()
        let xfrs = pendingXfrRequests
        pendingXfrRequests.removeAll()
        let ssos = pendingSsoRequests
        pendingSsoRequests.removeAll()
        let adls = pendingAdlRequests
        pendingAdlRequests.removeAll()
        lock.unlock()

        for (_, cont) in txs { cont.resume(throwing: error) }
        for (_, cont) in xfrs { cont.resume(throwing: error) }
        for (_, cont) in ssos { cont.resume(throwing: error) }
        for (_, cont) in adls { cont.resume(throwing: error) }
    }

    private func startReceiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                let frames = self.frameDecoder.feed(data)
                for frame in frames {
                    self.handleFrame(frame)
                }
            }
            if !isComplete && error == nil {
                self.startReceiveLoop()
            } else {
                self.isConnected = false
                self.continuation?.yield(.disconnected(reason: .unexpectedClosure))
                self.failAllPendingContinuations(with: NotificationServerError.unexpectedClosure)
            }
        }
    }

    private func normalizeIdentity(_ raw: String) -> String {
        let stripped = raw.hasPrefix("1:") ? String(raw.dropFirst(2)) : raw
        let clean = stripped.components(separatedBy: ";").first ?? stripped
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func handleFrame(_ frame: MsnpFrame) {
        if let trId = frame.transactionId {
            self.lock.lock()
            let cont = self.pendingTransactionContinuations.removeValue(forKey: trId)
            self.lock.unlock()
            cont?.resume(returning: frame)
        }

        switch frame.verb {
        case "VER":
            if let first = frame.parameters.first {
                self.negotiatedVersion = first
            }
        case "CVR":
            break
        case "USR":
            if frame.parameters.contains("OK") {
                let email = frame.parameters.count > 1 ? normalizeIdentity(frame.parameters[1]) : "mock-user@example.com"
                self.continuation?.yield(.authenticated(email: email))
                self.lock.lock()
                let ssos = self.pendingSsoRequests
                self.pendingSsoRequests.removeAll()
                self.lock.unlock()
                for (_, cont) in ssos { cont.resume() }
            }
        case "911":
            self.lock.lock()
            let ssos = self.pendingSsoRequests
            self.pendingSsoRequests.removeAll()
            self.lock.unlock()
            for (_, cont) in ssos {
                cont.resume(throwing: NotificationServerError.authenticationFailed(code: 911))
            }
        case "241":
            self.lock.lock()
            let adls = self.pendingAdlRequests
            self.pendingAdlRequests.removeAll()
            self.lock.unlock()
            for (_, cont) in adls {
                cont.resume(throwing: NotificationServerError.synchronizationFailed(code: 241))
            }
        case "ADL":
            if frame.parameters.contains("OK") {
                let trId = frame.transactionId ?? 0
                self.lock.lock()
                let cont = self.pendingAdlRequests.removeValue(forKey: trId)
                    ?? self.pendingAdlRequests.removeValue(forKey: self.pendingAdlRequests.keys.first ?? -1)
                self.lock.unlock()
                cont?.resume()
            }
        case "CHG":
            if let rawStatus = frame.parameters.first {
                let status = PresenceStatus(msnpPresenceCode: rawStatus)
                self.continuation?.yield(.presenceUpdated(status))
            }
        case "NLN", "ILN":
            if frame.parameters.count > 1 {
                let rawStatus = frame.parameters[0]
                let rawIdentity = frame.parameters[1]
                let status = PresenceStatus(msnpPresenceCode: rawStatus)
                let email = normalizeIdentity(rawIdentity)
                let name = frame.parameters.count > 2 ? frame.parameters[2] : email
                self.continuation?.yield(.contactPresenceChanged(email: email, status: status))
                self.onContactPresenceChanged?(Contact(id: email, nickname: name, email: email, presence: status), status)
            }
        case "FLN":
            if let raw = frame.parameters.first {
                let email = normalizeIdentity(raw)
                self.continuation?.yield(.contactPresenceChanged(email: email, status: .offline))
                self.onContactPresenceChanged?(Contact(id: email, nickname: nil, email: email, presence: .offline), .offline)
            }
        case "UBX":
            if let raw = frame.parameters.first {
                let email = normalizeIdentity(raw)
                let payloadText = frame.payload.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if let psm = SOAPXmlBuilder.extractTag(payloadText, tag: "PSM") {
                    let unescaped = SOAPXmlBuilder.unescapeXml(psm)
                    self.continuation?.yield(.contactPersonalMessageChanged(email: email, message: unescaped))
                } else if payloadText.contains("<PSM/>") || payloadText.contains("<PSM></PSM>") {
                    self.continuation?.yield(.contactPersonalMessageChanged(email: email, message: ""))
                }
            }
        case "RNG":
            // Wire: RNG <sessId> <host:port> CKI <key> <inviterEmail> <inviterDisplayName>
            // Parameters in nonTx: [sessId, host:port, "CKI", key, inviterEmail, ...]
            if frame.parameters.count >= 5 {
                let sessId = frame.parameters[0]
                let (h, p) = Self.parseEndpoint(frame.parameters[1], defaultPort: self.switchboardFallbackPort)
                let key = frame.parameters[3]
                let inviter = normalizeIdentity(frame.parameters[4])
                self.continuation?.yield(.switchboardInvitation(sessionId: sessId, host: h, port: p, authKey: key, inviter: inviter))
            }
        case "XFR":
            if frame.parameters.count >= 2 && frame.parameters[0] == "SB" {
                let trId = frame.transactionId ?? 0
                let (h, p) = Self.parseEndpoint(frame.parameters[1], defaultPort: self.switchboardFallbackPort)
                let authKey: String
                if let ckiIndex = frame.parameters.firstIndex(of: "CKI"), ckiIndex + 1 < frame.parameters.count {
                    authKey = frame.parameters[ckiIndex + 1]
                } else if frame.parameters.count > 2 {
                    authKey = frame.parameters[frame.parameters.count - 1]
                } else {
                    authKey = ""
                }

                let endpoint = SwitchboardEndpoint(host: h, port: p, authKey: authKey)
                self.lock.lock()
                let cont = self.pendingXfrRequests.removeValue(forKey: trId)
                    ?? self.pendingXfrRequests.removeValue(forKey: self.pendingXfrRequests.keys.first ?? -1)
                self.lock.unlock()

                cont?.resume(returning: endpoint)
            } else if frame.parameters.count >= 2 && frame.parameters[0] == "NS" {
                let (h, p) = Self.parseEndpoint(frame.parameters[1], defaultPort: 1863)
                self.lock.lock()
                self.lastRedirectEndpoint = (host: h, port: p)
                self.lock.unlock()
            }
        case "OUT":
            self.continuation?.yield(.disconnected(reason: .cleanSignOut))
        default:
            break
        }
    }

    private func sendRaw(_ string: String) async throws {
        guard let conn = connection else { throw NotificationServerError.unexpectedClosure }
        let data = Data(string.utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendTransaction(_ command: String, trId: Int) async throws -> MsnpFrame {
        try await withCheckedThrowingContinuation { continuation in
            self.lock.lock()
            self.pendingTransactionContinuations[trId] = continuation
            self.lock.unlock()

            Task {
                do {
                    try await self.sendRaw("\(command)\r\n")
                } catch {
                    self.lock.lock()
                    _ = self.pendingTransactionContinuations.removeValue(forKey: trId)
                    self.lock.unlock()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func sendVersionNegotiation() async throws {
        let trId = nextTransactionId()
        try await sendRaw("VER \(trId) MSNP18 CVR0\r\n")
    }

    public func sendClientInfo(email: String) async throws {
        let trId = nextTransactionId()
        try await sendRaw("CVR \(trId) 0x0409 winnt 6.1 i386 MSNMSGR 14.0.8117.0416 msmsgs \(email)\r\n")
    }

    public func sendSsoInitiate(email: String) async throws {
        let trId = nextTransactionId()
        try await sendRaw("USR \(trId) SSO I \(email)\r\n")
    }

    public func sendSsoComplete(ticket: String, proof: String, machineGuid: String = "{11111111-2222-3333-4444-555555555555}") async throws {
        let trId = nextTransactionId()
        try await sendRaw("USR \(trId) SSO S \(ticket) \(proof) \(machineGuid)\r\n")
    }

    public func sendEndpointCapabilities() async throws {
        let trId = nextTransactionId()
        let xml = "<EndpointData><Capabilities>2789003312:2609259408</Capabilities></EndpointData>"
        try await sendRaw("UUX \(trId) \(xml.utf8.count)\r\n\(xml)")
    }

    public func sendPrivateEndpointData(presence: PresenceStatus = .online, endpointName: String = "iPhone") async throws {
        let trId = nextTransactionId()
        let code = presence.msnpPresenceCode
        let xml = "<PrivateEndpointData><EpName>\(SOAPXmlBuilder.escapeXml(endpointName))</EpName><Idle>false</Idle><ClientType>1</ClientType><State>\(code)</State></PrivateEndpointData>"
        try await sendRaw("UUX \(trId) \(xml.utf8.count)\r\n\(xml)")
    }

    public func negotiate(email: String, maxRedirects: Int = 5) async throws -> SsoChallenge {
        var hops = 0
        while true {
            if hops >= maxRedirects {
                throw NotificationServerError.maxRedirectsExceeded
            }
            if !isConnected {
                try await connect()
            }

            let verTrId = nextTransactionId()
            let verFrame = try await sendTransaction("VER \(verTrId) MSNP18 CVR0", trId: verTrId)
            if verFrame.verb == "VER" && verFrame.parameters.contains("MSNP18") {
                self.negotiatedVersion = "MSNP18"
            }

            let cvrTrId = nextTransactionId()
            _ = try await sendTransaction("CVR \(cvrTrId) 0x0409 winnt 6.1 i386 MSNMSGR 14.0.8117.0416 msmsgs \(email)", trId: cvrTrId)

            let ssoTrId = nextTransactionId()
            let ssoResponse = try await sendTransaction("USR \(ssoTrId) SSO I \(email)", trId: ssoTrId)

            if ssoResponse.verb == "XFR" && ssoResponse.parameters.first == "NS" {
                hops += 1
                if hops >= maxRedirects {
                    throw NotificationServerError.maxRedirectsExceeded
                }
                let target = ssoResponse.parameters.count > 1 ? ssoResponse.parameters[1] : ""
                let (h, p) = Self.parseEndpoint(target, defaultPort: 1863)
                await disconnect()
                self.host = h
                self.port = p
                continue
            }

            if ssoResponse.verb == "USR" && ssoResponse.parameters.first == "SSO" && ssoResponse.parameters.dropFirst().first == "S" {
                let policy = ssoResponse.parameters.count > 2 ? ssoResponse.parameters[2] : "MBI_KEY_OLD"
                let nonce = ssoResponse.parameters.count > 3 ? ssoResponse.parameters[3] : ""
                return SsoChallenge(policy: policy, nonce: nonce)
            }

            if ssoResponse.verb == "911" {
                throw NotificationServerError.authenticationFailed(code: 911)
            }

            throw NotificationServerError.authenticationFailed(code: -1)
        }
    }

    public func negotiate(config: ServerConfig, email: String) async throws -> SsoChallenge {
        self.host = config.mainServer
        self.port = UInt16(config.mainPort)
        self.switchboardFallbackPort = UInt16(config.switchboardPort)
        return try await negotiate(email: email, maxRedirects: 5)
    }

    public func signIn(
        email: String,
        ticket: String,
        proof: String,
        machineGuid: String = "{11111111-2222-3333-4444-555555555555}"
    ) async throws {
        var hops = 0
        while true {
            if hops >= 5 {
                throw NotificationServerError.maxRedirectsExceeded
            }
            if !isConnected {
                try await connect()
            }

            let verTrId = nextTransactionId()
            let verFrame = try await sendTransaction("VER \(verTrId) MSNP18 CVR0", trId: verTrId)
            if verFrame.verb == "VER" && verFrame.parameters.contains("MSNP18") {
                self.negotiatedVersion = "MSNP18"
            }

            let cvrTrId = nextTransactionId()
            _ = try await sendTransaction("CVR \(cvrTrId) 0x0409 winnt 6.1 i386 MSNMSGR 14.0.8117.0416 msmsgs \(email)", trId: cvrTrId)

            let ssoTrId = nextTransactionId()
            let ssoResponse = try await sendTransaction("USR \(ssoTrId) SSO I \(email)", trId: ssoTrId)

            if ssoResponse.verb == "XFR" && ssoResponse.parameters.first == "NS" {
                hops += 1
                if hops >= 5 {
                    throw NotificationServerError.maxRedirectsExceeded
                }
                let target = ssoResponse.parameters.count > 1 ? ssoResponse.parameters[1] : ""
                let (h, p) = Self.parseEndpoint(target, defaultPort: 1863)
                await disconnect()
                self.host = h
                self.port = p
                continue
            }

            if ssoResponse.verb == "911" {
                throw NotificationServerError.authenticationFailed(code: 911)
            }

            let authTrId = nextTransactionId()
            let authResponse = try await sendTransaction("USR \(authTrId) SSO S \(ticket) \(proof) \(machineGuid)", trId: authTrId)

            if authResponse.verb == "USR" && authResponse.parameters.contains("OK") {
                let authedEmail = authResponse.parameters.count > 1 ? normalizeIdentity(authResponse.parameters[1]) : email
                self.continuation?.yield(.authenticated(email: authedEmail))
                return
            } else if authResponse.verb == "911" {
                throw NotificationServerError.authenticationFailed(code: 911)
            } else {
                throw NotificationServerError.authenticationFailed(code: -1)
            }
        }
    }

    public func finishSignIn(
        email: String,
        ticket: String,
        proof: String,
        machineGuid: String = "{11111111-2222-3333-4444-555555555555}"
    ) async throws {
        let authTrId = nextTransactionId()
        let authResponse = try await sendTransaction("USR \(authTrId) SSO S \(ticket) \(proof) \(machineGuid)", trId: authTrId)

        if authResponse.verb == "USR" && authResponse.parameters.contains("OK") {
            let authedEmail = authResponse.parameters.count > 1 ? normalizeIdentity(authResponse.parameters[1]) : email
            self.continuation?.yield(.authenticated(email: authedEmail))
            return
        } else if authResponse.verb == "911" {
            throw NotificationServerError.authenticationFailed(code: 911)
        } else {
            throw NotificationServerError.authenticationFailed(code: -1)
        }
    }

    /// Complete end-to-end MSNP18 authentication flow: negotiates SSO challenge with server, fetches tokens via Passport RST2, generates RPS proof, and completes sign-in.
    public func fullSignIn(
        email: String,
        password: String,
        config: ServerConfig,
        passportClient: PassportRST2Client,
        rpsGenerator: RPSProofGenerator,
        machineGuid: String = "{11111111-2222-3333-4444-555555555555}"
    ) async throws -> RST2SecurityTokens {
        let challenge = try await negotiate(config: config, email: email)
        let tokens = try await passportClient.authenticate(email: email, password: password, policy: challenge.policy)
        let proof = try rpsGenerator.generateProof(binarySecretBase64: tokens.binarySecretBase64, nonce: challenge.nonce)
        try await finishSignIn(email: email, ticket: tokens.messengerClearToken, proof: proof, machineGuid: machineGuid)
        return tokens
    }

    public func setPresence(_ status: PresenceStatus) async throws {
        let trId = nextTransactionId()
        let code = status.msnpPresenceCode
        try await sendRaw("CHG \(trId) \(code) 2789003312:2609259408 0\r\n")
    }

    public func setPersonalMessage(_ text: String) async throws {
        let trId = nextTransactionId()
        let escaped = SOAPXmlBuilder.escapeXml(text)
        let xml = "<Data><PSM>\(escaped)</PSM><CurrentMedia></CurrentMedia><MachineGuidName>{11111111-2222-3333-4444-555555555555}</MachineGuidName></Data>"
        try await sendRaw("UUX \(trId) \(xml.utf8.count)\r\n\(xml)")
        continuation?.yield(.personalMessageUpdated(text))
    }

    public func updateDisplayName(_ name: String) async throws {
        let trId = nextTransactionId()
        try await sendRaw("PRP \(trId) MFN \(name)\r\n")
    }

    public func requestSwitchboard(timeout: TimeInterval = 3.0) async throws -> SwitchboardEndpoint {
        guard isConnected else {
            throw NotificationServerError.unexpectedClosure
        }
        let trId = nextTransactionId()

        return try await withThrowingTaskGroup(of: SwitchboardEndpoint.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SwitchboardEndpoint, Error>) in
                        self.lock.lock()
                        self.pendingXfrRequests[trId] = continuation
                        self.lock.unlock()

                        Task {
                            do {
                                try await self.sendRaw("XFR \(trId) SB\r\n")
                            } catch {
                                self.lock.lock()
                                let cont = self.pendingXfrRequests.removeValue(forKey: trId)
                                self.lock.unlock()
                                cont?.resume(throwing: error)
                            }
                        }
                    }
                } onCancel: {
                    self.lock.lock()
                    _ = self.pendingXfrRequests.removeValue(forKey: trId)
                    self.lock.unlock()
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NotificationServerError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    public func syncAddressBook(contacts: [(email: String, flags: Int)], maxChunkSize: Int = 50) async throws {
        if contacts.isEmpty {
            let trId = nextTransactionId()
            let xml = "<ml l=\"1\"></ml>"
            try await sendAdlAndWait(trId: trId, xml: xml)
            return
        }

        let chunks = stride(from: 0, to: contacts.count, by: maxChunkSize).map {
            Array(contacts[$0..<min($0 + maxChunkSize, contacts.count)])
        }

        for chunk in chunks {
            let trId = nextTransactionId()
            var domainGroups: [String: [(account: String, flag: Int)]] = [:]
            for c in chunk {
                let parts = c.email.components(separatedBy: "@")
                let account = parts.first ?? ""
                let domain = parts.count > 1 ? parts[1] : "msngr.dev"
                domainGroups[domain, default: []].append((account: account, flag: c.flags))
            }

            var xml = "<ml l=\"1\">"
            for (domain, accounts) in domainGroups.sorted(by: { $0.key < $1.key }) {
                xml += "<d n=\"\(SOAPXmlBuilder.escapeXml(domain))\">"
                for a in accounts {
                    xml += "<c n=\"\(SOAPXmlBuilder.escapeXml(a.account))\" l=\"\(a.flag)\" t=\"1\"/>"
                }
                xml += "</d>"
            }
            xml += "</ml>"
            try await sendAdlAndWait(trId: trId, xml: xml)
        }
    }

    private func sendAdlAndWait(trId: Int, xml: String) async throws {
        let frame = try await sendTransaction("ADL \(trId) \(xml.utf8.count)\r\n\(xml)", trId: trId)
        if frame.verb == "241" {
            throw NotificationServerError.synchronizationFailed(code: 241)
        }
    }

    public func sendPing() async throws {
        let trId = nextTransactionId()
        try await sendRaw("PNG\r\n")
    }

    public func signOut() async throws {
        try await sendRaw("OUT\r\n")
        await disconnect()
    }
}
