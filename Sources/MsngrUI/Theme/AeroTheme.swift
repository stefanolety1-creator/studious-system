import SwiftUI

// MARK: - Color Extension & Palette Definitions

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    // WLM 2009 Light Palette (Wave 3 Frutiger Aero)
    static let wlmPrimary = Color(hex: 0x0078D7)
    static let wlmPrimaryContainer = Color(hex: 0xD6EFFC)
    static let wlmOnPrimaryContainer = Color(hex: 0x003865)
    static let wlmSecondary = Color(hex: 0x32B300)
    static let wlmSecondaryContainer = Color(hex: 0xDCF7D5)
    static let wlmWindowBackground = Color(hex: 0xE7F3FC)
    static let wlmSurfaceVariant = Color(hex: 0xEDF5FA)
    static let wlmOutline = Color(hex: 0xB5D7ED)
    static let wlmOutlineVariant = Color(hex: 0xDCEAF3)
    static let wlmTextDark = Color(hex: 0x1C2A39)
    static let wlmTextMuted = Color(hex: 0x556877)

    // WLM Night Aero Dark Palette
    static let wlmNightPrimary = Color(hex: 0x5AC8FA)
    static let wlmNightSecondary = Color(hex: 0x55E030)
    static let wlmNightBackground = Color(hex: 0x0D141A)
    static let wlmNightSurface = Color(hex: 0x121B22)
    static let wlmNightOutline = Color(hex: 0x4A657C)

    // Retro MSN Messenger 7.5 Palette
    static let msn75Primary = Color(hex: 0x0055AA)
    static let msn75Secondary = Color(hex: 0xE67E00)
    static let msn75Background = Color(hex: 0xF3F7FA)

    // Presence Status Colors
    static let msnOnline = Color(hex: 0x6AE633)
    static let msnOnlineBorder = Color(hex: 0x166B0A)
    static let msnBusy = Color(hex: 0xFF4D4D)
    static let msnBusyBorder = Color(hex: 0x8B0000)
    static let msnAway = Color(hex: 0xFFC107)
    static let msnAwayBorder = Color(hex: 0xB26500)
    static let msnOffline = Color(hex: 0x90A4AE)
    static let msnOfflineTop = Color(hex: 0xCFD8DC)

    // Chat Bubble Colors
    static let wlmBubbleIncoming = Color(hex: 0xF3F8FC)
    static let wlmBubbleOutgoing = Color(hex: 0xE2F0FA)
    static let wlmSenderMe = Color(hex: 0x6B7A88)
    static let wlmSenderPeer = Color(hex: 0x1B65A4)
}

// MARK: - Legacy AeroSkin Enum (Backward Compatibility)

public enum AeroSkin: String, CaseIterable, Identifiable, Codable, Sendable {
    case wlm2009Light = "WLM 2009 Aero (Light)"
    case wlm2009Night = "WLM Night Aero (Dark)"
    case msn75Classic = "MSN Messenger 7.5"

    public var id: String { rawValue }

    public var primaryColor: Color {
        switch self {
        case .wlm2009Light: return .wlmPrimary
        case .wlm2009Night: return .wlmNightPrimary
        case .msn75Classic: return .msn75Primary
        }
    }

    public var windowBackgroundColor: Color {
        switch self {
        case .wlm2009Light: return .wlmWindowBackground
        case .wlm2009Night: return .wlmNightBackground
        case .msn75Classic: return .msn75Background
        }
    }

    public var isDark: Bool {
        self == .wlm2009Night
    }
}

// MARK: - Complete 23 WlmScene Cases (Exact Android WlmScenes.kt Parity)

public enum WlmScene: String, CaseIterable, Identifiable, Codable, Sendable {
    case sky = "Windows Live Sky"
    case carbonFiber = "Carbon Fiber"
    case mesmerizingWhite = "Mesmerizing White"
    case dottieGreen = "Spring Meadow"
    case graffiti = "Graffiti & Concrete"
    case butterflyPattern = "Butterfly Damask"
    case silhouette = "Aurora Horizon"
    case robot = "Retro Robot"
    case morty = "Morty"
    case scene0001 = "Blue Waves"
    case scene0002 = "Orange Gradient"
    case scene0003 = "Pastel Colors"
    case scene0004 = "Night Glow"
    case scene0005 = "Neon Tech"
    case scene0006 = "Minimal White"
    case scene0007 = "Geometric Art"
    case scene0008 = "Dark Prism"
    case zune01 = "Zune Dark Glow"
    case zune02 = "Zune Sunset"
    case zune03 = "Zune Cyberpunk"
    case zune04 = "Zune Ambient"
    case zune05 = "Zune Midnight"
    case zune06 = "Zune Aurora"

    public var id: String { sceneId }

    public var sceneId: String {
        switch self {
        case .sky: return "sky"
        case .carbonFiber: return "carbonfiber"
        case .mesmerizingWhite: return "mesmerizingwhite"
        case .dottieGreen: return "dottiegreen"
        case .graffiti: return "graffiti"
        case .butterflyPattern: return "butterflypattern"
        case .silhouette: return "silhouette"
        case .robot: return "robot"
        case .morty: return "morty"
        case .scene0001: return "scene0001"
        case .scene0002: return "scene0002"
        case .scene0003: return "scene0003"
        case .scene0004: return "scene0004"
        case .scene0005: return "scene0005"
        case .scene0006: return "scene0006"
        case .scene0007: return "scene0007"
        case .scene0008: return "scene0008"
        case .zune01: return "zune01"
        case .zune02: return "zune02"
        case .zune03: return "zune03"
        case .zune04: return "zune04"
        case .zune05: return "zune05"
        case .zune06: return "zune06"
        }
    }

    public var displayName: String { rawValue }
    public var title: String { rawValue }

    // Backward compatibility aliases
    public static var butterflyDamask: WlmScene { .butterflyPattern }
    public static var vistaSilhouette: WlmScene { .silhouette }
    public static var zuneOrange: WlmScene { .zune02 }

    public static func fromId(_ id: String?) -> WlmScene {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !id.isEmpty else {
            return .sky
        }
        for scene in WlmScene.allCases {
            if scene.sceneId == id || scene.rawValue.lowercased() == id {
                return scene
            }
        }
        // Check aliases
        switch id {
        case "windows live sky", "sky": return .sky
        case "carbon fiber", "carbonfiber": return .carbonFiber
        case "spring meadow", "dottiegreen": return .dottieGreen
        case "butterfly damask", "butterflypattern": return .butterflyPattern
        case "aurora horizon", "silhouette": return .silhouette
        case "zune sunset", "zune orange", "zune02": return .zune02
        default: return .sky
        }
    }

    public init?(rawValue: String) {
        let clean = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scene in WlmScene.allCases {
            if scene.rawValue.lowercased() == clean || scene.sceneId == clean {
                self = scene
                return
            }
        }
        switch clean {
        case "windows live sky", "sky": self = .sky
        case "carbon fiber", "carbonfiber": self = .carbonFiber
        case "mesmerizing white", "mesmerizingwhite": self = .mesmerizingWhite
        case "spring meadow", "dottie green", "dottiegreen": self = .dottieGreen
        case "graffiti", "graffiti & concrete": self = .graffiti
        case "butterfly damask", "butterfly pattern", "butterflypattern": self = .butterflyPattern
        case "aurora horizon", "vista silhouette", "silhouette": self = .silhouette
        case "robot", "retro robot": self = .robot
        case "morty": self = .morty
        case "scene0001", "blue waves": self = .scene0001
        case "scene0002", "orange gradient": self = .scene0002
        case "scene0003", "pastel colors": self = .scene0003
        case "scene0004", "night glow": self = .scene0004
        case "scene0005", "neon tech": self = .scene0005
        case "scene0006", "minimal white": self = .scene0006
        case "scene0007", "geometric art": self = .scene0007
        case "scene0008", "dark prism": self = .scene0008
        case "zune01", "zune dark glow": self = .zune01
        case "zune02", "zune orange", "zune sunset": self = .zune02
        case "zune03", "zune cyberpunk": self = .zune03
        case "zune04", "zune ambient": self = .zune04
        case "zune05", "zune midnight": self = .zune05
        case "zune06", "zune aurora": self = .zune06
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let match = WlmScene(rawValue: value) {
            self = match
        } else {
            self = WlmScene.fromId(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sceneId)
    }

    public var isDark: Bool {
        switch self {
        case .carbonFiber, .butterflyPattern, .robot, .scene0004, .scene0005,
             .scene0008, .zune01, .zune02, .zune03, .zune05:
            return true
        default:
            return false
        }
    }

    public var isDarkText: Bool {
        self == .mesmerizingWhite
    }

    public var textColor: Color {
        switch self {
        case .sky: return Color(hex: 0x103657)
        case .carbonFiber: return .white
        case .mesmerizingWhite: return Color(hex: 0x1F2937)
        case .dottieGreen: return Color(hex: 0x133800)
        case .graffiti: return Color(hex: 0x0F2336)
        case .butterflyPattern: return .white
        case .silhouette: return Color(hex: 0x1E3A5F)
        case .robot: return .white
        case .morty: return Color(hex: 0x1E293B)
        case .scene0001: return Color(hex: 0x0F2B48)
        case .scene0002: return Color(hex: 0x3A1A00)
        case .scene0003: return Color(hex: 0x1E293B)
        case .scene0004: return .white
        case .scene0005: return .white
        case .scene0006: return Color(hex: 0x1E293B)
        case .scene0007: return Color(hex: 0x0F2942)
        case .scene0008: return .white
        case .zune01: return .white
        case .zune02: return .white
        case .zune03: return .white
        case .zune04: return Color(hex: 0x1E293B)
        case .zune05: return .white
        case .zune06: return Color(hex: 0x1E3A5F)
        }
    }

    public var statusColor: Color {
        switch self {
        case .sky: return Color(hex: 0x1B4F76)
        case .carbonFiber: return Color(hex: 0x70E050)
        case .mesmerizingWhite: return Color(hex: 0x4B5563)
        case .dottieGreen: return Color(hex: 0x225000)
        case .graffiti: return Color(hex: 0x1F3D59)
        case .butterflyPattern: return Color(hex: 0xD4D4D8)
        case .silhouette: return Color(hex: 0x385E8A)
        case .robot: return Color(hex: 0xE2E8F0)
        case .morty: return Color(hex: 0x475569)
        case .scene0001: return Color(hex: 0x1C476E)
        case .scene0002: return Color(hex: 0x5A2A00)
        case .scene0003: return Color(hex: 0x334155)
        case .scene0004: return Color(hex: 0x93C5FD)
        case .scene0005: return Color(hex: 0x67E8F9)
        case .scene0006: return Color(hex: 0x475569)
        case .scene0007: return Color(hex: 0x1E4060)
        case .scene0008: return Color(hex: 0xC084FC)
        case .zune01: return Color(hex: 0xF472B6)
        case .zune02: return Color(hex: 0xFDBA74)
        case .zune03: return Color(hex: 0xA78BFA)
        case .zune04: return Color(hex: 0x475569)
        case .zune05: return Color(hex: 0x38BDF8)
        case .zune06: return Color(hex: 0x2563EB)
        }
    }

    public var shadowColor: Color {
        textShadowColor
    }

    public var textShadowColor: Color {
        isDark ? Color.black.opacity(0.80) : Color.white.opacity(0.70)
    }

    public var headerGradient: LinearGradient {
        switch self {
        case .sky:
            return .wlmSkyHeader
        case .carbonFiber:
            return LinearGradient(
                colors: [Color(hex: 0x1A1E24), Color(hex: 0x2C333D), Color(hex: 0x121519)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mesmerizingWhite:
            return LinearGradient(
                colors: [Color(hex: 0xE4F2FC), Color(hex: 0xF7FBFF), Color(hex: 0xFFFFFF)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .dottieGreen:
            return LinearGradient(
                colors: [Color(hex: 0x1F8A2B), Color(hex: 0x43B639), Color(hex: 0x8CE063)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .graffiti:
            return LinearGradient(
                colors: [Color(hex: 0x6E7A8A), Color(hex: 0x95A3B3), Color(hex: 0xCED7E0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .butterflyPattern:
            return LinearGradient(
                colors: [Color(hex: 0x0B4F8A), Color(hex: 0x1778C2), Color(hex: 0x4CA6E8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .silhouette:
            return LinearGradient(
                colors: [Color(hex: 0x09304E), Color(hex: 0x12667A), Color(hex: 0x39B583)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .robot:
            return LinearGradient(
                colors: [Color(hex: 0x2D3748), Color(hex: 0x4A5568), Color(hex: 0x718096)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .morty:
            return LinearGradient(
                colors: [Color(hex: 0xCBD5E1), Color(hex: 0xE2E8F0), Color(hex: 0xF8FAFC)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .scene0001:
            return LinearGradient(
                colors: [Color(hex: 0x0F2B48), Color(hex: 0x1E588A), Color(hex: 0x64B5F6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .scene0002:
            return LinearGradient(
                colors: [Color(hex: 0x78350F), Color(hex: 0xD97706), Color(hex: 0xFCD34D)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .scene0003:
            return LinearGradient(
                colors: [Color(hex: 0xFED7AA), Color(hex: 0xFBCFE8), Color(hex: 0xBFDBFE)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .scene0004:
            return LinearGradient(
                colors: [Color(hex: 0x0F172A), Color(hex: 0x1E3A8A), Color(hex: 0x3B82F6)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .scene0005:
            return LinearGradient(
                colors: [Color(hex: 0x052E16), Color(hex: 0x047857), Color(hex: 0x10B981)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .scene0006:
            return LinearGradient(
                colors: [Color(hex: 0xF1F5F9), Color(hex: 0xF8FAFC), Color(hex: 0xFFFFFF)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .scene0007:
            return LinearGradient(
                colors: [Color(hex: 0x1E293B), Color(hex: 0x334155), Color(hex: 0x64748B)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .scene0008:
            return LinearGradient(
                colors: [Color(hex: 0x3B0764), Color(hex: 0x6B21A8), Color(hex: 0xA855F7)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .zune01:
            return LinearGradient(
                colors: [Color(hex: 0x831843), Color(hex: 0xBE185D), Color(hex: 0xF472B6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .zune02:
            return LinearGradient(
                colors: [Color(hex: 0x7C2D12), Color(hex: 0xC2410C), Color(hex: 0xFB923C)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .zune03:
            return LinearGradient(
                colors: [Color(hex: 0x4C1D95), Color(hex: 0x6D28D9), Color(hex: 0x8B5CF6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .zune04:
            return LinearGradient(
                colors: [Color(hex: 0xE2E8F0), Color(hex: 0xF1F5F9), Color(hex: 0xF8FAFC)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .zune05:
            return LinearGradient(
                colors: [Color(hex: 0x0C4A6E), Color(hex: 0x0369A1), Color(hex: 0x38BDF8)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .zune06:
            return LinearGradient(
                colors: [Color(hex: 0x172554), Color(hex: 0x1D4ED8), Color(hex: 0x60A5FA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Complete 31 WlmUserTile Cases (Exact Android WlmUserTiles.kt Parity)

public enum WlmUserTile: String, CaseIterable, Identifiable, Codable, Sendable {
    case guest = "ic_msn_buddy_avatar"
    case classicGuest = "usertile_guest"
    case dog = "usertile_dog"
    case kitten = "usertile_kitten"
    case daisy = "usertile_daisy"
    case gerberDaisy = "usertile_gerber_daisy"
    case chess = "usertile_chess"
    case chef = "usertile_chef"
    case morty = "usertile_morty"
    case shopping = "usertile_shopping"
    case music = "usertile_music"
    case doctor = "usertile_doctor"
    case tennis = "usertile_tennis"
    case sports = "usertile_sports"
    case electricGuitar = "usertile_electric_guitar"
    case guitar = "usertile_guitar"
    case executive = "usertile_executive"
    case robot = "usertile_robot"
    case basketball = "usertile_basketball"
    case soccer = "usertile_soccer"
    case golf = "usertile_golf"
    case surf = "usertile_surf"
    case leaf = "usertile_leaf"
    case flare = "usertile_flare"
    case seastar = "usertile_seastar"
    case fish = "usertile_fish"
    case bonsai = "usertile_bonsai"
    case spring = "usertile_spring"
    case summer = "usertile_summer"
    case fall = "usertile_fall"
    case winter = "usertile_winter"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .guest: return "MSN Buddy"
        case .classicGuest: return "Guest"
        case .dog: return "Dog"
        case .kitten: return "Kitten"
        case .daisy: return "Daisy"
        case .gerberDaisy: return "Gerber Daisy"
        case .chess: return "Chess"
        case .chef: return "Chef"
        case .morty: return "Morty"
        case .shopping: return "Shopping"
        case .music: return "Music"
        case .doctor: return "Doctor"
        case .tennis: return "Tennis"
        case .sports: return "Sports"
        case .electricGuitar: return "Electric Guitar"
        case .guitar: return "Acoustic Guitar"
        case .executive: return "Executive"
        case .robot: return "Robot"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .golf: return "Golf"
        case .surf: return "Surf"
        case .leaf: return "Leaf"
        case .flare: return "Flare"
        case .seastar: return "Sea Star"
        case .fish: return "Fish"
        case .bonsai: return "Bonsai"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall: return "Autumn"
        case .winter: return "Winter"
        }
    }

    public var systemSymbol: String {
        switch self {
        case .guest: return "person.2.fill"
        case .classicGuest: return "person.fill"
        case .dog: return "pawprint.fill"
        case .kitten: return "cat.fill"
        case .daisy: return "camera.macro"
        case .gerberDaisy: return "camera.macro.circle.fill"
        case .chess: return "crown.fill"
        case .chef: return "fork.knife"
        case .morty: return "face.smiling.inverse"
        case .shopping: return "bag.fill"
        case .music: return "music.note"
        case .doctor: return "cross.case.fill"
        case .tennis: return "tennisball.fill"
        case .sports: return "figure.run"
        case .electricGuitar: return "guitars.fill"
        case .guitar: return "tuningfork"
        case .executive: return "briefcase.fill"
        case .robot: return "desktopcomputer"
        case .basketball: return "basketball.fill"
        case .soccer: return "soccerball"
        case .golf: return "flag.fill"
        case .surf: return "waveform"
        case .leaf: return "leaf.fill"
        case .flare: return "sun.max.fill"
        case .seastar: return "star.fill"
        case .fish: return "fish.fill"
        case .bonsai: return "tree.fill"
        case .spring: return "sparkles"
        case .summer: return "sun.haze.fill"
        case .fall: return "wind"
        case .winter: return "snowflake"
        }
    }

    public var gradientColors: [Color] {
        switch self {
        case .guest, .classicGuest:
            return [Color(hex: 0xD6EFFC), Color(hex: 0x98DBFD)]
        case .dog, .kitten:
            return [Color(hex: 0xFFE4CC), Color(hex: 0xFFB066)]
        case .daisy, .gerberDaisy, .spring:
            return [Color(hex: 0xFFF0F5), Color(hex: 0xFFB6C1)]
        case .chess, .executive, .robot:
            return [Color(hex: 0xE2E8F0), Color(hex: 0x94A3B8)]
        case .chef:
            return [Color(hex: 0xFEE2E2), Color(hex: 0xF87171)]
        case .morty:
            return [Color(hex: 0xFEF08A), Color(hex: 0xEAB308)]
        case .shopping:
            return [Color(hex: 0xFBCFE8), Color(hex: 0xF43F5E)]
        case .music, .electricGuitar, .guitar:
            return [Color(hex: 0xE0E7FF), Color(hex: 0x818CF8)]
        case .doctor:
            return [Color(hex: 0xCCFBF1), Color(hex: 0x2DD4BF)]
        case .tennis, .sports, .basketball, .soccer, .golf:
            return [Color(hex: 0xDCFCE7), Color(hex: 0x4ADE80)]
        case .surf, .fish, .seastar:
            return [Color(hex: 0xBAE6FD), Color(hex: 0x38BDF8)]
        case .leaf, .bonsai:
            return [Color(hex: 0xD1FAE5), Color(hex: 0x10B981)]
        case .flare, .summer:
            return [Color(hex: 0xFEF9C3), Color(hex: 0xFACC15)]
        case .fall:
            return [Color(hex: 0xFFEDD5), Color(hex: 0xFB923C)]
        case .winter:
            return [Color(hex: 0xE0F2FE), Color(hex: 0x7DD3FC)]
        }
    }
}

// MARK: - Frutiger Aero Gradients

public extension LinearGradient {
    /// Iconic WLM 2009 4-stop sky header gradient (`#187FD0` -> `#3EA2EB` -> `#6CB9F3` -> `#A5DCF9`).
    static let wlmSkyHeader = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x187FD0), location: 0.0),
            .init(color: Color(hex: 0x3EA2EB), location: 0.35),
            .init(color: Color(hex: 0x6CB9F3), location: 0.75),
            .init(color: Color(hex: 0xA5DCF9), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Classic MSN Messenger 7.5 header gradient.
    static let msn75Header = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x004E98), location: 0.0),
            .init(color: Color(hex: 0x1D78CD), location: 0.5),
            .init(color: Color(hex: 0x56A6F5), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// WLM 2009 contact row hover/selection highlight gradient.
    static let wlmContactSelection = LinearGradient(
        stops: [
            .init(color: Color(hex: 0xE8F5FD), location: 0.0),
            .init(color: Color(hex: 0xC8E6F8), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Atmospheric Frutiger Aero sky-to-meadow backdrop gradient (Light mode).
    static let wlmAtmosphereLight = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x98DBFD), location: 0.0),
            .init(color: Color(hex: 0xCEEFFD), location: 0.25),
            .init(color: Color(hex: 0xF3F9FD), location: 0.60),
            .init(color: Color(hex: 0xE2F5EB), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Oceanic twilight backdrop gradient (Night Aero Dark mode).
    static let wlmAtmosphereDark = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x09141C), location: 0.0),
            .init(color: Color(hex: 0x0C1922), location: 0.35),
            .init(color: Color(hex: 0x0F161C), location: 0.70),
            .init(color: Color(hex: 0x090E13), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Returns the atmospheric backdrop gradient according to dark mode state.
    static func wlmAtmosphereGradient(isDarkMode: Bool) -> LinearGradient {
        isDarkMode ? .wlmAtmosphereDark : .wlmAtmosphereLight
    }

    /// Alias for wlmSkyHeader gradient.
    static var wlmSkyGradient: LinearGradient {
        .wlmSkyHeader
    }
}

// MARK: - Aero Glass & Glossy Button Modifiers

public struct AeroGlassSheenModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var alpha: Double

    public init(cornerRadius: CGFloat = 18, alpha: Double = 0.25) {
        self.cornerRadius = cornerRadius
        self.alpha = alpha
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(alpha), location: 0.0),
                                .init(color: Color.clear, location: 0.45)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            )
    }
}

public struct AeroSpecularBorderModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var strokeWidth: CGFloat
    public var borderAlpha: Double

    public init(cornerRadius: CGFloat = 18, strokeWidth: CGFloat = 1.0, borderAlpha: Double = 0.55) {
        self.cornerRadius = cornerRadius
        self.strokeWidth = strokeWidth
        self.borderAlpha = borderAlpha
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(borderAlpha), location: 0.0),
                                .init(color: Color.wlmOutline.opacity(0.65), location: 0.5),
                                .init(color: Color.wlmOutline.opacity(0.35), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: strokeWidth
                    )
                    .allowsHitTesting(false)
            )
    }
}

public struct AeroCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var fillOpacity: Double
    public var borderAlpha: Double
    public var sheenAlpha: Double

    public init(
        cornerRadius: CGFloat = 18,
        fillOpacity: Double = 0.88,
        borderAlpha: Double = 0.55,
        sheenAlpha: Double = 0.25
    ) {
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.borderAlpha = borderAlpha
        self.sheenAlpha = sheenAlpha
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .modifier(AeroGlassSheenModifier(cornerRadius: cornerRadius, alpha: sheenAlpha))
            .modifier(AeroSpecularBorderModifier(cornerRadius: cornerRadius, strokeWidth: 1.0, borderAlpha: borderAlpha))
            .shadow(color: Color(hex: 0x003865, alpha: 0.08), radius: 8, x: 0, y: 3)
    }
}

public struct AeroGlossyButtonModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var baseColor: Color
    public var highlightIntensity: Double

    public init(
        cornerRadius: CGFloat = 20,
        baseColor: Color = .wlmPrimary,
        highlightIntensity: Double = 0.35
    ) {
        self.cornerRadius = cornerRadius
        self.baseColor = baseColor
        self.highlightIntensity = highlightIntensity
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [baseColor.opacity(0.92), baseColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .modifier(AeroGlassSheenModifier(cornerRadius: cornerRadius, alpha: highlightIntensity))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.60), location: 0.0),
                                .init(color: Color.white.opacity(0.20), location: 0.6),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: baseColor.opacity(0.30), radius: 4, x: 0, y: 2)
    }
}

public typealias AeroGlassCardModifier = AeroCardModifier

public extension View {
    func aeroGlassSheen(cornerRadius: CGFloat = 18, alpha: Double = 0.25) -> some View {
        modifier(AeroGlassSheenModifier(cornerRadius: cornerRadius, alpha: alpha))
    }

    func aeroSpecularBorder(cornerRadius: CGFloat = 18, strokeWidth: CGFloat = 1.0, borderAlpha: Double = 0.55) -> some View {
        modifier(AeroSpecularBorderModifier(cornerRadius: cornerRadius, strokeWidth: strokeWidth, borderAlpha: borderAlpha))
    }

    func aeroCard(cornerRadius: CGFloat = 18, fillOpacity: Double = 0.88, borderAlpha: Double = 0.55, sheenAlpha: Double = 0.25) -> some View {
        modifier(AeroCardModifier(cornerRadius: cornerRadius, fillOpacity: fillOpacity, borderAlpha: borderAlpha, sheenAlpha: sheenAlpha))
    }

    func aeroGlassCard(cornerRadius: CGFloat = 18, fillOpacity: Double = 0.88, borderAlpha: Double = 0.55, sheenAlpha: Double = 0.25) -> some View {
        aeroCard(cornerRadius: cornerRadius, fillOpacity: fillOpacity, borderAlpha: borderAlpha, sheenAlpha: sheenAlpha)
    }

    func aeroGlossyButton(cornerRadius: CGFloat = 20, baseColor: Color = .wlmPrimary, highlightIntensity: Double = 0.35) -> some View {
        modifier(AeroGlossyButtonModifier(cornerRadius: cornerRadius, baseColor: baseColor, highlightIntensity: highlightIntensity))
    }
}
