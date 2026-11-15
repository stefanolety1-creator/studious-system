import Foundation

/// Originator of a chat message.
public enum MessageAuthor: String, Codable, Sendable {
    case me
    case contact
    case system
}

/// Transmission status of an outgoing message.
public enum MessageDeliveryStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case failed
}

/// Message payload classification.
public enum ChatMessageKind: String, Codable, Sendable {
    case text
    case nudge
    case system
    case fileTransfer
    case wink
    case voiceClip
    case ink
    case gameMove
}

/// File transfer progress and state machine representation.
public enum FileTransferStatus: String, Codable, Sendable {
    case offered
    case waitingPeer
    case transferring
    case completed
    case rejected
    case failed
}

public struct FileTransferInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let fileName: String
    public let fileSize: Int64
    public let isOutgoing: Bool
    public var status: FileTransferStatus
    public var progress: Float
    public var localPath: String?
    public var error: String?

    public init(
        id: String,
        fileName: String,
        fileSize: Int64,
        isOutgoing: Bool,
        status: FileTransferStatus = .offered,
        progress: Float = 0.0,
        localPath: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.isOutgoing = isOutgoing
        self.status = status
        self.progress = progress
        self.localPath = localPath
        self.error = error
    }
}

/// Voice clip metadata structure.
public struct VoiceClipInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let durationSeconds: Double
    public let waveformSamples: [Float]
    public var localAudioUri: String?

    public init(
        id: String,
        durationSeconds: Double,
        waveformSamples: [Float] = [],
        localAudioUri: String? = nil
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.waveformSamples = waveformSamples
        self.localAudioUri = localAudioUri
    }
}

/// Wink animation reference structure.
public struct WinkReference: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public var thumbnailUri: String?

    public init(id: String, name: String, thumbnailUri: String? = nil) {
        self.id = id
        self.name = name
        self.thumbnailUri = thumbnailUri
    }
}

/// Primary instant message structure representing text, nudges, media, and system alerts.
public struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    /// Unique identifier for SwiftUI rendering and local store.
    public let id: UUID

    /// Optional legacy 64-bit millisecond sequence ID for Android binary store parity.
    public let legacyId: Int64?

    /// Lowercase email or Circle GUID of the conversation recipient.
    public let contactId: String

    /// Message originator.
    public let author: MessageAuthor

    /// Raw message body text (including BBCode formatting or C0 controls).
    public let text: String

    /// Timestamp when message was created or received.
    public let timestamp: Date

    /// Classification of message kind.
    public var kind: ChatMessageKind

    /// Outgoing delivery status.
    public var deliveryStatus: MessageDeliveryStatus

    /// Delivery error description if delivery failed.
    public var deliveryError: String?

    /// Specific sender email (populated in group/circle conversations).
    public var senderEmail: String?

    /// Specific sender friendly name (populated in group/circle conversations).
    public var senderName: String?

    /// Associated file transfer payload if kind == .fileTransfer.
    public var fileTransfer: FileTransferInfo?

    /// Associated wink payload if kind == .wink.
    public var wink: WinkReference?

    /// Associated voice clip payload if kind == .voiceClip.
    public var voiceClip: VoiceClipInfo?

    public init(
        id: UUID = UUID(),
        legacyId: Int64? = nil,
        contactId: String,
        author: MessageAuthor,
        text: String,
        timestamp: Date = Date(),
        kind: ChatMessageKind = .text,
        deliveryStatus: MessageDeliveryStatus = .sent,
        deliveryError: String? = nil,
        senderEmail: String? = nil,
        senderName: String? = nil,
        fileTransfer: FileTransferInfo? = nil,
        wink: WinkReference? = nil,
        voiceClip: VoiceClipInfo? = nil
    ) {
        self.id = id
        self.legacyId = legacyId
        self.contactId = contactId.lowercased()
        self.author = author
        self.text = text
        self.timestamp = timestamp
        self.kind = kind
        self.deliveryStatus = deliveryStatus
        self.deliveryError = deliveryError
        self.senderEmail = senderEmail
        self.senderName = senderName
        self.fileTransfer = fileTransfer
        self.wink = wink
        self.voiceClip = voiceClip
    }

    /// Convenience initializer for incoming protocol messages.
    public init(
        id: UUID = UUID(),
        sender: String,
        text: String,
        formattedText: AttributedString? = nil,
        messageType: ChatMessageKind = .text,
        timestamp: Date = Date()
    ) {
        self.init(
            id: id,
            contactId: sender,
            author: .contact,
            text: text,
            timestamp: timestamp,
            kind: messageType,
            senderEmail: sender
        )
    }

    /// Sender identifier alias.
    public var sender: String {
        senderEmail ?? contactId
    }

    /// Message payload kind alias.
    public var messageType: ChatMessageKind {
        kind
    }

    /// Formatted SwiftUI AttributedString with Messenger Plus! styling applied.
    public var formattedText: AttributedString {
        MessengerPlusParser.parseToAttributedString(text)
    }

    /// Convenience check for nudge message.
    public var isNudge: Bool { kind == .nudge }

    /// Convenience check for in-flight transmission.
    public var isSending: Bool { deliveryStatus == .sending }

    /// Static builder for classic WLM 2009 Nudge.
    public static func nudge(contactId: String, author: MessageAuthor) -> ChatMessage {
        ChatMessage(
            contactId: contactId,
            author: author,
            text: author == .me ? "You have just sent a Nudge." : "You have just received a Nudge!",
            kind: .nudge
        )
    }

    /// Static builder for system informational notices.
    public static func system(contactId: String, text: String) -> ChatMessage {
        ChatMessage(
            contactId: contactId,
            author: .system,
            text: text,
            kind: .system
        )
    }
}
