//
// MockSocketStream.swift
// MsngrIntegrationTests
//
// Pure Swift in-memory duplex stream simulating bidirectional TCP transport
// without OS socket or port binding.
//

import Foundation

/// Connection state of an in-memory mock socket stream.
public enum MockStreamState: Sendable, Equatable {
    case idle
    case connected
    case closed
    case reset
}

/// Errors thrown during MockSocketStream operations.
public enum MockSocketStreamError: Error, LocalizedError, Sendable, Equatable {
    case streamClosed
    case connectionReset
    case timeout
    case readBufferEmpty

    public var errorDescription: String? {
        switch self {
        case .streamClosed: return "The in-memory stream was closed."
        case .connectionReset: return "The in-memory connection was reset by peer."
        case .timeout: return "The mock stream operation timed out."
        case .readBufferEmpty: return "No data available in read buffer."
        }
    }
}

/// In-memory bidirectional duplex stream simulating a TCP connection endpoint.
/// Paired instances allow writing to one side and reading from the other with zero network overhead.
public final class MockSocketStream: @unchecked Sendable {
    public let id: String
    private let lock = NSLock()

    private weak var peer: MockSocketStream?
    private var _state: MockStreamState = .idle
    private var _bytesSent: Int = 0
    private var _bytesReceived: Int = 0

    private var incomingDataContinuation: AsyncStream<Data>.Continuation?
    public let incomingData: AsyncStream<Data>

    private var incomingBuffer = Data()
    private var _recordedOutboundData: [Data] = []
    private var _recordedOutboundStrings: [String] = []
    private var autoReplies: [(prefix: String, reply: String)] = []

    public var state: MockStreamState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var isConnected: Bool {
        state == .connected
    }

    public var bytesSent: Int {
        lock.lock()
        defer { lock.unlock() }
        return _bytesSent
    }

    public var bytesReceived: Int {
        lock.lock()
        defer { lock.unlock() }
        return _bytesReceived
    }

    public var recordedOutboundData: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedOutboundData
    }

    public var recordedOutboundStrings: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedOutboundStrings
    }

    public init(id: String = UUID().uuidString) {
        self.id = id
        var continuation: AsyncStream<Data>.Continuation!
        self.incomingData = AsyncStream { c in
            continuation = c
        }
        self.incomingDataContinuation = continuation
    }

    /// Creates a connected duplex pair of mock streams (client <-> server).
    public static func createPair(
        clientId: String = "mock-client",
        serverId: String = "mock-server"
    ) -> (client: MockSocketStream, server: MockSocketStream) {
        let client = MockSocketStream(id: clientId)
        let server = MockSocketStream(id: serverId)

        client.peer = server
        server.peer = client

        client.setState(.connected)
        server.setState(.connected)

        return (client: client, server: server)
    }

    private func setState(_ newState: MockStreamState) {
        lock.lock()
        _state = newState
        lock.unlock()
    }

    // MARK: - Outbound Writing

    /// Sends raw binary data to the connected peer.
    public func send(_ data: Data) async throws {
        lock.lock()
        guard _state == .connected else {
            lock.unlock()
            throw MockSocketStreamError.streamClosed
        }
        _bytesSent += data.count
        _recordedOutboundData.append(data)
        if let str = String(data: data, encoding: .utf8) {
            _recordedOutboundStrings.append(str)
        }
        let targetPeer = peer
        lock.unlock()

        guard let targetPeer = targetPeer else {
            throw MockSocketStreamError.streamClosed
        }

        targetPeer.deliverIncoming(data)
    }

    /// Sends a UTF-8 string to the connected peer.
    public func send(_ string: String) async throws {
        try await send(Data(string.utf8))
    }

    /// Sends a line terminated by CRLF to the connected peer.
    public func sendLine(_ line: String) async throws {
        let terminated = line.hasSuffix("\r\n") ? line : "\(line)\r\n"
        try await send(terminated)
    }

    // MARK: - Inbound Delivery & Receiving

    private func deliverIncoming(_ data: Data) {
        lock.lock()
        guard _state == .connected else {
            lock.unlock()
            return
        }
        _bytesReceived += data.count
        incomingBuffer.append(data)
        let cont = incomingDataContinuation
        let replies = autoReplies
        let currentString = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()

        cont?.yield(data)

        // Check auto-replies
        for item in replies {
            if currentString.hasPrefix(item.prefix) {
                Task {
                    try? await self.send(item.reply)
                }
            }
        }
    }

    /// Reads up to `maxBytes` from the incoming buffer, waiting for data if necessary.
    public func read(upTo maxBytes: Int, timeout: TimeInterval = 3.0) async throws -> Data {
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    self.lock.lock()
                    if self._state == .closed || self._state == .reset {
                        self.lock.unlock()
                        throw MockSocketStreamError.streamClosed
                    }
                    if !self.incomingBuffer.isEmpty {
                        let count = min(maxBytes, self.incomingBuffer.count)
                        let slice = self.incomingBuffer.prefix(count)
                        self.incomingBuffer.removeFirst(count)
                        self.lock.unlock()
                        return Data(slice)
                    }
                    self.lock.unlock()
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                throw MockSocketStreamError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Reads a single line terminated by CRLF or LF.
    public func readLine(timeout: TimeInterval = 3.0) async throws -> String? {
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    self.lock.lock()
                    if self._state == .closed || self._state == .reset {
                        self.lock.unlock()
                        return nil
                    }

                    if let line = self.extractLineFromBuffer() {
                        self.lock.unlock()
                        return line
                    }
                    self.lock.unlock()
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                throw MockSocketStreamError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func extractLineFromBuffer() -> String? {
        guard !incomingBuffer.isEmpty else { return nil }

        // Look for \r\n first, then \n
        if let crlfRange = incomingBuffer.range(of: Data([0x0D, 0x0A])) {
            let lineData = incomingBuffer.subdata(in: 0..<crlfRange.lowerBound)
            incomingBuffer.removeSubrange(0..<crlfRange.upperBound)
            return String(data: lineData, encoding: .utf8)
        } else if let lfRange = incomingBuffer.range(of: Data([0x0A])) {
            let lineData = incomingBuffer.subdata(in: 0..<lfRange.lowerBound)
            incomingBuffer.removeSubrange(0..<lfRange.upperBound)
            return String(data: lineData, encoding: .utf8)
        }
        return nil
    }

    /// Consumes incoming data as an AsyncStream of decoded string lines.
    public var incomingLines: AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                while self.isConnected {
                    if let line = try? await self.readLine(timeout: 0.1) {
                        continuation.yield(line)
                    } else if !self.isConnected {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Scripting & Automation Helpers

    /// Registers an automatic scripted reply when an incoming message starts with `prefix`.
    public func autoReply(when prefix: String, response: String) {
        lock.lock()
        defer { lock.unlock() }
        let terminated = response.hasSuffix("\r\n") ? response : "\(response)\r\n"
        autoReplies.append((prefix: prefix, reply: terminated))
    }

    /// Waits for a line matching the given predicate.
    public func expectLine(
        timeout: TimeInterval = 3.0,
        matching: @escaping @Sendable (String) -> Bool
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = try? await readLine(timeout: 0.2) {
                if matching(line) {
                    return line
                }
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        throw MockSocketStreamError.timeout
    }

    /// Waits for a line starting with `prefix`.
    public func expectPrefix(
        _ prefix: String,
        timeout: TimeInterval = 3.0
    ) async throws -> String {
        return try await expectLine(timeout: timeout) { $0.hasPrefix(prefix) }
    }

    // MARK: - Lifecycle & Diagnostics

    /// Gracefully closes the stream.
    public func close() {
        lock.lock()
        _state = .closed
        incomingDataContinuation?.finish()
        incomingDataContinuation = nil
        let targetPeer = peer
        lock.unlock()

        targetPeer?.peerDidClose()
    }

    private func peerDidClose() {
        lock.lock()
        _state = .closed
        incomingDataContinuation?.finish()
        incomingDataContinuation = nil
        lock.unlock()
    }

    /// Simulates an abrupt connection reset by peer (TCP RST).
    public func simulateReset() {
        lock.lock()
        _state = .reset
        incomingDataContinuation?.finish()
        incomingDataContinuation = nil
        let targetPeer = peer
        lock.unlock()

        targetPeer?.peerDidReset()
    }

    private func peerDidReset() {
        lock.lock()
        _state = .reset
        incomingDataContinuation?.finish()
        incomingDataContinuation = nil
        lock.unlock()
    }

    /// Clears recorded telemetry buffers.
    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        _recordedOutboundData.removeAll()
        _recordedOutboundStrings.removeAll()
        _bytesSent = 0
        _bytesReceived = 0
        incomingBuffer.removeAll()
        autoReplies.removeAll()
    }
}
