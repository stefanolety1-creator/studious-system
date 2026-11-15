import SwiftUI
import MsngrCore

/// Compact 13x13pt glossy square presence icon matching Windows Live Messenger 2009 (`MsnPresenceIcon`).
public struct MsnPresenceIcon: View {
    public let status: PresenceStatus
    public var size: CGFloat

    public init(status: PresenceStatus, size: CGFloat = 13) {
        self.status = status
        self.size = size
    }

    public var fillGradient: LinearGradient {
        switch status {
        case .online:
            return LinearGradient(
                colors: [.msnOnline, .msnOnline.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .busy, .onThePhone:
            return LinearGradient(
                colors: [.msnBusy, .msnBusy.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .away, .idle, .beRightBack, .outToLunch:
            return LinearGradient(
                colors: [.msnAway, .msnAway.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .hidden, .offline:
            return LinearGradient(
                colors: [.msnOfflineTop, .msnOffline],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    public var borderColor: Color {
        switch status {
        case .online:
            return .msnOnlineBorder
        case .busy, .onThePhone:
            return .msnBusyBorder
        case .away, .idle, .beRightBack, .outToLunch:
            return .msnAwayBorder
        case .hidden, .offline:
            return .msnOffline
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

/// 3D glowing squircle presence avatar frame (`frame_online`, `frame_busy`, `frame_away`, `frame_offline`).
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

    public var frameAccentColor: Color {
        switch status {
        case .online:
            return .msnOnline
        case .busy, .onThePhone:
            return .msnBusy
        case .away, .idle, .beRightBack, .outToLunch:
            return .msnAway
        case .hidden, .offline:
            return .msnOffline
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
                .shadow(color: frameAccentColor.opacity(status.isOnline ? 0.55 : 0.15), radius: 5, x: 0, y: 2)

            // Inner user tile
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0xD6EFFC), Color(hex: 0x98DBFD)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let symbolName = symbolName {
                    Image(systemName: symbolName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: innerSize * 0.55, height: innerSize * 0.55)
                        .foregroundStyle(Color.wlmOnPrimaryContainer)
                } else {
                    Text(initials)
                        .font(.system(size: innerSize * 0.44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.wlmOnPrimaryContainer)
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
}
