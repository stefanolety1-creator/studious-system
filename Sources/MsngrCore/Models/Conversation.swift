import Foundation

/// Encapsulates the active state, messages collection, and participant metadata for a chat session.
public struct Conversation: Identifiable, Hashable, Codable, Sendable {
    /// Conversation identifier matching the remote contact ID or circle GUID email.
    public let id: String

    /// Display title for chat header.
    public var title: String

    /// Remote participant emails in this Switchboard session.
    public var participantEmails: [String]

    /// Chronologically ordered collection of chat messages.
    public var messages: [ChatMessage]

    /// Indicates whether a remote peer is currently typing.
    public var isPeerTyping: Bool

    /// Display name of the participant currently typing.
    public var typingPeerName: String?

    /// Number of unread incoming messages in this conversation.
    public var unreadCount: Int

    /// Unsent draft text in the chat input bar.
    public var draftText: String

    /// Indicates whether an active Switchboard TCP socket is currently connected.
    public var isSwitchboardConnected: Bool

    /// Active Switchboard session identifier.
    public var switchboardSessionId: String?

    /// Indicates whether this conversation represents a multi-user circle or group chat.
    public var isGroupChat: Bool

    /// Timestamp of latest message or interaction.
    public var lastActivityDate: Date

    /// Indicates whether additional historical messages can be loaded from disk.
    public var canLoadOlderMessages: Bool

    public init(
        id: String,
        title: String,
        participantEmails: [String] = [],
        messages: [ChatMessage] = [],
        isPeerTyping: Bool = false,
        typingPeerName: String? = nil,
        unreadCount: Int = 0,
        draftText: String = "",
        isSwitchboardConnected: Bool = false,
        switchboardSessionId: String? = nil,
        isGroupChat: Bool = false,
        lastActivityDate: Date = Date(),
        canLoadOlderMessages: Bool = false
    ) {
        self.id = id.lowercased()
        self.title = title
        self.participantEmails = participantEmails
        self.messages = messages
        self.isPeerTyping = isPeerTyping
        self.typingPeerName = typingPeerName
        self.unreadCount = unreadCount
        self.draftText = draftText
        self.isSwitchboardConnected = isSwitchboardConnected
        self.switchboardSessionId = switchboardSessionId
        self.isGroupChat = isGroupChat
        self.lastActivityDate = lastActivityDate
        self.canLoadOlderMessages = canLoadOlderMessages
    }

    /// Appends a new chat message and updates conversation activity date.
    public mutating func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        lastActivityDate = message.timestamp
        if message.author == .contact {
            unreadCount += 1
        }
    }

    /// Updates the delivery status of an outgoing message.
    public mutating func updateDeliveryStatus(messageId: UUID, status: MessageDeliveryStatus, error: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].deliveryStatus = status
        messages[index].deliveryError = error
    }

    /// Clears unread counter.
    public mutating func markAsRead() {
        unreadCount = 0
    }

    /// Sets typing indicator state.
    public mutating func setPeerTyping(_ typing: Bool, peerName: String? = nil) {
        isPeerTyping = typing
        typingPeerName = typing ? peerName : nil
    }
}
