import Foundation

/// Represents user presence in Windows Live Messenger / MSNP18 protocol.
/// Conforms to MSNP18 wire specifications and handles all legacy and Escargot aliases.
public enum PresenceStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case online = "NLN"
    case busy = "BSY"
    case away = "AWY"
    case idle = "IDL"
    case beRightBack = "BRB"
    case onThePhone = "PHN"
    case outToLunch = "LUN"
    case hidden = "HDN"
    case offline = "FLN"

    public var id: String { rawValue }

    /// Primary MSNP18 wire verb for this status.
    public var wireCode: String { rawValue }

    /// Valid outbound wire code sent to Notification Server via `CHG`.
    /// Aliases (`IDL`, `BRB`, `PHN`, `LUN`) map to `AWY`, while `FLN` maps to `HDN`.
    public var outboundWireCode: String {
        switch self {
        case .online:
            return "NLN"
        case .busy:
            return "BSY"
        case .away, .idle, .beRightBack, .onThePhone, .outToLunch:
            return "AWY"
        case .hidden, .offline:
            return "HDN"
        }
    }

    /// Outbound wire code alias used by NotificationServerClient.
    public var msnpPresenceCode: String { outboundWireCode }

    /// Initializes PresenceStatus from an MSNP18 presence code, defaulting unknown codes to `.online`.
    public init(msnpPresenceCode: String) {
        let normalized = msnpPresenceCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "NLN", "AVAILABLE", "ONLINE":
            self = .online
        case "BSY", "BUSY":
            self = .busy
        case "AWY", "AWAY":
            self = .away
        case "IDL", "IDLE":
            self = .idle
        case "BRB":
            self = .beRightBack
        case "PHN", "ONTHEPHONE":
            self = .onThePhone
        case "LUN", "OUTTOLUNCH":
            self = .outToLunch
        case "HDN", "HIDDEN", "APPEAROFFLINE":
            self = .hidden
        case "FLN", "OFFLINE":
            self = .offline
        default:
            self = .online
        }
    }

    /// English display label matching classic WLM 2009.
    public var label: String {
        switch self {
        case .online: return "Online"
        case .busy: return "Busy"
        case .away: return "Away"
        case .idle: return "Away (Idle)"
        case .beRightBack: return "Be Right Back"
        case .onThePhone: return "On the Phone"
        case .outToLunch: return "Out to Lunch"
        case .hidden: return "Appear Offline"
        case .offline: return "Offline"
        }
    }

    /// Sorting priority in contacts list: Online (0) > Busy (1) > Away/Idle/BRB (2) > Offline (3).
    public var priority: Int {
        switch self {
        case .online: return 0
        case .busy: return 1
        case .away, .idle, .beRightBack, .onThePhone, .outToLunch: return 2
        case .hidden, .offline: return 3
        }
    }

    /// Indicates whether the contact is actively reachable on the network.
    public var isOnline: Bool {
        switch self {
        case .online, .busy, .away, .idle, .beRightBack, .onThePhone, .outToLunch:
            return true
        case .hidden, .offline:
            return false
        }
    }

    /// Asset name for the WLM 2009 Frutiger Aero glossy status icon.
    public var iconName: String {
        switch self {
        case .online: return "status_online"
        case .busy: return "status_busy"
        case .away, .idle, .beRightBack, .onThePhone, .outToLunch: return "status_away"
        case .hidden, .offline: return "status_offline"
        }
    }

    /// Parses inbound MSNP18 wire status verbs or friendly string aliases.
    public static func from(wireCode: String) -> PresenceStatus {
        let normalized = wireCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "NLN", "AVAILABLE", "ONLINE":
            return .online
        case "BSY", "BUSY":
            return .busy
        case "AWY", "AWAY":
            return .away
        case "IDL", "IDLE":
            return .idle
        case "BRB":
            return .beRightBack
        case "PHN", "ONTHEPHONE":
            return .onThePhone
        case "LUN", "OUTTOLUNCH":
            return .outToLunch
        case "HDN", "HIDDEN", "APPEAROFFLINE":
            return .hidden
        case "FLN", "OFFLINE":
            return .offline
        default:
            return .offline
        }
    }
}

/// Typealias for seamless compatibility with codebase references.
public typealias Presence = PresenceStatus
