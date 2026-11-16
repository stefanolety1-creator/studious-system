import SwiftUI
import MsngrCore

// MARK: - Extension for Status Aliases

public extension PresenceStatus {
    static var invisible: PresenceStatus { .hidden }
}

// MARK: - 3D Glossy Presence Indicator Orb (PresenceDot)

/// Authentic 3D spherical glossy presence dot matching Android `PresenceDot`.
public struct PresenceDot: View {
    public let presence: PresenceStatus
    public var size: CGFloat

    public init(presence: PresenceStatus, size: CGFloat = 12) {
        self.presence = presence
        self.size = size
    }

    public init(status: PresenceStatus, size: CGFloat = 12) {
        self.presence = status
        self.size = size
    }

    public var baseColor: Color {
        switch presence {
        case .online:
            return Color(hex: 0x6AE633)
        case .busy, .onThePhone:
            return Color(hex: 0xFF4D4D)
        case .away, .idle, .beRightBack, .outToLunch:
            return Color(hex: 0xFFC107)
        case .hidden, .offline:
            return Color(hex: 0x90A4AE)
        }
    }

    public var body: some View {
        ZStack {
            // Base sphere
            Circle()
                .fill(baseColor)

            // Radial ambient depth shadow (lower-right depth)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.clear, Color.black.opacity(0.38)],
                        center: .center,
                        startRadius: size * 0.20,
                        endRadius: size * 0.50
                    )
                )

            // Specular gloss highlight (top-left 0.35, 0.30)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color.white.opacity(0.35),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 0,
                        endRadius: size * 0.40
                    )
                )

            // Glass rim stroke
            Circle()
                .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.75)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - PresenceBadgeView (13x13pt Glossy Square Badge)

/// Authentic 13x13pt glossy square presence icon matching Windows Live Messenger 2009.
public struct PresenceBadgeView: View {
    public let presence: PresenceStatus
    public var size: CGFloat

    public init(presence: PresenceStatus, size: CGFloat = 13) {
        self.presence = presence
        self.size = size
    }

    public init(status: PresenceStatus, size: CGFloat = 13) {
        self.presence = status
        self.size = size
    }

    public var fillGradient: LinearGradient {
        switch presence {
        case .online:
            return LinearGradient(
                colors: [Color(hex: 0x6AE633), Color(hex: 0x6AE633).opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .busy, .onThePhone:
            return LinearGradient(
                colors: [Color(hex: 0xFF4D4D), Color(hex: 0xFF4D4D).opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .away, .idle, .beRightBack, .outToLunch:
            return LinearGradient(
                colors: [Color(hex: 0xFFC107), Color(hex: 0xFFC107).opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .hidden, .offline:
            return LinearGradient(
                colors: [Color(hex: 0xCFD8DC), Color(hex: 0x90A4AE)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    public var borderColor: Color {
        switch presence {
        case .online:
            return Color(hex: 0x166B0A)
        case .busy, .onThePhone:
            return Color(hex: 0x8B0000)
        case .away, .idle, .beRightBack, .outToLunch:
            return Color(hex: 0xB26500)
        case .hidden, .offline:
            return Color(hex: 0x90A4AE)
        }
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fillGradient)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.65), location: 0.0),
                                .init(color: Color.clear, location: 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Legacy MsnPresenceIcon (Backward Compatibility)

public struct MsnPresenceIcon: View {
    public let status: PresenceStatus
    public var size: CGFloat

    public init(status: PresenceStatus, size: CGFloat = 13) {
        self.status = status
        self.size = size
    }

    public init(presence: PresenceStatus, size: CGFloat = 13) {
        self.status = presence
        self.size = size
    }

    public var body: some View {
        PresenceBadgeView(presence: status, size: size)
    }
}

// MARK: - AvatarWithPresenceFrame (3D Glowing Squircle Presence Frame)

/// Authentic 3D glowing squircle presence avatar frame with inner user tile and specular glass sheen.
public struct AvatarWithPresenceFrame: View {
    public let avatarUrl: URL?
    public let displayName: String
    public let presence: PresenceStatus
    public var size: CGFloat
    public var symbolName: String?
    public var userTile: WlmUserTile?

    public init(
        avatarUrl: URL? = nil,
        presence: PresenceStatus = .online,
        size: CGFloat = 56,
        displayName: String = "",
        symbolName: String? = nil,
        userTile: WlmUserTile? = nil
    ) {
        self.avatarUrl = avatarUrl
        self.displayName = displayName
        self.presence = presence
        self.size = size
        self.symbolName = symbolName
        self.userTile = userTile
    }

    public var frameAccentColor: Color {
        switch presence {
        case .online:
            return Color(hex: 0x6AE633)
        case .busy, .onThePhone:
            return Color(hex: 0xFF4D4D)
        case .away, .idle, .beRightBack, .outToLunch:
            return Color(hex: 0xFFC107)
        case .hidden, .offline:
            return Color(hex: 0x90A4AE)
        }
    }

    private var initials: String {
        let cleaned = MessengerPlusParser.stripFormatting(displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.first else { return "M" }
        return String(first).uppercased()
    }

    public var body: some View {
        let innerSize = size * 0.84
        let cornerRadius = max(6, size * 0.14)

        ZStack {
            // Outer 3D glowing bezel
            RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            frameAccentColor.opacity(0.95),
                            frameAccentColor.opacity(0.55),
                            frameAccentColor.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: frameAccentColor.opacity(presence.isOnline ? 0.55 : 0.15), radius: 5, x: 0, y: 2)

            // Inner user tile / avatar content
            ZStack {
                let tile = userTile ?? .guest
                LinearGradient(
                    colors: tile.gradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let avatarUrl = avatarUrl {
                    AsyncImage(url: avatarUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            fallbackTileContent(innerSize: innerSize, tile: tile)
                        }
                    }
                } else {
                    fallbackTileContent(innerSize: innerSize, tile: tile)
                }
            }
            .frame(width: innerSize, height: innerSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )

            // Top specular glass reflection over frame
            RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.50), location: 0.0),
                            .init(color: Color.clear, location: 0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func fallbackTileContent(innerSize: CGFloat, tile: WlmUserTile) -> some View {
        if let symbolName = symbolName ?? (userTile?.systemSymbol) {
            Image(systemName: symbolName)
                .resizable()
                .scaledToFit()
                .frame(width: innerSize * 0.55, height: innerSize * 0.55)
                .foregroundStyle(Color(hex: 0x003865))
        } else if !displayName.isEmpty {
            Text(initials)
                .font(.system(size: innerSize * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x003865))
        } else {
            Image(systemName: tile.systemSymbol)
                .resizable()
                .scaledToFit()
                .frame(width: innerSize * 0.55, height: innerSize * 0.55)
                .foregroundStyle(Color(hex: 0x003865))
        }
    }
}

// MARK: - Legacy AeroAvatarFrameView (Backward Compatibility)

public struct AeroAvatarFrameView: View {
    public let displayName: String
    public let status: PresenceStatus
    public var size: CGFloat
    public var symbolName: String?

    public init(
        displayName: String,
        status: PresenceStatus,
        size: CGFloat = 56,
        symbolName: String? = nil
    ) {
        self.displayName = displayName
        self.status = status
        self.size = size
        self.symbolName = symbolName
    }

    public var body: some View {
        AvatarWithPresenceFrame(
            avatarUrl: nil,
            presence: status,
            size: size,
            displayName: displayName,
            symbolName: symbolName
        )
    }
}
