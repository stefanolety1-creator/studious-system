import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MsnSoundEffect Catalog

public enum MsnSoundEffect: String, CaseIterable, Identifiable, Sendable {
    case online = "online.mp3"
    case nudge = "nudge.mp3"
    case type = "type.mp3"
    case newalert = "newalert.mp3"
    case newemail = "newemail.mp3"
    case ring = "phone.mp3"
    case callstart = "outgoing.mp3"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .online: return "Contact Online Chime"
        case .nudge: return "Nudge Shake Alert"
        case .type: return "Keystroke Type Sound"
        case .newalert: return "Incoming Message Alert"
        case .newemail: return "New Mail Notification"
        case .ring: return "Incoming Call Ringtone"
        case .callstart: return "Outgoing Call Ringback"
        }
    }

    // Static Aliases for backward compatibility
    public static let phone: MsnSoundEffect = .ring
    public static let outgoing: MsnSoundEffect = .callstart
    public static let callStart: MsnSoundEffect = .callstart
    public static let newAlert: MsnSoundEffect = .newalert
    public static let newEmail: MsnSoundEffect = .newemail

    public init?(rawValue: String) {
        let clean = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".mp3", with: "")
            .lowercased()
        switch clean {
        case "online": self = .online
        case "nudge": self = .nudge
        case "type": self = .type
        case "newalert", "new_alert": self = .newalert
        case "newemail", "new_email": self = .newemail
        case "ring", "phone": self = .ring
        case "callstart", "outgoing", "call_start": self = .callstart
        default: return nil
        }
    }

    /// Ordered candidate filenames to check in resource bundles.
    public var fileCandidates: [String] {
        switch self {
        case .online: return ["online.mp3", "online"]
        case .nudge: return ["nudge.mp3", "nudge"]
        case .type: return ["type.mp3", "type"]
        case .newalert: return ["newalert.mp3", "newalert"]
        case .newemail: return ["newemail.mp3", "newemail"]
        case .ring: return ["ring.mp3", "phone.mp3", "ring", "phone"]
        case .callstart: return ["callstart.mp3", "outgoing.mp3", "callstart", "outgoing"]
        }
    }
}

// MARK: - Sound Playback Session Delegate

private final class SoundPlaybackSession: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let player: AVAudioPlayer
    let onCompletion: @Sendable (SoundPlaybackSession) -> Void

    init(player: AVAudioPlayer, onCompletion: @escaping @Sendable (SoundPlaybackSession) -> Void) {
        self.player = player
        self.onCompletion = onCompletion
        super.init()
        self.player.delegate = self
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onCompletion(self)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onCompletion(self)
    }
}

// MARK: - MsnSoundPlayer

@MainActor
public final class MsnSoundPlayer: ObservableObject {
    public static let shared = MsnSoundPlayer()

    // MARK: - Published Properties

    @Published public var isSoundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundEnabled, forKey: "msngr_sound_enabled")
        }
    }

    @Published public var isVibrationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVibrationEnabled, forKey: "msngr_vibration_enabled")
        }
    }

    @Published public var volume: Float = 1.0

    @Published public private(set) var lastPlayedEffect: MsnSoundEffect?
    @Published public private(set) var playCount: Int = 0

    public var isMuted: Bool {
        get { !isSoundEnabled }
        set { isSoundEnabled = !newValue }
    }

    // MARK: - Private State

    private var activeSessions = Set<SoundPlaybackSession>()
    private var audioDataCache = [String: Data]()

    // MARK: - Initialization

    public init() {
        self.isSoundEnabled = UserDefaults.standard.object(forKey: "msngr_sound_enabled") as? Bool ?? true
        self.isVibrationEnabled = UserDefaults.standard.object(forKey: "msngr_vibration_enabled") as? Bool ?? true
        configureAudioSession()
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio hardware may not be available on headless CI or simulator
        }
        #endif
    }

    // MARK: - Audio Playback API

    /// Plays the requested sound effect, applying caching, volume, and concurrent playback.
    public func play(_ effect: MsnSoundEffect, customVolume: Float? = nil) {
        guard isSoundEnabled else { return }

        lastPlayedEffect = effect
        playCount += 1

        if effect == .nudge && isVibrationEnabled {
            vibrateNudge()
        }

        guard let soundData = loadSoundData(for: effect) else {
            return
        }

        do {
            let player = try AVAudioPlayer(data: soundData)
            player.volume = max(0.0, min(1.0, customVolume ?? volume))

            var sessionBox: SoundPlaybackSession?
            sessionBox = SoundPlaybackSession(player: player) { [weak self] session in
                Task { @MainActor in
                    self?.activeSessions.remove(session)
                }
            }

            if let session = sessionBox {
                activeSessions.insert(session)
                player.play()
            }
        } catch {
            // Graceful fallback: audio hardware errors do not interrupt app execution
        }
    }

    /// Stops all currently active sound sessions.
    public func stopAll() {
        for session in activeSessions {
            session.player.stop()
        }
        activeSessions.removeAll()
    }

    /// Triggers authentic MSN Nudge haptic waveform pattern `[0, 120, 80, 150, 60, 200] ms`.
    public func vibrateNudge() {
        #if os(iOS)
        guard isVibrationEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)

        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            try? await Task.sleep(nanoseconds: 150_000_000)
            impact.impactOccurred()
        }
        #endif
    }

    // MARK: - Resource Lookup

    private func loadSoundData(for effect: MsnSoundEffect) -> Data? {
        if let cached = audioDataCache[effect.rawValue] {
            return cached
        }

        for candidate in effect.fileCandidates {
            let name = (candidate as NSString).deletingPathExtension
            let ext = (candidate as NSString).pathExtension.isEmpty ? "mp3" : (candidate as NSString).pathExtension

            // 1. Bundle.module lookup (SPM Package)
            #if SWIFT_PACKAGE
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
                ?? Bundle.module.url(forResource: name, withExtension: ext)
                ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/Sounds") {
                if let data = try? Data(contentsOf: url) {
                    audioDataCache[effect.rawValue] = data
                    return data
                }
            }
            #endif

            // 2. Bundle.main lookup (XcodeGen / App)
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Sounds") {
                if let data = try? Data(contentsOf: url) {
                    audioDataCache[effect.rawValue] = data
                    return data
                }
            }

            // 3. Fallback direct relative file path in bundle / working directory
            let fallbackPaths = [
                "Sources/MsngrUI/Resources/Sounds/\(candidate)",
                "Resources/Sounds/\(candidate)",
                "Sounds/\(candidate)",
                candidate
            ]
            for path in fallbackPaths {
                if FileManager.default.fileExists(atPath: path), let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    audioDataCache[effect.rawValue] = data
                    return data
                }
            }
        }

        return nil
    }
}
