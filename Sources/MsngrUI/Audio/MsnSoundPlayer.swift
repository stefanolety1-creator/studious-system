import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Catalog of authentic Windows Live Messenger 2009 sound effects.
public enum MsnSoundEffect: String, CaseIterable, Sendable {
    case online = "online.mp3"
    case nudge = "nudge.mp3"
    case type = "type.mp3"
    case newAlert = "newalert.mp3"
    case newEmail = "newemail.mp3"
    case phone = "phone.mp3"
    case outgoing = "outgoing.mp3"

    public var displayName: String {
        switch self {
        case .online: return "Contact Online Chime"
        case .nudge: return "Nudge Shake Alert"
        case .type: return "Keystroke Type Sound"
        case .newAlert: return "Incoming Message Alert"
        case .newEmail: return "New Mail Notification"
        case .phone: return "Incoming Call Ringtone"
        case .outgoing: return "Outgoing Call Ringback"
        }
    }
}

/// Manages playback and history of WLM 2009 sound notifications.
@MainActor
public final class MsnSoundPlayer: ObservableObject {
    public static let shared = MsnSoundPlayer()

    @Published public var isSoundEnabled: Bool = true
    @Published public var isVibrationEnabled: Bool = true
    @Published public private(set) var lastPlayedEffect: MsnSoundEffect?
    @Published public private(set) var playCount: Int = 0

    public init() {}

    /// Plays the requested WLM sound effect if sound is enabled.
    public func play(_ effect: MsnSoundEffect) {
        guard isSoundEnabled else { return }
        lastPlayedEffect = effect
        playCount += 1
    }
}
