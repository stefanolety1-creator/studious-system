import Foundation

/// Represents a contact category group in the address book or main contacts list view.
public struct ContactGroup: Identifiable, Hashable, Codable, Sendable {
    /// Unique group identifier: ABCH GUID, circle GUID email, or system key.
    public let id: String

    /// Group title (e.g. "Favorites", "Friends", "Online").
    public var name: String

    /// Indicates whether this group is a WLM 2009 Circle.
    public var isCircle: Bool

    /// Indicates whether this group is a dynamic system group (e.g. "Online", "Offline").
    public var isSystemGroup: Bool

    /// Set of member contact emails assigned to this group.
    public var contactIds: Set<String>

    /// UI accordion expansion state.
    public var isExpanded: Bool

    /// Visual display order.
    public var orderIndex: Int

    public init(
        id: String,
        name: String,
        isCircle: Bool = false,
        isSystemGroup: Bool = false,
        contactIds: Set<String> = [],
        isExpanded: Bool = true,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isCircle = isCircle
        self.isSystemGroup = isSystemGroup
        self.contactIds = contactIds
        self.isExpanded = isExpanded
        self.orderIndex = orderIndex
    }

    /// Static builder for the "Online" contacts category header.
    public static func online(contactIds: Set<String> = []) -> ContactGroup {
        ContactGroup(
            id: "system.online",
            name: "Online",
            isSystemGroup: true,
            contactIds: contactIds,
            isExpanded: true,
            orderIndex: 0
        )
    }

    /// Static builder for the "Offline" contacts category header.
    public static func offline(contactIds: Set<String> = []) -> ContactGroup {
        ContactGroup(
            id: "system.offline",
            name: "Offline",
            isSystemGroup: true,
            contactIds: contactIds,
            isExpanded: true,
            orderIndex: 1
        )
    }
}
