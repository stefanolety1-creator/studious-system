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
    func connect() async throws
    func signIn(email: String, ticket: String, proof: String, machineGuid: String) async throws
    func setPresence(_ status: PresenceStatus) async throws
    func setPersonalMessage(_ text: String) async throws
    func updateDisplayName(_ name: String) async throws
    func requestSwitchboard(timeout: TimeInterval) async throws -> SwitchboardEndpoint
    func disconnect() async
}

/// Production and mock-compatible MSNP18 Notification Server TCP client using `NWConnection`.
public final class NotificationServerClient: NotificationServerClientProtocol, @unchecked Sendable {
    public var host: String
    public var port: UInt16?

    private var connection: NWConnection?
    private let lock = NSLock()
    private var transactionCounter = 0
    private var continuation: AsyncStream<MsnpServerEvent>.Continuation?
    public let events: AsyncStream<MsnpServerEvent>

    private var negotiatedVersion: String?
    public private(set) var isConnected: Bool = false
    private var lastRedirectEndpoint: (host: String, port: UInt16)?
    private var pendingXfrRequests: [Int: CheckedContinuation<SwitchboardEndpoint, Error>] = [:]
    private var pendingSsoRequests: [Int: CheckedContinuation<Void, Error>] = [:]
    private var pendingAdlRequests: [Int: CheckedContinuation<Void, Error>] = [:]

    public init(host: String = "127.0.0.1", port: UInt16? = nil) {
        self.host = host
        self.port = port
        var cont: AsyncStream<MsnpServerEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
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
        let xfrs = pendingXfrRequests
        pendingXfrRequests.removeAll()
        let ssos = pendingSsoRequests
        pendingSsoRequests.removeAll()
        let adls = pendingAdlRequests
        pendingAdlRequests.removeAll()
        lock.unlock()

        for (_, cont) in xfrs { cont.resume(throwing: error) }
        for (_, cont) in ssos { cont.resume(throwing: error) }
        for (_, cont) in adls { cont.resume(throwing: error) }
    }

    private func startReceiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.processIncomingBytes(data)
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

    private func processIncomingBytes(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\r\n")

        for line in lines where !line.isEmpty {
            let tokens = line.components(separatedBy: " ").filter { !$0.isEmpty }
            guard let verb = tokens.first else { continue }

            switch verb {
            case "VER":
                if tokens.count > 2 {
                    self.negotiatedVersion = tokens[2]
                }
            case "CVR":
                break
            case "USR":
                if tokens.contains("OK") {
                    let email = tokens.count > 3 ? tokens[3] : "mock-user@example.com"
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
                if tokens.contains("OK") {
                    let trId = tokens.count > 1 ? (Int(tokens[1]) ?? 0) : 0
                    self.lock.lock()
                    let cont = self.pendingAdlRequests.removeValue(forKey: trId)
                        ?? self.pendingAdlRequests.removeValue(forKey: self.pendingAdlRequests.keys.first ?? -1)
                    self.lock.unlock()
                    cont?.resume()
                }
            case "CHG":
                if tokens.count > 2 {
                    let rawStatus = tokens[2]
                    let status = PresenceStatus(msnpPresenceCode: rawStatus)
                    self.continuation?.yield(.presenceUpdated(status))
                }
            case "NLN", "ILN":
                if tokens.count > 2 {
                    let rawStatus = tokens[1]
                    let email = tokens.count > 3 ? tokens[2].replacingOccurrences(of: "1:", with: "") : ""
                    self.continuation?.yield(.contactPresenceChanged(email: email, status: PresenceStatus(msnpPresenceCode: rawStatus)))
                }
            case "FLN":
                if tokens.count > 1 {
                    let email = tokens[1].replacingOccurrences(of: "1:", with: "")
                    self.continuation?.yield(.contactPresenceChanged(email: email, status: .offline))
                }
            case "UBX":
                if tokens.count > 1 {
                    let email = tokens[1].replacingOccurrences(of: "1:", with: "")
                    if let psm = SOAPXmlBuilder.extractTag(text, tag: "PSM") {
                        let unescaped = SOAPXmlBuilder.unescapeXml(psm)
                        self.continuation?.yield(.contactPersonalMessageChanged(email: email, message: unescaped))
                    }
                }
            case "RNG":
                if tokens.count >= 6 {
                    let sessId = tokens[1]
                    let hostPort = tokens[2].components(separatedBy: ":")
                    let h = hostPort.first ?? "127.0.0.1"
                    let p = UInt16(hostPort.last ?? "1864") ?? 1864
                    let key = tokens[4]
                    let inviter = tokens[5]
                    self.continuation?.yield(.switchboardInvitation(sessionId: sessId, host: h, port: p, authKey: key, inviter: inviter))
                }
            case "XFR":
                if tokens.count >= 4 && tokens[2] == "SB" {
                    let trId = Int(tokens[1]) ?? 0
                    let hostPort = tokens[3].components(separatedBy: ":")
                    let h = hostPort.first ?? "127.0.0.1"
                    let p = UInt16(hostPort.last ?? "1864") ?? 1864

                    let authKey: String
                    if let ckiIndex = tokens.firstIndex(of: "CKI"), ckiIndex + 1 < tokens.count {
                        authKey = tokens[ckiIndex + 1]
                    } else if tokens.count > 4 {
                        authKey = tokens[tokens.count - 1]
                    } else {
                        authKey = ""
                    }

                    let endpoint = SwitchboardEndpoint(host: h, port: p, authKey: authKey)

                    self.lock.lock()
                    let cont = self.pendingXfrRequests.removeValue(forKey: trId)
                        ?? self.pendingXfrRequests.removeValue(forKey: self.pendingXfrRequests.keys.first ?? -1)
                    self.lock.unlock()

                    cont?.resume(returning: endpoint)
                } else if tokens.count >= 4 && tokens[2] == "NS" {
                    let hostPort = tokens[3].components(separatedBy: ":")
                    let h = hostPort.first ?? "127.0.0.1"
                    let p = UInt16(hostPort.last ?? "1864") ?? 1864
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

    public func signIn(
        email: String,
        ticket: String,
        proof: String,
        machineGuid: String = "{11111111-2222-3333-4444-555555555555}"
    ) async throws {
        var hops = 0
        while true {
            if hops >= 3 {
                throw NotificationServerError.maxRedirectsExceeded
            }
            try await sendVersionNegotiation()
            try await sendClientInfo(email: email)

            self.lock.lock()
            self.lastRedirectEndpoint = nil
            self.lock.unlock()

            let ssoTrId = nextTransactionId()
            try await sendRaw("USR \(ssoTrId) SSO I \(email)\r\n")

            try await Task.sleep(nanoseconds: 40_000_000)

            self.lock.lock()
            let redirect = self.lastRedirectEndpoint
            self.lock.unlock()

            if let redirect = redirect {
                hops += 1
                if hops >= 3 {
                    throw NotificationServerError.maxRedirectsExceeded
                }
                await disconnect()
                self.host = redirect.host
                self.port = redirect.port
                try await connect()
                continue
            }

            let authTrId = nextTransactionId()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.lock.lock()
                self.pendingSsoRequests[authTrId] = continuation
                self.lock.unlock()

                Task {
                    do {
                        try await self.sendRaw("USR \(authTrId) SSO S \(ticket) \(proof) \(machineGuid)\r\n")
                    } catch {
                        self.lock.lock()
                        _ = self.pendingSsoRequests.removeValue(forKey: authTrId)
                        self.lock.unlock()
                        continuation.resume(throwing: error)
                    }
                }
            }
            return
        }
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

    public func syncAddressBook(contacts: [(email: String, flags: Int)], maxChunkSize: Int = 150) async throws {
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
                xml += "<d n=\"\(domain)\">"
                for a in accounts {
                    xml += "<c n=\"\(a.account)\" l=\"\(a.flag)\" t=\"1\"/>"
                }
                xml += "</d>"
            }
            xml += "</ml>"
            try await sendAdlAndWait(trId: trId, xml: xml)
        }
    }

    private func sendAdlAndWait(trId: Int, xml: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.lock.lock()
            self.pendingAdlRequests[trId] = continuation
            self.lock.unlock()

            Task {
                do {
                    try await self.sendRaw("ADL \(trId) \(xml.utf8.count)\r\n\(xml)")
                } catch {
                    self.lock.lock()
                    _ = self.pendingAdlRequests.removeValue(forKey: trId)
                    self.lock.unlock()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func sendPing() async throws {
        try await sendRaw("PNG\r\n")
    }

    public func signOut() async throws {
        try await sendRaw("OUT\r\n")
        await disconnect()
    }
}
