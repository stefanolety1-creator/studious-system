import SwiftUI

// MARK: - Hex Color Extension

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

// MARK: - Aero Skins & Scenes

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

public enum WlmScene: String, CaseIterable, Identifiable, Codable, Sendable {
    case sky = "Windows Live Sky"
    case carbonFiber = "Carbon Fiber"
    case mesmerizingWhite = "Mesmerizing White"
    case dottieGreen = "Spring Meadow"
    case butterflyDamask = "Butterfly Damask"
    case vistaSilhouette = "Aurora Horizon"
    case zuneOrange = "Zune Sunset"

    public var id: String { rawValue }

    public var isDarkText: Bool {
        self == .mesmerizingWhite
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
        case .butterflyDamask:
            return LinearGradient(
                colors: [Color(hex: 0x0B4F8A), Color(hex: 0x1778C2), Color(hex: 0x4CA6E8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .vistaSilhouette:
            return LinearGradient(
                colors: [Color(hex: 0x09304E), Color(hex: 0x12667A), Color(hex: 0x39B583)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .zuneOrange:
            return LinearGradient(
                colors: [Color(hex: 0x7A1C54), Color(hex: 0xC83E4D), Color(hex: 0xF28C28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
}

// MARK: - Aero Glass & Glossy Button Modifiers

public struct AeroGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var fillOpacity: Double
    public var borderAlpha: Double
    public var sheenAlpha: Double

    public init(
        cornerRadius: CGFloat = 18,
        fillOpacity: Double = 0.88,
        borderAlpha: Double = 0.55,
        sheenAlpha: Double = 0.22
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
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(sheenAlpha), location: 0.0),
                                        .init(color: Color.clear, location: 0.45)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
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
                        lineWidth: 1
                    )
            )
            .shadow(color: Color(hex: 0x003865, alpha: 0.08), radius: 10, x: 0, y: 4)
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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(highlightIntensity), location: 0.0),
                                .init(color: Color.clear, location: 0.50)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            )
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

public extension View {
    func aeroGlassCard(
        cornerRadius: CGFloat = 18,
        fillOpacity: Double = 0.88,
        borderAlpha: Double = 0.55,
        sheenAlpha: Double = 0.22
    ) -> some View {
        modifier(AeroGlassCardModifier(
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity,
            borderAlpha: borderAlpha,
            sheenAlpha: sheenAlpha
        ))
    }

    func aeroGlossyButton(
        cornerRadius: CGFloat = 20,
        baseColor: Color = .wlmPrimary,
        highlightIntensity: Double = 0.35
    ) -> some View {
        modifier(AeroGlossyButtonModifier(
            cornerRadius: cornerRadius,
            baseColor: baseColor,
            highlightIntensity: highlightIntensity
        ))
    }
}
