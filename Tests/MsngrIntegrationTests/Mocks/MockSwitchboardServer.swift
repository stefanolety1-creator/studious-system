//
// MockSwitchboardServer.swift
// MsngrIntegrationTests
//
// Local TCP server emulating an MSNP18 Switchboard (SB) session using Apple's NWListener.
// Handles authentication handshakes, CAL calling flow, JOI join announcements,
// MSG routing with ACK responses, typing indicators, nudges, and BYE teardown.
//

import Foundation
import Network

/// Local TCP server emulating an MSNP18 Switchboard (SB) session using Apple's NWListener.
public actor MockSwitchboardServer {
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var decoders: [ObjectIdentifier: MockMsnpIncrementalDecoder] = [:]

    public private(set) var port: UInt16?
    public private(set) var recordedCommands: [MockMsnpCommand] = []
    public private(set) var recordedMessages: [MockSwitchboardMime] = []

    // Configurable parameters
    public var sessionId: String = "1001"
    public var peerEmail: String = "selin@msngr.dev"
    public var peerDisplayName: String = "Selin"
    public var peerEndpointGuid: String = "11111111-2222-3333-4444-555555555555"
    public var autoSimulatePeerJoin: Bool = true
    public var autoReplyHandler: (@Sendable (String) -> String?)?
    public var nextCalError: Int? = nil
    public var nextMsgError: Bool = false

    public func setNextCalError(code: Int) {
        self.nextCalError = code
    }

    public func setNextMsgErrorNak() {
        self.nextMsgError = true
    }

    public init() {}

    // MARK: - Server Lifecycle

    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwListener = try NWListener(using: params, on: .any)
        self.listener = nwListener

        let queue = DispatchQueue(label: "com.msngr.mock.sb.\(UUID().uuidString)")

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let allocatedPort = nwListener.port?.rawValue {
                        Task {
                            await self.setPort(allocatedPort)
                            lock.lock()
                            if !resumed {
                                resumed = true
                                lock.unlock()
                                continuation.resume(returning: allocatedPort)
                            } else {
                                lock.unlock()
                            }
                        }
                    }
                case .failed(let error):
                    lock.lock()
                    if !resumed {
                        resumed = true
                        lock.unlock()
                        continuation.resume(throwing: error)
                    } else {
                        lock.unlock()
                    }
                case .cancelled:
                    lock.lock()
                    if !resumed {
                        resumed = true
                        lock.unlock()
                        continuation.resume(throwing: URLError(.cancelled))
                    } else {
                        lock.unlock()
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                Task {
                    await self.handleNewConnection(connection, queue: queue)
                }
            }

            nwListener.start(queue: queue)
        }
    }

    public func stop() {
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        decoders.removeAll()
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func setPort(_ port: UInt16) {
        self.port = port
    }

    // MARK: - Connection Management

    private func handleNewConnection(_ connection: NWConnection, queue: DispatchQueue) {
        activeConnections.append(connection)
        let id = ObjectIdentifier(connection)
        decoders[id] = MockMsnpIncrementalDecoder()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .cancelled = state, case .failed = state {
                Task { await self.removeConnection(connection) }
            }
        }

        connection.start(queue: queue)
        receiveLoop(on: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll(where: { $0 === connection })
        decoders.removeValue(forKey: ObjectIdentifier(connection))
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                Task {
                    await self.processIncomingBytes(data, from: connection)
                }
            }
            if isComplete || error != nil {
                Task {
                    await self.removeConnection(connection)
                }
            } else {
                Task {
                    await self.receiveLoop(on: connection)
                }
            }
        }
    }

    // MARK: - Command Processing

    private func processIncomingBytes(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard let decoder = decoders[id] else { return }

        let commands = decoder.feed(data)
        for cmd in commands {
            recordedCommands.append(cmd)
            handleCommand(cmd, on: connection)
        }
    }

    private func handleCommand(_ command: MockMsnpCommand, on connection: NWConnection) {
        let trId = command.transactionId.map { String($0) } ?? "0"

        switch command.verb {
        case "USR":
            let identity = command.parameters.first ?? "user@example.com"
            send("USR \(trId) OK \(identity) LocalUser\r\n", on: connection)

        case "ANS":
            send("ANS \(trId) OK\r\n", on: connection)

        case "CAL":
            if let calErr = nextCalError {
                nextCalError = nil
                send("\(calErr) \(trId)\r\n", on: connection)
                return
            }
            let targetEmail = command.parameters.first ?? ""
            send("CAL \(trId) RINGING \(sessionId)\r\n", on: connection)

            // Automatically simulate peer participant join when remote peer is invited
            if autoSimulatePeerJoin && !targetEmail.localizedCaseInsensitiveContains("mock-user") {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                    await self.simulatePeerJoin(email: peerEmail, displayName: peerDisplayName)
                }
            }

        case "MSG":
            if nextMsgError {
                nextMsgError = false
                send("NAK \(trId)\r\n", on: connection)
                return
            }
            let ackMode = command.parameters.first ?? "A"
            if ackMode == "A" {
                send("ACK \(trId)\r\n", on: connection)
            }

            if let payload = command.payload {
                let parsedMime = parseMime(payload: payload)
                recordedMessages.append(parsedMime)

                // Handle optional auto-reply for text messages
                if case .text(let text, _) = parsedMime, let replyGenerator = autoReplyHandler {
                    if let replyText = replyGenerator(text) {
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            await self.sendIncomingTextMessage(text: replyText)
                        }
                    }
                }
            }

        case "BYE":
            connection.cancel()

        default:
            break
        }
    }

    // MARK: - Simulation & Injection APIs

    public func simulatePeerJoin(email: String, displayName: String) {
        broadcast("JOI \(email);{\(peerEndpointGuid)} \(displayName) 2789003312:2609259408\r\n")
    }

    public func simulatePeerLeave(email: String) {
        broadcast("BYE \(email);{\(peerEndpointGuid)}\r\n")
    }

    public func sendIncomingTextMessage(text: String, formatHeader: String? = nil) {
        let format = formatHeader ?? "FN=Segoe%20UI; EF=; CO=0; CS=0; PF=0"
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nX-MMS-IM-Format: \(format)\r\n\r\n\(text)"
        let length = mime.utf8.count
        broadcast("MSG \(peerEmail);{\(peerEndpointGuid)} \(peerDisplayName) \(length)\r\n\(mime)")
    }

    public func sendIncomingTyping() {
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\nTypingUser: \(peerEmail)\r\n\r\n\r\n"
        let length = mime.utf8.count
        broadcast("MSG \(peerEmail);{\(peerEndpointGuid)} \(peerDisplayName) \(length)\r\n\(mime)")
    }

    public func sendIncomingNudge() {
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msnmsgr-datacast\r\n\r\nID: 1\r\n"
        let length = mime.utf8.count
        broadcast("MSG \(peerEmail);{\(peerEndpointGuid)} \(peerDisplayName) \(length)\r\n\(mime)")
    }

    // MARK: - MIME Parser Helper

    private func parseMime(payload: Data) -> MockSwitchboardMime {
        let crlfCrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let lfLf = Data([0x0A, 0x0A])

        let delimRange = payload.range(of: crlfCrlf) ?? payload.range(of: lfLf)
        guard let delim = delimRange else {
            return .unsupported(contentType: "unknown", rawData: payload)
        }

        let headerData = payload.subdata(in: 0..<delim.lowerBound)
        let bodyData = payload.subdata(in: delim.upperBound..<payload.count)

        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        var headers: [String: String] = [:]
        headerString.enumerateLines { line, _ in
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let contentType = headers["content-type"]?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""

        switch contentType {
        case "text/plain":
            return .text(value: bodyString, formatHeader: headers["x-mms-im-format"])
        case "text/x-msmsgscontrol":
            return .typing(user: headers["typinguser"] ?? "")
        case "text/x-msnmsgr-datacast":
            if bodyString.contains("ID: 1") {
                return .nudge
            }
            return .datacast(body: bodyString)
        default:
            return .unsupported(contentType: contentType, rawData: bodyData)
        }
    }

    // MARK: - Raw Stream Senders

    private func send(_ string: String, on connection: NWConnection) {
        let data = Data(string.utf8)
        connection.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func broadcast(_ string: String) {
        let data = Data(string.utf8)
        for connection in activeConnections {
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    // MARK: - Query & Test Helper APIs

    public func getRecordedMessages() -> [MockSwitchboardMime] {
        return recordedMessages
    }

    public func getRecordedCommands() -> [MockMsnpCommand] {
        return recordedCommands
    }

    public func clear() {
        recordedCommands.removeAll()
        recordedMessages.removeAll()
    }

    public func waitForCommand(verb: String, timeoutSeconds: Double = 2.0) async -> MockMsnpCommand? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let cmd = recordedCommands.first(where: { $0.verb == verb }) {
                return cmd
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        return recordedCommands.first(where: { $0.verb == verb })
    }

    public func waitForMessage(timeoutSeconds: Double = 2.0) async -> MockSwitchboardMime? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let msg = recordedMessages.last {
                return msg
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        return recordedMessages.last
    }
}

// MARK: - Switchboard MIME Types

public enum MockSwitchboardMime: Sendable, Equatable {
    case text(value: String, formatHeader: String?)
    case typing(user: String)
    case nudge
    case datacast(body: String)
    case unsupported(contentType: String, rawData: Data)
}
