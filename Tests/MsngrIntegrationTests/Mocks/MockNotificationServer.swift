//
// MockNotificationServer.swift
// MsngrIntegrationTests
//
// Local TCP server emulating the MSNP18 Notification Server (NS) using Apple's NWListener.
// Handles authentication handshakes, ADL roster synchronization, presence, and Switchboard routing.
//

import Foundation
import Network

/// Local TCP server emulating the MSNP18 Notification Server (NS) using Apple's NWListener.
public actor MockNotificationServer {
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var decoders: [ObjectIdentifier: MockMsnpIncrementalDecoder] = [:]

    public private(set) var port: UInt16?
    public private(set) var recordedCommands: [MockMsnpCommand] = []

    // Configurable parameters
    public var switchboardPort: UInt16?
    public var handshakePolicy: String = "MBI_KEY_OLD"
    public var handshakeNonce: String = "mock-nonce-12345678"
    public var redirectEndpoint: (host: String, port: UInt16)?
    public var failNextChg: Bool = false
    public var failSsoWith911: Bool = false
    public var failAdlWith241: Bool = false
    public var sessionUserEmail: String = "mock-user@example.com"

    public func setSessionUserEmail(_ email: String) {
        self.sessionUserEmail = email
    }

    public func setFailSsoWith911(_ fail: Bool) {
        self.failSsoWith911 = fail
    }

    public func setFailAdlWith241(_ fail: Bool) {
        self.failAdlWith241 = fail
    }

    public func setRedirectEndpoint(host: String, port: UInt16) {
        self.redirectEndpoint = (host: host, port: port)
    }

    public func setSwitchboardPort(_ port: UInt16) {
        self.switchboardPort = port
    }

    public init() {}

    // MARK: - Server Lifecycle

    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwListener = try NWListener(using: params, on: .any)
        self.listener = nwListener

        let queue = DispatchQueue(label: "com.msngr.mock.ns.\(UUID().uuidString)")

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
        sessionUserEmail = "mock-user@example.com"
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
        case "VER":
            send("VER \(trId) MSNP18 CVR0\r\n", on: connection)

        case "CVR":
            send("CVR \(trId) 14.0.8117.0416 14.0.8117.0416 14.0.8117.0416 http://msgr.dlservice.microsoft.com http://messenger.live.com\r\n", on: connection)

        case "USR":
            if command.parameters.first == "SSO" && command.parameters.dropFirst().first == "I" {
                if let email = command.parameters.dropFirst(2).first {
                    self.sessionUserEmail = email
                }
                if let redirect = redirectEndpoint {
                    send("XFR \(trId) NS \(redirect.host):\(redirect.port) 0 \(redirect.host):\(redirect.port)\r\n", on: connection)
                } else {
                    send("USR \(trId) SSO S \(handshakePolicy) \(handshakeNonce)\r\n", on: connection)
                }
            } else if command.parameters.first == "SSO" && command.parameters.dropFirst().first == "S" {
                // USR <trId> SSO S <ticket> <proof> {machineGuid}
                if failSsoWith911 {
                    send("911 \(trId)\r\n", on: connection)
                } else {
                    send("USR \(trId) OK \(self.sessionUserEmail) 1 0\r\n", on: connection)
                }
            }

        case "ADL":
            if failAdlWith241 {
                send("241 \(trId)\r\n", on: connection)
            } else {
                send("ADL \(trId) OK\r\n", on: connection)
            }

        case "RML":
            send("RML \(trId) OK\r\n", on: connection)

        case "UUX":
            send("UUX \(trId) 0\r\n", on: connection)

        case "CHG":
            if failNextChg {
                failNextChg = false
                connection.cancel()
            } else {
                let state = command.parameters.first ?? "NLN"
                let caps = command.parameters.dropFirst().first ?? "2789003312:2609259408"
                let pic = command.parameters.dropFirst(2).first ?? "0"
                send("CHG \(trId) \(state) \(caps) \(pic)\r\n", on: connection)
            }

        case "PRP":
            if command.parameters.first == "MFN" {
                let nick = command.parameters.dropFirst().first ?? "MockProfile"
                send("PRP \(trId) MFN \(nick)\r\n", on: connection)
            }

        case "PNG":
            send("QNG 45\r\n", on: connection)

        case "XFR":
            if command.parameters.first == "SB" {
                let sbPort = switchboardPort ?? 1864
                send("XFR \(trId) SB 127.0.0.1:\(sbPort) CKI mock-cki-key-12345\r\n", on: connection)
            }

        case "OUT":
            connection.cancel()

        default:
            break
        }
    }

    // MARK: - Server-Initiated Event Injection

    public func sendInboundPresence(contactEmail: String, status: String = "NLN", displayName: String = "Friend") {
        broadcast("NLN \(status) 1:\(contactEmail) \(displayName) 2789003312:2609259408 0\r\n")
    }

    public func sendInboundInitialPresence(contactEmail: String, status: String = "NLN", displayName: String = "Friend") {
        broadcast("ILN 0 \(status) 1:\(contactEmail) 1 \(displayName) 2789003312:2609259408 0\r\n")
    }

    public func sendInboundOfflinePresence(contactEmail: String) {
        broadcast("FLN 1:\(contactEmail)\r\n")
    }

    public func sendInboundPersonalMessage(contactEmail: String, statusMessage: String) {
        let xml = "<Data><PSM>\(statusMessage)</PSM><CurrentMedia></CurrentMedia></Data>"
        let line = "UBX 1:\(contactEmail) \(xml.utf8.count)\r\n\(xml)"
        broadcast(line)
    }

    public func sendInboundRNG(sessionId: String, port: UInt16, authKey: String, inviterEmail: String, inviterName: String) {
        broadcast("RNG \(sessionId) 127.0.0.1:\(port) CKI \(authKey) \(inviterEmail) \(inviterName)\r\n")
    }

    public func sendInboundSignOut(reason: String = "OTH") {
        broadcast("OUT \(reason)\r\n")
    }

    // MARK: - Query & Test Helper APIs

    public func getRecordedCommands() -> [MockMsnpCommand] {
        return recordedCommands
    }

    public func clearRecordedCommands() {
        recordedCommands.removeAll()
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
}

// MARK: - Supporting Protocol Framing Codec

public struct MockMsnpCommand: Sendable, Equatable {
    public let verb: String
    public let transactionId: Int?
    public let parameters: [String]
    public let payload: Data?

    public init(verb: String, transactionId: Int? = nil, parameters: [String] = [], payload: Data? = nil) {
        self.verb = verb
        self.transactionId = transactionId
        self.parameters = parameters
        self.payload = payload
    }
}

public final class MockMsnpIncrementalDecoder: @unchecked Sendable {
    private var buffer = Data()
    private var pendingCommand: (command: MockMsnpCommand, payloadLength: Int)?

    private static let nonTransactionalVerbs: Set<String> = ["RNG", "NOT", "QNG"]
    private static let payloadVerbs: Set<String> = [
        "MSG", "UUM", "UBM", "UUX", "UBX", "UBN", "ADL", "RML", "NOT", "GCF", "SDG", "NFY", "PUT"
    ]
    private static let crlf = Data([0x0D, 0x0A])

    public init() {}

    public func feed(_ bytes: Data) -> [MockMsnpCommand] {
        buffer.append(bytes)
        var commands: [MockMsnpCommand] = []

        while true {
            if let pending = pendingCommand {
                if buffer.count < pending.payloadLength {
                    break // Await more payload bytes
                }
                let payload = buffer.subdata(in: 0..<pending.payloadLength)
                buffer.removeSubrange(0..<pending.payloadLength)
                commands.append(MockMsnpCommand(
                    verb: pending.command.verb,
                    transactionId: pending.command.transactionId,
                    parameters: pending.command.parameters,
                    payload: payload
                ))
                self.pendingCommand = nil
                continue
            }

            guard let crlfRange = buffer.range(of: Self.crlf) else {
                break // Incomplete header line
            }

            let lineData = buffer.subdata(in: 0..<crlfRange.lowerBound)
            buffer.removeSubrange(0..<crlfRange.upperBound)

            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                continue
            }

            let tokens = line.components(separatedBy: " ").filter { !$0.isEmpty }
            guard let verbToken = tokens.first?.uppercased() else { continue }

            let transactionId: Int?
            let paramStartIndex: Int
            if Self.nonTransactionalVerbs.contains(verbToken) {
                transactionId = nil
                paramStartIndex = 1
            } else {
                transactionId = tokens.count > 1 ? Int(tokens[1]) : nil
                paramStartIndex = transactionId == nil ? 1 : 2
            }

            let parameters = tokens.count > paramStartIndex ? Array(tokens[paramStartIndex...]) : []
            let cmd = MockMsnpCommand(verb: verbToken, transactionId: transactionId, parameters: parameters)

            if Self.payloadVerbs.contains(verbToken), let lastParam = parameters.last, let expectedLength = Int(lastParam), expectedLength > 0 {
                if buffer.count < expectedLength {
                    self.pendingCommand = (cmd, expectedLength)
                    break
                } else {
                    let payload = buffer.subdata(in: 0..<expectedLength)
                    buffer.removeSubrange(0..<expectedLength)
                    commands.append(MockMsnpCommand(
                        verb: cmd.verb,
                        transactionId: cmd.transactionId,
                        parameters: cmd.parameters,
                        payload: payload
                    ))
                }
            } else {
                commands.append(cmd)
            }
        }
        return commands
    }
}
