import Foundation

/// Represents a remote user or circle group contact in the address book and chat session.
public struct Contact: Identifiable, Hashable, Codable, Sendable {
    /// Unique identifier: lowercase passport email or Circle GUID email.
    public let id: String

    /// Friendly display name (may contain Messenger Plus! BBCode formatting).
    public var nickname: String?

    /// Passport email address.
    public let email: String

    /// Current presence state.
    public var presence: PresenceStatus

    /// Personal status message (PSM / "Now Playing").
    public var statusMessage: String

    /// Local file path or cached URI of display picture.
    public var avatarUri: String?

    /// Deserialized MSNObject XML representation for avatar synchronization.
    public var avatarMsnObjectString: String?

    /// Number of unread incoming messages from this contact.
    public var unreadCount: Int

    /// Indicates whether contact is blocked in the ABCH Block List.
    public var isBlocked: Bool

    /// Indicates whether contact is part of the user's Forward List (FL).
    public var isForwardListContact: Bool

    /// Indicates whether the user manually marked conversation as unread.
    public var isMarkedUnread: Bool

    /// Indicates whether this contact entity represents a WLM 2009 Circle group chat.
    public var isGroup: Bool

    /// Identifier of the parent `ContactGroup` category (if assigned).
    public var groupId: String?

    /// If `isGroup == true`, the collection of circle members.
    public var members: [GroupMember]

    /// Timestamp of the latest message or interaction.
    public var lastActivityDate: Date?

    public init(
        id: String,
        nickname: String? = nil,
        email: String,
        presence: PresenceStatus = .offline,
        statusMessage: String = "",
        avatarUri: String? = nil,
        avatarMsnObjectString: String? = nil,
        unreadCount: Int = 0,
        isBlocked: Bool = false,
        isForwardListContact: Bool = true,
        isMarkedUnread: Bool = false,
        isGroup: Bool = false,
        groupId: String? = nil,
        members: [GroupMember] = [],
        lastActivityDate: Date? = nil
    ) {
        self.id = id.lowercased()
        self.nickname = nickname
        self.email = email
        self.presence = presence
        self.statusMessage = statusMessage
        self.avatarUri = avatarUri
        self.avatarMsnObjectString = avatarMsnObjectString
        self.unreadCount = unreadCount
        self.isBlocked = isBlocked
        self.isForwardListContact = isForwardListContact
        self.isMarkedUnread = isMarkedUnread
        self.isGroup = isGroup
        self.groupId = groupId
        self.members = members
        self.lastActivityDate = lastActivityDate
    }

    /// Convenience initializer accepting `displayName` directly.
    public init(
        id: String,
        email: String,
        displayName: String,
        presence: PresenceStatus = .online,
        statusMessage: String = "",
        groupId: String? = nil,
        isBlocked: Bool = false
    ) {
        self.init(
            id: id,
            nickname: displayName,
            email: email,
            presence: presence,
            statusMessage: statusMessage,
            isBlocked: isBlocked,
            groupId: groupId
        )
    }

    /// User-facing display name, falling back to email if nickname is blank.
    public var displayName: String {
        if let nick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nick.isEmpty {
            return nick
        }
        return email
    }

    /// Display name stripped of all Messenger Plus! BBCode tags and C0 control codes.
    public var cleanDisplayName: String {
        MessengerPlusParser.stripFormatting(displayName)
    }

    /// Personal message stripped of all Messenger Plus! BBCode tags.
    public var cleanStatusMessage: String {
        MessengerPlusParser.stripFormatting(statusMessage)
    }

    /// Indicates whether there are pending unread messages.
    public var isUnread: Bool {
        isMarkedUnread || unreadCount > 0
    }
}

// MARK: - Circle Group Member & Roles

public enum GroupMemberRole: String, Codable, Sendable, CaseIterable {
    case owner = "Owner"
    case administrator = "Administrator"
    case user = "User"
    case unknown = "Unknown"

    public var relationshipRole: Int? {
        switch self {
        case .owner: return 1
        case .administrator: return 2
        case .user: return 3
        case .unknown: return nil
        }
    }

    public static func from(relationshipRole: Int?) -> GroupMemberRole {
        switch relationshipRole {
        case 1: return .owner
        case 2: return .administrator
        case 3: return .user
        default: return .unknown
        }
    }
}

public struct GroupMember: Identifiable, Hashable, Codable, Sendable {
    public var id: String { email.lowercased() }
    public let email: String
    public var displayName: String
    public var presence: PresenceStatus
    public var avatarUri: String?
    public var storageId: String?
    public var role: GroupMemberRole

    public init(
        email: String,
        displayName: String? = nil,
        presence: PresenceStatus = .offline,
        avatarUri: String? = nil,
        storageId: String? = nil,
        role: GroupMemberRole = .user
    ) {
        self.email = email
        self.displayName = displayName ?? email
        self.presence = presence
        self.avatarUri = avatarUri
        self.storageId = storageId
        self.role = role
    }
}
