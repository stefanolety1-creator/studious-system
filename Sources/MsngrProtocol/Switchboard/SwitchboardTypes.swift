import Foundation
import MsngrCore

/// Acknowledgement mode for MSNP18 Switchboard `MSG` transmissions.
public enum SwitchboardAckMode: String, Sendable {
    case acknowledged = "A"
    case unacknowledged = "U"
    case negativeAck = "N"
    case data = "D"
}

/// Reason a Switchboard chat session ended.
public enum SessionEndReason: Sendable, Equatable {
    case cleanTeardown
    case peerDeparted
    case socketReset
}

/// Events emitted by an active Switchboard chat session.
public enum SwitchboardEvent: Sendable, Equatable {
    case userJoined(email: String, displayName: String)
    case userLeft(email: String)
    case messageReceived(ChatMessage)
    case typingReceived(email: String)
    case nudgeReceived(email: String)
    case sessionEnded(reason: SessionEndReason)
}

/// Errors thrown during Switchboard chat session operations.
public enum SwitchboardError: Error, Equatable, Sendable {
    case connectionTimeout
    case peerOffline(code: Int)
    case emptyMessage
    case messageExceedsMaxLength
    case messageDeliveryFailed(trId: Int)
    case socketReset
}

/// Errors thrown when sending a Nudge datacast.
public enum NudgeError: Error, Equatable, Sendable {
    case cooldownActive
}

/// Actor tracking typing indicator expiration timeout.
public actor TypingStateTracker {
    public private(set) var isTyping = false
    private var expiryTask: Task<Void, Error>?
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 0.3) {
        self.timeout = timeout
    }

    public func setTyping() {
        isTyping = true
        expiryTask?.cancel()
        expiryTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            isTyping = false
        }
    }

    public func getIsTyping() -> Bool {
        return isTyping
    }
}
