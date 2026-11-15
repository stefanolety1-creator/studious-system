import Foundation
import Network
import MsngrCore

/// Protocol for managing an MSNP18 Switchboard 1:1 or multi-user chat session.
public protocol SwitchboardSessionProtocol: Sendable {
    var events: AsyncStream<SwitchboardEvent> { get }
    func connect(authKey: String, userEmail: String, machineGuid: String) async throws
    func invite(peerEmail: String) async throws
    func answer(authKey: String, sessionId: String, userEmail: String, machineGuid: String) async throws
    func sendMessage(_ text: String, ackMode: SwitchboardAckMode, fontName: String, colorHex: String) async throws
    func sendTyping(userEmail: String) async throws
    func sendNudge() async throws
    func disconnect() async
}

/// Manages a live MSNP18 Switchboard TCP session for instant messaging, typing notifications, nudges, and games.
public final class SwitchboardSession: SwitchboardSessionProtocol, @unchecked Sendable {
    public let host: String
    public var port: UInt16?

    private var connection: NWConnection?
    private let lock = NSLock()
    private var transactionCounter = 0
    private var continuation: AsyncStream<SwitchboardEvent>.Continuation?
    public let events: AsyncStream<SwitchboardEvent>

    private var lastNudgeTime: Date?
    private var lastTypingTime: Date?
    public private(set) var activeRoster: [String] = []
    public private(set) var isConnected: Bool = false
    private var pendingCalRequests: [Int: CheckedContinuation<Void, Error>] = [:]
    private var pendingMsgRequests: [Int: CheckedContinuation<Void, Error>] = [:]

    public init(host: String = "127.0.0.1", port: UInt16? = nil) {
        self.host = host
        self.port = port
        var cont: AsyncStream<SwitchboardEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    public func nextTransactionId() -> Int {
        lock.lock()
        defer { lock.unlock() }
        transactionCounter += 1
        return transactionCounter
    }

    public func connect(
        authKey: String,
        userEmail: String,
        machineGuid: String = "{11111111-2222-3333-4444-555555555555}"
    ) async throws {
        guard let p = port else { throw SwitchboardError.connectionTimeout }
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
                        self.failAllPending(error: err)
                        continuation.resume(throwing: err)
                    } else {
                        cLock.unlock()
                    }
                case .cancelled:
                    self.isConnected = false
                    self.continuation?.yield(.sessionEnded(reason: .socketReset))
                    self.failAllPending(error: SwitchboardError.socketReset)
                default:
                    break
                }
            }
            let queue = DispatchQueue(label: "com.msngr.sb.client.\(UUID().uuidString)")
            conn.start(queue: queue)
        }

        startReceiveLoop()

        let trId = nextTransactionId()
        try await sendRaw("USR \(trId) \(userEmail);\(machineGuid) \(authKey)\r\n")
    }

    private func failAllPending(error: Error) {
        lock.lock()
        let cals = pendingCalRequests
        pendingCalRequests.removeAll()
        let msgs = pendingMsgRequests
        pendingMsgRequests.removeAll()
        lock.unlock()

        for (_, cont) in cals { cont.resume(throwing: error) }
        for (_, cont) in msgs { cont.resume(throwing: error) }
    }

    public func invite(peerEmail: String) async throws {
        let trId = nextTransactionId()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.lock.lock()
            self.pendingCalRequests[trId] = cont
            self.lock.unlock()

            Task {
                do {
                    try await self.sendRaw("CAL \(trId) \(peerEmail)\r\n")
                } catch {
                    self.lock.lock()
                    _ = self.pendingCalRequests.removeValue(forKey: trId)
                    self.lock.unlock()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func answer(
        authKey: String,
        sessionId: String,
        userEmail: String,
        machineGuid: String = "{11111111-2222-3333-4444-555555555555}"
    ) async throws {
        let trId = nextTransactionId()
        try await sendRaw("ANS \(trId) \(userEmail);\(machineGuid) \(authKey) \(sessionId)\r\n")
    }

    public func sendMessage(
        _ text: String,
        ackMode: SwitchboardAckMode = .acknowledged,
        fontName: String = "Segoe UI",
        colorHex: String = "0"
    ) async throws {
        guard !text.isEmpty else {
            throw SwitchboardError.emptyMessage
        }
        guard text.utf8.count <= 1202 else {
            throw SwitchboardError.messageExceedsMaxLength
        }

        let trId = nextTransactionId()
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nX-MMS-IM-Format: FN=\(fontName); EF=; CO=\(colorHex); CS=0; PF=00\r\n\r\n\(text)"
        let length = mime.utf8.count

        if ackMode == .acknowledged {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.lock.lock()
                self.pendingMsgRequests[trId] = cont
                self.lock.unlock()

                Task {
                    do {
                        try await self.sendRaw("MSG \(trId) \(ackMode.rawValue) \(length)\r\n\(mime)")
                    } catch {
                        self.lock.lock()
                        _ = self.pendingMsgRequests.removeValue(forKey: trId)
                        self.lock.unlock()
                        cont.resume(throwing: error)
                    }
                }
            }
        } else {
            try await sendRaw("MSG \(trId) \(ackMode.rawValue) \(length)\r\n\(mime)")
        }
    }

    public func sendTyping(userEmail: String = "user@msngr.dev") async throws {
        lock.lock()
        if let last = lastTypingTime, Date().timeIntervalSince(last) < 0.5 {
            lock.unlock()
            return
        }
        lastTypingTime = Date()
        lock.unlock()

        let trId = nextTransactionId()
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\nTypingUser: \(userEmail)\r\n\r\n\r\n"
        try await sendRaw("MSG \(trId) U \(mime.utf8.count)\r\n\(mime)")
    }

    public func sendNudge() async throws {
        lock.lock()
        if let last = lastNudgeTime, Date().timeIntervalSince(last) < 2.0 {
            lock.unlock()
            throw NudgeError.cooldownActive
        }
        lastNudgeTime = Date()
        lock.unlock()

        let trId = nextTransactionId()
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msnmsgr-datacast\r\n\r\nID: 1\r\n"
        try await sendRaw("MSG \(trId) N \(mime.utf8.count)\r\n\(mime)")
    }

    public func sendGameMove(slot: Int) async throws {
        guard (0...8).contains(slot) else { return }
        try await sendMessage("[GAME:TTT:MOVE:\(slot)]", ackMode: .unacknowledged)
    }

    public func disconnect() async {
        try? await sendRaw("BYE\r\n")
        connection?.cancel()
        connection = nil
        isConnected = false
        failAllPending(error: SwitchboardError.socketReset)
    }

    private func sendRaw(_ string: String) async throws {
        guard let conn = connection else { throw SwitchboardError.socketReset }
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
                self.continuation?.yield(.sessionEnded(reason: .socketReset))
                self.failAllPending(error: SwitchboardError.socketReset)
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
            case "CAL":
                if tokens.count > 1, let trId = Int(tokens[1]) {
                    self.lock.lock()
                    let cont = self.pendingCalRequests.removeValue(forKey: trId)
                    self.lock.unlock()
                    cont?.resume()
                }
            case "217":
                let trId = tokens.count > 1 ? (Int(tokens[1]) ?? 0) : 0
                self.lock.lock()
                let cont = self.pendingCalRequests.removeValue(forKey: trId)
                    ?? self.pendingCalRequests.removeValue(forKey: self.pendingCalRequests.keys.first ?? -1)
                self.lock.unlock()
                cont?.resume(throwing: SwitchboardError.peerOffline(code: 217))
            case "ACK":
                if tokens.count > 1, let trId = Int(tokens[1]) {
                    self.lock.lock()
                    let cont = self.pendingMsgRequests.removeValue(forKey: trId)
                    self.lock.unlock()
                    cont?.resume()
                }
            case "NAK":
                let trId = tokens.count > 1 ? (Int(tokens[1]) ?? 0) : 0
                self.lock.lock()
                let cont = self.pendingMsgRequests.removeValue(forKey: trId)
                    ?? self.pendingMsgRequests.removeValue(forKey: self.pendingMsgRequests.keys.first ?? -1)
                self.lock.unlock()
                cont?.resume(throwing: SwitchboardError.messageDeliveryFailed(trId: trId))
            case "JOI", "IRO":
                if tokens.count > 1 {
                    let emailGuid = tokens[1].components(separatedBy: ";")
                    let email = emailGuid.first ?? tokens[1]
                    let name = tokens.count > 2 ? tokens[2] : email
                    self.activeRoster.append(email)
                    self.continuation?.yield(.userJoined(email: email, displayName: name))
                }
            case "BYE":
                if tokens.count > 1 {
                    let emailGuid = tokens[1].components(separatedBy: ";")
                    let email = emailGuid.first ?? tokens[1]
                    self.activeRoster.removeAll(where: { $0 == email })
                    self.continuation?.yield(.userLeft(email: email))
                }
            case "MSG":
                if text.contains("text/x-msmsgscontrol") {
                    if let user = extractHeader(text, header: "TypingUser") {
                        self.continuation?.yield(.typingReceived(email: user))
                    }
                } else if text.contains("text/x-msnmsgr-datacast") && text.contains("ID: 1") {
                    let sender = tokens.count > 1 ? tokens[1] : "peer@msngr.dev"
                    self.continuation?.yield(.nudgeReceived(email: sender))
                } else if text.contains("text/plain") {
                    let sender = tokens.count > 1 ? tokens[1] : "peer@msngr.dev"
                    let body = extractMimeBody(text)
                    let styled = MessengerPlusParser.parseToAttributedString(body)
                    let chatMsg = ChatMessage(
                        sender: sender,
                        text: body,
                        formattedText: styled,
                        messageType: .text
                    )
                    self.continuation?.yield(.messageReceived(chatMsg))
                }
            default:
                break
            }
        }
    }

    private func extractHeader(_ text: String, header: String) -> String? {
        for line in text.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix(header.lowercased() + ":") {
                let parts = line.components(separatedBy: ":")
                return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractMimeBody(_ text: String) -> String {
        let parts = text.components(separatedBy: "\r\n\r\n")
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}
