import SwiftUI

// MARK: - Hex Color Parsing Utility

public extension Color {
    /// Initializes a Color from a 3-char (#RGB), 6-char (#RRGGBB), or 8-char (#AARRGGBB) hex string.
    /// Note: 8-character format defaults to `#AARRGGBB` (Android/MSN standard).
    /// Malformed or invalid hex strings safely fall back to neutral gray (#808080).
    init(hexString: String) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        // Validate length: must be exactly 3, 6, or 8 hex characters
        guard clean.count == 3 || clean.count == 6 || clean.count == 8 else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1.0)
            return
        }

        // Validate that all characters are hexadecimal digits
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard clean.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1.0)
            return
        }

        let scanner = Scanner(string: clean)
        var rgbValue: UInt64 = 0
        guard scanner.scanHexInt64(&rgbValue), scanner.isAtEnd else {
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1.0)
            return
        }

        switch clean.count {
        case 3: // #RGB
            let r = Double((rgbValue >> 8) & 0xF) / 15.0
            let g = Double((rgbValue >> 4) & 0xF) / 15.0
            let b = Double(rgbValue & 0xF) / 15.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
        case 6: // #RRGGBB
            let r = Double((rgbValue >> 16) & 0xFF) / 255.0
            let g = Double((rgbValue >> 8) & 0xFF) / 255.0
            let b = Double(rgbValue & 0xFF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
        case 8: // #AARRGGBB (Android / MSN standard)
            let a = Double((rgbValue >> 24) & 0xFF) / 255.0
            let r = Double((rgbValue >> 16) & 0xFF) / 255.0
            let g = Double((rgbValue >> 8) & 0xFF) / 255.0
            let b = Double(rgbValue & 0xFF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        default:
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1.0)
        }
    }

    /// Safely decodes a hex string to Color, returning nil if invalid or empty.
    /// Supports 3-char (#RGB), 6-char (#RRGGBB), and 8-char (#AARRGGBB Android standard) formats.
    static func fromHex(_ hex: String?) -> Color? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }
        var clean = hex
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        guard clean.count == 3 || clean.count == 6 || clean.count == 8 else {
            return nil
        }

        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard clean.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            return nil
        }

        let scanner = Scanner(string: clean)
        var rgbValue: UInt64 = 0
        guard scanner.scanHexInt64(&rgbValue), scanner.isAtEnd else {
            return nil
        }

        return Color(hexString: hex)
    }
}

// MARK: - Sub-Configuration Structures

public struct SkinStyleConfig: Codable, Sendable, Equatable, Hashable {
    public var enableGlossyEffects: Bool
    public var useWlmTopHeader: Bool
    public var use3dPresenceFrames: Bool
    public var useSkyHeaderGradient: Bool
    public var avatarCornerRadiusDp: Double
    public var cardCornerRadiusDp: Double
    public var buttonCornerRadiusDp: Double
    public var avatarSizeDp: Double?
    public var glassSheenAlpha: Double?
    public var glassBorderAlpha: Double?
    public var cardBorderAlpha: Double?
    public var cardBorderWidthDp: Double?

    public init(
        enableGlossyEffects: Bool = true,
        useWlmTopHeader: Bool = true,
        use3dPresenceFrames: Bool = true,
        useSkyHeaderGradient: Bool = true,
        avatarCornerRadiusDp: Double = 16,
        cardCornerRadiusDp: Double = 18,
        buttonCornerRadiusDp: Double = 24,
        avatarSizeDp: Double? = 56,
        glassSheenAlpha: Double? = 0.45,
        glassBorderAlpha: Double? = 0.35,
        cardBorderAlpha: Double? = 0.35,
        cardBorderWidthDp: Double? = 1.0
    ) {
        self.enableGlossyEffects = enableGlossyEffects
        self.useWlmTopHeader = useWlmTopHeader
        self.use3dPresenceFrames = use3dPresenceFrames
        self.useSkyHeaderGradient = useSkyHeaderGradient
        self.avatarCornerRadiusDp = avatarCornerRadiusDp
        self.cardCornerRadiusDp = cardCornerRadiusDp
        self.buttonCornerRadiusDp = buttonCornerRadiusDp
        self.avatarSizeDp = avatarSizeDp
        self.glassSheenAlpha = glassSheenAlpha
        self.glassBorderAlpha = glassBorderAlpha
        self.cardBorderAlpha = cardBorderAlpha
        self.cardBorderWidthDp = cardBorderWidthDp
    }

    private enum CodingKeys: String, CodingKey {
        case enableGlossyEffects, useWlmTopHeader, use3dPresenceFrames, useSkyHeaderGradient
        case avatarCornerRadiusDp, cardCornerRadiusDp, buttonCornerRadiusDp
        case avatarSizeDp, glassSheenAlpha, glassBorderAlpha, cardBorderAlpha, cardBorderWidthDp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enableGlossyEffects = try container.decodeIfPresent(Bool.self, forKey: .enableGlossyEffects) ?? true
        self.useWlmTopHeader = try container.decodeIfPresent(Bool.self, forKey: .useWlmTopHeader) ?? true
        self.use3dPresenceFrames = try container.decodeIfPresent(Bool.self, forKey: .use3dPresenceFrames) ?? true
        self.useSkyHeaderGradient = try container.decodeIfPresent(Bool.self, forKey: .useSkyHeaderGradient) ?? true
        self.avatarCornerRadiusDp = try container.decodeIfPresent(Double.self, forKey: .avatarCornerRadiusDp) ?? 16
        self.cardCornerRadiusDp = try container.decodeIfPresent(Double.self, forKey: .cardCornerRadiusDp) ?? 18
        self.buttonCornerRadiusDp = try container.decodeIfPresent(Double.self, forKey: .buttonCornerRadiusDp) ?? 24
        self.avatarSizeDp = try container.decodeIfPresent(Double.self, forKey: .avatarSizeDp) ?? 56
        self.glassSheenAlpha = try container.decodeIfPresent(Double.self, forKey: .glassSheenAlpha) ?? 0.45
        self.glassBorderAlpha = try container.decodeIfPresent(Double.self, forKey: .glassBorderAlpha) ?? 0.35
        self.cardBorderAlpha = try container.decodeIfPresent(Double.self, forKey: .cardBorderAlpha) ?? 0.35
        self.cardBorderWidthDp = try container.decodeIfPresent(Double.self, forKey: .cardBorderWidthDp) ?? 1.0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableGlossyEffects, forKey: .enableGlossyEffects)
        try container.encode(useWlmTopHeader, forKey: .useWlmTopHeader)
        try container.encode(use3dPresenceFrames, forKey: .use3dPresenceFrames)
        try container.encode(useSkyHeaderGradient, forKey: .useSkyHeaderGradient)
        try container.encode(avatarCornerRadiusDp, forKey: .avatarCornerRadiusDp)
        try container.encode(cardCornerRadiusDp, forKey: .cardCornerRadiusDp)
        try container.encode(buttonCornerRadiusDp, forKey: .buttonCornerRadiusDp)
        try container.encodeIfPresent(avatarSizeDp, forKey: .avatarSizeDp)
        try container.encodeIfPresent(glassSheenAlpha, forKey: .glassSheenAlpha)
        try container.encodeIfPresent(glassBorderAlpha, forKey: .glassBorderAlpha)
        try container.encodeIfPresent(cardBorderAlpha, forKey: .cardBorderAlpha)
        try container.encodeIfPresent(cardBorderWidthDp, forKey: .cardBorderWidthDp)
    }
}

public struct SkinEffectsConfig: Codable, Sendable, Equatable, Hashable {
    public var glassSheen: Double
    public var borderAlpha: Double
    public var cardBorderWidthDp: Double
    public var cardBorderAlpha: Double?

    public init(
        glassSheen: Double = 0.45,
        borderAlpha: Double = 0.35,
        cardBorderWidthDp: Double = 1.0,
        cardBorderAlpha: Double? = 0.35
    ) {
        self.glassSheen = glassSheen
        self.borderAlpha = borderAlpha
        self.cardBorderWidthDp = cardBorderWidthDp
        self.cardBorderAlpha = cardBorderAlpha
    }

    private enum CodingKeys: String, CodingKey {
        case glassSheen, borderAlpha, cardBorderWidthDp, cardBorderAlpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.glassSheen = try container.decodeIfPresent(Double.self, forKey: .glassSheen) ?? 0.45
        self.borderAlpha = try container.decodeIfPresent(Double.self, forKey: .borderAlpha) ?? 0.35
        self.cardBorderWidthDp = try container.decodeIfPresent(Double.self, forKey: .cardBorderWidthDp) ?? 1.0
        self.cardBorderAlpha = try container.decodeIfPresent(Double.self, forKey: .cardBorderAlpha) ?? 0.35
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(glassSheen, forKey: .glassSheen)
        try container.encode(borderAlpha, forKey: .borderAlpha)
        try container.encode(cardBorderWidthDp, forKey: .cardBorderWidthDp)
        try container.encodeIfPresent(cardBorderAlpha, forKey: .cardBorderAlpha)
    }
}

public struct SkinChatBubblesConfig: Codable, Sendable, Equatable, Hashable {
    public var enabled: Bool
    public var myBubbleColor: String?
    public var myTextColor: String?
    public var peerBubbleColor: String?
    public var peerTextColor: String?
    public var senderTitleMe: String?
    public var senderTitleContact: String?
    public var cornerRadiusDp: Double
    public var borderAlpha: Double

    public init(
        enabled: Bool = false,
        myBubbleColor: String? = "#D6EFFC",
        myTextColor: String? = "#6B7A88",
        peerBubbleColor: String? = "#F3F8FC",
        peerTextColor: String? = "#1B65A4",
        senderTitleMe: String? = "#6B7A88",
        senderTitleContact: String? = "#1B65A4",
        cornerRadiusDp: Double = 14,
        borderAlpha: Double = 0.25
    ) {
        self.enabled = enabled
        self.myBubbleColor = myBubbleColor
        self.myTextColor = myTextColor
        self.peerBubbleColor = peerBubbleColor
        self.peerTextColor = peerTextColor
        self.senderTitleMe = senderTitleMe
        self.senderTitleContact = senderTitleContact
        self.cornerRadiusDp = cornerRadiusDp
        self.borderAlpha = borderAlpha
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, myBubbleColor, myTextColor, peerBubbleColor, peerTextColor
        case senderTitleMe, senderTitleContact, cornerRadiusDp, borderAlpha
        case outgoingBackground, outgoingText, incomingBackground, incomingText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.myBubbleColor = try container.decodeIfPresent(String.self, forKey: .myBubbleColor)
            ?? container.decodeIfPresent(String.self, forKey: .outgoingBackground)
        self.myTextColor = try container.decodeIfPresent(String.self, forKey: .myTextColor)
            ?? container.decodeIfPresent(String.self, forKey: .outgoingText)
        self.peerBubbleColor = try container.decodeIfPresent(String.self, forKey: .peerBubbleColor)
            ?? container.decodeIfPresent(String.self, forKey: .incomingBackground)
        self.peerTextColor = try container.decodeIfPresent(String.self, forKey: .peerTextColor)
            ?? container.decodeIfPresent(String.self, forKey: .incomingText)
        self.senderTitleMe = try container.decodeIfPresent(String.self, forKey: .senderTitleMe)
        self.senderTitleContact = try container.decodeIfPresent(String.self, forKey: .senderTitleContact)
        self.cornerRadiusDp = try container.decodeIfPresent(Double.self, forKey: .cornerRadiusDp) ?? 14
        self.borderAlpha = try container.decodeIfPresent(Double.self, forKey: .borderAlpha) ?? 0.25
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(myBubbleColor, forKey: .myBubbleColor)
        try container.encodeIfPresent(myTextColor, forKey: .myTextColor)
        try container.encodeIfPresent(peerBubbleColor, forKey: .peerBubbleColor)
        try container.encodeIfPresent(peerTextColor, forKey: .peerTextColor)
        try container.encodeIfPresent(senderTitleMe, forKey: .senderTitleMe)
        try container.encodeIfPresent(senderTitleContact, forKey: .senderTitleContact)
        try container.encode(cornerRadiusDp, forKey: .cornerRadiusDp)
        try container.encode(borderAlpha, forKey: .borderAlpha)
    }
}

public struct SkinPresenceColorsConfig: Codable, Sendable, Equatable, Hashable {
    public var online: String
    public var away: String
    public var busy: String
    public var offline: String

    public init(
        online: String = "#5CE02A",
        away: String = "#FFA500",
        busy: String = "#FF2D2D",
        offline: String = "#9E9E9E"
    ) {
        self.online = online
        self.away = away
        self.busy = busy
        self.offline = offline
    }

    private enum CodingKeys: String, CodingKey {
        case online, away, busy, offline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.online = try container.decodeIfPresent(String.self, forKey: .online) ?? "#5CE02A"
        self.away = try container.decodeIfPresent(String.self, forKey: .away) ?? "#FFA500"
        self.busy = try container.decodeIfPresent(String.self, forKey: .busy) ?? "#FF2D2D"
        self.offline = try container.decodeIfPresent(String.self, forKey: .offline) ?? "#9E9E9E"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(online, forKey: .online)
        try container.encode(away, forKey: .away)
        try container.encode(busy, forKey: .busy)
        try container.encode(offline, forKey: .offline)
    }
}

public struct SkinAssetsConfig: Codable, Sendable, Equatable, Hashable {
    public var buddyAvatar: String?
    public var frameOnline: String?
    public var frameAway: String?
    public var frameBusy: String?
    public var frameOffline: String?
    public var preview: String?
    public var headerBackground: String?
    public var chatBackground: String?
    public var chatBackgroundOpacity: Double?
    public var fontFamily: String?

    public init(
        buddyAvatar: String? = "assets/ic_msn_buddy_avatar.png",
        frameOnline: String? = "assets/frame_online.png",
        frameAway: String? = "assets/frame_away.png",
        frameBusy: String? = "assets/frame_busy.png",
        frameOffline: String? = "assets/frame_offline.png",
        preview: String? = "preview.png",
        headerBackground: String? = nil,
        chatBackground: String? = nil,
        chatBackgroundOpacity: Double? = 0.25,
        fontFamily: String? = nil
    ) {
        self.buddyAvatar = buddyAvatar
        self.frameOnline = frameOnline
        self.frameAway = frameAway
        self.frameBusy = frameBusy
        self.frameOffline = frameOffline
        self.preview = preview
        self.headerBackground = headerBackground
        self.chatBackground = chatBackground
        self.chatBackgroundOpacity = chatBackgroundOpacity
        self.fontFamily = fontFamily
    }

    private enum CodingKeys: String, CodingKey {
        case buddyAvatar, frameOnline, frameAway, frameBusy, frameOffline, preview
        case headerBackground, chatBackground, chatBackgroundOpacity, fontFamily
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.buddyAvatar = try container.decodeIfPresent(String.self, forKey: .buddyAvatar) ?? "assets/ic_msn_buddy_avatar.png"
        self.frameOnline = try container.decodeIfPresent(String.self, forKey: .frameOnline) ?? "assets/frame_online.png"
        self.frameAway = try container.decodeIfPresent(String.self, forKey: .frameAway) ?? "assets/frame_away.png"
        self.frameBusy = try container.decodeIfPresent(String.self, forKey: .frameBusy) ?? "assets/frame_busy.png"
        self.frameOffline = try container.decodeIfPresent(String.self, forKey: .frameOffline) ?? "assets/frame_offline.png"
        self.preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? "preview.png"
        self.headerBackground = try container.decodeIfPresent(String.self, forKey: .headerBackground)
        self.chatBackground = try container.decodeIfPresent(String.self, forKey: .chatBackground)
        self.chatBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .chatBackgroundOpacity) ?? 0.25
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(buddyAvatar, forKey: .buddyAvatar)
        try container.encodeIfPresent(frameOnline, forKey: .frameOnline)
        try container.encodeIfPresent(frameAway, forKey: .frameAway)
        try container.encodeIfPresent(frameBusy, forKey: .frameBusy)
        try container.encodeIfPresent(frameOffline, forKey: .frameOffline)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(headerBackground, forKey: .headerBackground)
        try container.encodeIfPresent(chatBackground, forKey: .chatBackground)
        try container.encodeIfPresent(chatBackgroundOpacity, forKey: .chatBackgroundOpacity)
        try container.encodeIfPresent(fontFamily, forKey: .fontFamily)
    }
}

public struct SkinSoundsConfig: Codable, Sendable, Equatable, Hashable {
    public var type: String?
    public var nudge: String?
    public var online: String?
    public var newalert: String?
    public var newemail: String?
    public var ring: String?
    public var callstart: String?

    public init(
        type: String? = "sounds/type.mp3",
        nudge: String? = "sounds/nudge.mp3",
        online: String? = "sounds/online.mp3",
        newalert: String? = "sounds/newalert.mp3",
        newemail: String? = "sounds/newemail.mp3",
        ring: String? = "sounds/phone.mp3",
        callstart: String? = "sounds/outgoing.mp3"
    ) {
        self.type = type
        self.nudge = nudge
        self.online = online
        self.newalert = newalert
        self.newemail = newemail
        self.ring = ring
        self.callstart = callstart
    }

    private enum CodingKeys: String, CodingKey {
        case type, nudge, online, newalert, newemail, ring, callstart
        case message, alert, phone, outgoing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decodeIfPresent(String.self, forKey: .message)
            ?? "sounds/type.mp3"
        self.nudge = try container.decodeIfPresent(String.self, forKey: .nudge)
            ?? "sounds/nudge.mp3"
        self.online = try container.decodeIfPresent(String.self, forKey: .online)
            ?? "sounds/online.mp3"
        self.newalert = try container.decodeIfPresent(String.self, forKey: .newalert)
            ?? container.decodeIfPresent(String.self, forKey: .alert)
            ?? "sounds/newalert.mp3"
        self.newemail = try container.decodeIfPresent(String.self, forKey: .newemail)
            ?? "sounds/newemail.mp3"
        self.ring = try container.decodeIfPresent(String.self, forKey: .ring)
            ?? container.decodeIfPresent(String.self, forKey: .phone)
            ?? "sounds/phone.mp3"
        self.callstart = try container.decodeIfPresent(String.self, forKey: .callstart)
            ?? container.decodeIfPresent(String.self, forKey: .outgoing)
            ?? "sounds/outgoing.mp3"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(nudge, forKey: .nudge)
        try container.encodeIfPresent(online, forKey: .online)
        try container.encodeIfPresent(newalert, forKey: .newalert)
        try container.encodeIfPresent(newemail, forKey: .newemail)
        try container.encodeIfPresent(ring, forKey: .ring)
        try container.encodeIfPresent(callstart, forKey: .callstart)
    }
}

public struct SkinColorsConfig: Codable, Sendable, Equatable, Hashable {
    public var primary: String
    public var onPrimary: String
    public var primaryContainer: String
    public var onPrimaryContainer: String
    public var secondary: String
    public var onSecondary: String
    public var secondaryContainer: String
    public var onSecondaryContainer: String
    public var background: String
    public var onBackground: String
    public var surface: String
    public var onSurface: String
    public var surfaceContainer: String
    public var outline: String
    public var tertiary: String?
    public var onTertiary: String?
    public var tertiaryContainer: String?
    public var onTertiaryContainer: String?
    public var surfaceContainerLow: String?
    public var surfaceContainerHigh: String?
    public var surfaceVariant: String?
    public var onSurfaceVariant: String?
    public var outlineVariant: String?

    public init(
        primary: String,
        onPrimary: String,
        primaryContainer: String,
        onPrimaryContainer: String,
        secondary: String,
        onSecondary: String,
        secondaryContainer: String,
        onSecondaryContainer: String,
        background: String,
        onBackground: String,
        surface: String,
        onSurface: String,
        surfaceContainer: String,
        outline: String,
        tertiary: String? = nil,
        onTertiary: String? = nil,
        tertiaryContainer: String? = nil,
        onTertiaryContainer: String? = nil,
        surfaceContainerLow: String? = nil,
        surfaceContainerHigh: String? = nil,
        surfaceVariant: String? = nil,
        onSurfaceVariant: String? = nil,
        outlineVariant: String? = nil
    ) {
        self.primary = primary
        self.onPrimary = onPrimary
        self.primaryContainer = primaryContainer
        self.onPrimaryContainer = onPrimaryContainer
        self.secondary = secondary
        self.onSecondary = onSecondary
        self.secondaryContainer = secondaryContainer
        self.onSecondaryContainer = onSecondaryContainer
        self.background = background
        self.onBackground = onBackground
        self.surface = surface
        self.onSurface = onSurface
        self.surfaceContainer = surfaceContainer
        self.outline = outline
        self.tertiary = tertiary
        self.onTertiary = onTertiary
        self.tertiaryContainer = tertiaryContainer
        self.onTertiaryContainer = onTertiaryContainer
        self.surfaceContainerLow = surfaceContainerLow
        self.surfaceContainerHigh = surfaceContainerHigh
        self.surfaceVariant = surfaceVariant
        self.onSurfaceVariant = onSurfaceVariant
        self.outlineVariant = outlineVariant
    }

    private enum CodingKeys: String, CodingKey {
        case primary, onPrimary, primaryContainer, onPrimaryContainer
        case secondary, onSecondary, secondaryContainer, onSecondaryContainer
        case background, onBackground, surface, onSurface, surfaceContainer, outline
        case tertiary, onTertiary, tertiaryContainer, onTertiaryContainer
        case surfaceContainerLow, surfaceContainerHigh, surfaceVariant, onSurfaceVariant, outlineVariant
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.primary = try container.decodeIfPresent(String.self, forKey: .primary) ?? "#0078D7"
        self.onPrimary = try container.decodeIfPresent(String.self, forKey: .onPrimary) ?? "#FFFFFF"
        self.primaryContainer = try container.decodeIfPresent(String.self, forKey: .primaryContainer) ?? "#D6EFFC"
        self.onPrimaryContainer = try container.decodeIfPresent(String.self, forKey: .onPrimaryContainer) ?? "#003865"
        self.secondary = try container.decodeIfPresent(String.self, forKey: .secondary) ?? "#32B300"
        self.onSecondary = try container.decodeIfPresent(String.self, forKey: .onSecondary) ?? "#FFFFFF"
        self.secondaryContainer = try container.decodeIfPresent(String.self, forKey: .secondaryContainer) ?? "#DCF7D5"
        self.onSecondaryContainer = try container.decodeIfPresent(String.self, forKey: .onSecondaryContainer) ?? "#0C4000"
        self.background = try container.decodeIfPresent(String.self, forKey: .background) ?? "#FFFFFF"
        self.onBackground = try container.decodeIfPresent(String.self, forKey: .onBackground) ?? "#1C2A39"
        self.surface = try container.decodeIfPresent(String.self, forKey: .surface) ?? "#FFFFFF"
        self.onSurface = try container.decodeIfPresent(String.self, forKey: .onSurface) ?? "#1C2A39"
        self.surfaceContainer = try container.decodeIfPresent(String.self, forKey: .surfaceContainer) ?? "#F3F8FC"
        self.outline = try container.decodeIfPresent(String.self, forKey: .outline) ?? "#B5D7ED"
        self.tertiary = try container.decodeIfPresent(String.self, forKey: .tertiary)
        self.onTertiary = try container.decodeIfPresent(String.self, forKey: .onTertiary)
        self.tertiaryContainer = try container.decodeIfPresent(String.self, forKey: .tertiaryContainer)
        self.onTertiaryContainer = try container.decodeIfPresent(String.self, forKey: .onTertiaryContainer)
        self.surfaceContainerLow = try container.decodeIfPresent(String.self, forKey: .surfaceContainerLow)
        self.surfaceContainerHigh = try container.decodeIfPresent(String.self, forKey: .surfaceContainerHigh)
        self.surfaceVariant = try container.decodeIfPresent(String.self, forKey: .surfaceVariant)
        self.onSurfaceVariant = try container.decodeIfPresent(String.self, forKey: .onSurfaceVariant)
        self.outlineVariant = try container.decodeIfPresent(String.self, forKey: .outlineVariant)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primary, forKey: .primary)
        try container.encode(onPrimary, forKey: .onPrimary)
        try container.encode(primaryContainer, forKey: .primaryContainer)
        try container.encode(onPrimaryContainer, forKey: .onPrimaryContainer)
        try container.encode(secondary, forKey: .secondary)
        try container.encode(onSecondary, forKey: .onSecondary)
        try container.encode(secondaryContainer, forKey: .secondaryContainer)
        try container.encode(onSecondaryContainer, forKey: .onSecondaryContainer)
        try container.encode(background, forKey: .background)
        try container.encode(onBackground, forKey: .onBackground)
        try container.encode(surface, forKey: .surface)
        try container.encode(onSurface, forKey: .onSurface)
        try container.encode(surfaceContainer, forKey: .surfaceContainer)
        try container.encode(outline, forKey: .outline)
        try container.encodeIfPresent(tertiary, forKey: .tertiary)
        try container.encodeIfPresent(onTertiary, forKey: .onTertiary)
        try container.encodeIfPresent(tertiaryContainer, forKey: .tertiaryContainer)
        try container.encodeIfPresent(onTertiaryContainer, forKey: .onTertiaryContainer)
        try container.encodeIfPresent(surfaceContainerLow, forKey: .surfaceContainerLow)
        try container.encodeIfPresent(surfaceContainerHigh, forKey: .surfaceContainerHigh)
        try container.encodeIfPresent(surfaceVariant, forKey: .surfaceVariant)
        try container.encodeIfPresent(onSurfaceVariant, forKey: .onSurfaceVariant)
        try container.encodeIfPresent(outlineVariant, forKey: .outlineVariant)
    }
}

public struct SkinColorPalettesConfig: Codable, Sendable, Equatable, Hashable {
    public var light: SkinColorsConfig
    public var dark: SkinColorsConfig

    public init(
        light: SkinColorsConfig = SkinColorPalettesConfig.standard.light,
        dark: SkinColorsConfig = SkinColorPalettesConfig.standard.dark
    ) {
        self.light = light
        self.dark = dark
    }

    private enum CodingKeys: String, CodingKey {
        case light, dark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultLight = SkinColorPalettesConfig.standard.light
        let defaultDark = SkinColorPalettesConfig.standard.dark
        let decodedLight = try container.decodeIfPresent(SkinColorsConfig.self, forKey: .light) ?? defaultLight
        let decodedDark = try container.decodeIfPresent(SkinColorsConfig.self, forKey: .dark) ?? (container.contains(.light) ? decodedLight : defaultDark)
        self.light = decodedLight
        self.dark = decodedDark
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(light, forKey: .light)
        try container.encode(dark, forKey: .dark)
    }
}

public extension SkinColorPalettesConfig {
    static let standard = SkinColorPalettesConfig(
        light: SkinColorsConfig(
            primary: "#0078D7",
            onPrimary: "#FFFFFF",
            primaryContainer: "#D6EFFC",
            onPrimaryContainer: "#003865",
            secondary: "#32B300",
            onSecondary: "#FFFFFF",
            secondaryContainer: "#DCF7D5",
            onSecondaryContainer: "#0C4000",
            background: "#FFFFFF",
            onBackground: "#1C2A39",
            surface: "#FFFFFF",
            onSurface: "#1C2A39",
            surfaceContainer: "#F3F8FC",
            outline: "#B5D7ED"
        ),
        dark: SkinColorsConfig(
            primary: "#5AC8FA",
            onPrimary: "#003254",
            primaryContainer: "#004F7C",
            onPrimaryContainer: "#CEECFE",
            secondary: "#55E030",
            onSecondary: "#063A00",
            secondaryContainer: "#145408",
            onSecondaryContainer: "#B3F5A4",
            background: "#0D141A",
            onBackground: "#E3EDF4",
            surface: "#121B22",
            onSurface: "#E3EDF4",
            surfaceContainer: "#1E2A34",
            outline: "#3A5163"
        )
    )
}

// MARK: - Compatibility Typealiases

public typealias SkinStyle = SkinStyleConfig
public typealias SkinEffects = SkinEffectsConfig
public typealias SkinChatBubbles = SkinChatBubblesConfig
public typealias SkinPresenceColors = SkinPresenceColorsConfig
public typealias SkinAssets = SkinAssetsConfig
public typealias SkinSounds = SkinSoundsConfig
public typealias SkinPalettePair = SkinColorPalettesConfig
public typealias SkinColorScheme = SkinColorsConfig

// MARK: - Resolved SwiftUI Color Palette

public struct SkinColors: Sendable, Equatable {
    public let primary: Color
    public let onPrimary: Color
    public let primaryContainer: Color
    public let onPrimaryContainer: Color
    public let secondary: Color
    public let onSecondary: Color
    public let secondaryContainer: Color
    public let onSecondaryContainer: Color
    public let background: Color
    public let onBackground: Color
    public let surface: Color
    public let onSurface: Color
    public let surfaceContainer: Color
    public let outline: Color
    public let outlineVariant: Color

    public init(from config: SkinColorsConfig) {
        self.primary = Color(hexString: config.primary)
        self.onPrimary = Color(hexString: config.onPrimary)
        self.primaryContainer = Color(hexString: config.primaryContainer)
        self.onPrimaryContainer = Color(hexString: config.onPrimaryContainer)
        self.secondary = Color(hexString: config.secondary)
        self.onSecondary = Color(hexString: config.onSecondary)
        self.secondaryContainer = Color(hexString: config.secondaryContainer)
        self.onSecondaryContainer = Color(hexString: config.onSecondaryContainer)
        self.background = Color(hexString: config.background)
        self.onBackground = Color(hexString: config.onBackground)
        self.surface = Color(hexString: config.surface)
        self.onSurface = Color(hexString: config.onSurface)
        self.surfaceContainer = Color(hexString: config.surfaceContainer)
        self.outline = Color(hexString: config.outline)
        self.outlineVariant = config.outlineVariant.flatMap(Color.fromHex) ?? Color(hexString: config.outline).opacity(0.5)
    }
}

// MARK: - Main SkinConfig

public struct SkinConfig: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var author: String
    public var version: String
    public var description: String?
    public var appTitle: String?
    public var style: SkinStyleConfig
    public var effects: SkinEffectsConfig
    public var chatBubbles: SkinChatBubblesConfig
    public var presenceColors: SkinPresenceColorsConfig
    public var assets: SkinAssetsConfig
    public var sounds: SkinSoundsConfig
    public var colors: SkinColorPalettesConfig

    public init(
        id: String,
        name: String,
        author: String = "Msngr Team",
        version: String = "1.0",
        description: String? = nil,
        appTitle: String? = nil,
        style: SkinStyleConfig = SkinStyleConfig(),
        effects: SkinEffectsConfig = SkinEffectsConfig(),
        chatBubbles: SkinChatBubblesConfig = SkinChatBubblesConfig(),
        presenceColors: SkinPresenceColorsConfig = SkinPresenceColorsConfig(),
        assets: SkinAssetsConfig = SkinAssetsConfig(),
        sounds: SkinSoundsConfig = SkinSoundsConfig(),
        colors: SkinColorPalettesConfig = .standard
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.version = version
        self.description = description
        self.appTitle = appTitle
        self.style = style
        self.effects = effects
        self.chatBubbles = chatBubbles
        self.presenceColors = presenceColors
        self.assets = assets
        self.sounds = sounds
        self.colors = colors
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, author, version, description, appTitle
        case style, effects, chatBubbles, presenceColors, assets, sounds, colors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? "custom_\(UUID().uuidString.prefix(8))"
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Custom Theme"
        self.author = (try? container.decodeIfPresent(String.self, forKey: .author)) ?? "Community"
        self.version = (try? container.decodeIfPresent(String.self, forKey: .version)) ?? "1.0"
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.appTitle = try? container.decodeIfPresent(String.self, forKey: .appTitle)
        self.style = (try? container.decodeIfPresent(SkinStyleConfig.self, forKey: .style)) ?? SkinStyleConfig()
        self.effects = (try? container.decodeIfPresent(SkinEffectsConfig.self, forKey: .effects)) ?? SkinEffectsConfig()
        self.chatBubbles = (try? container.decodeIfPresent(SkinChatBubblesConfig.self, forKey: .chatBubbles)) ?? SkinChatBubblesConfig()
        self.presenceColors = (try? container.decodeIfPresent(SkinPresenceColorsConfig.self, forKey: .presenceColors)) ?? SkinPresenceColorsConfig()
        self.assets = (try? container.decodeIfPresent(SkinAssetsConfig.self, forKey: .assets)) ?? SkinAssetsConfig()
        self.sounds = (try? container.decodeIfPresent(SkinSoundsConfig.self, forKey: .sounds)) ?? SkinSoundsConfig()
        self.colors = (try? container.decodeIfPresent(SkinColorPalettesConfig.self, forKey: .colors)) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(appTitle, forKey: .appTitle)
        try container.encode(style, forKey: .style)
        try container.encode(effects, forKey: .effects)
        try container.encode(chatBubbles, forKey: .chatBubbles)
        try container.encode(presenceColors, forKey: .presenceColors)
        try container.encode(assets, forKey: .assets)
        try container.encode(sounds, forKey: .sounds)
        try container.encode(colors, forKey: .colors)
    }

    public func resolvedColors(isDarkMode: Bool) -> SkinColors {
        SkinColors(from: isDarkMode ? colors.dark : colors.light)
    }

    public static func decode(from data: Data) throws -> SkinConfig {
        try JSONDecoder().decode(SkinConfig.self, from: data)
    }

    public static func decode(from jsonString: String) throws -> SkinConfig {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Invalid UTF-8 string")
            )
        }
        return try decode(from: data)
    }
}

// MARK: - Static Factory Presets

public extension SkinConfig {
    /// Authentic Windows Live Messenger 2009 Frutiger Aero theme matching Android reference.
    static let wlm2009 = SkinConfig(
        id: "wlm2009",
        name: "Windows Live Messenger 2009",
        author: "Stefano De Luca & Msngr Community",
        version: "2.0",
        description: "Stile autentico Frutiger Aero con finiture in vetro lucido, sfumatura cielo, cornici 3D e pacchetto suoni WLM 2009.",
        appTitle: "Windows Live Messenger",
        style: SkinStyleConfig(
            enableGlossyEffects: true,
            useWlmTopHeader: true,
            use3dPresenceFrames: true,
            useSkyHeaderGradient: true,
            avatarCornerRadiusDp: 16,
            cardCornerRadiusDp: 18,
            buttonCornerRadiusDp: 24,
            avatarSizeDp: 56,
            glassSheenAlpha: 0.45,
            glassBorderAlpha: 0.35,
            cardBorderAlpha: 0.35,
            cardBorderWidthDp: 1.0
        ),
        effects: SkinEffectsConfig(
            glassSheen: 0.45,
            borderAlpha: 0.35,
            cardBorderWidthDp: 1.0,
            cardBorderAlpha: 0.35
        ),
        chatBubbles: SkinChatBubblesConfig(
            enabled: false,
            myBubbleColor: "#D6EFFC",
            myTextColor: "#6B7A88",
            peerBubbleColor: "#F3F8FC",
            peerTextColor: "#1B65A4",
            senderTitleMe: "#6B7A88",
            senderTitleContact: "#1B65A4",
            cornerRadiusDp: 14,
            borderAlpha: 0.25
        ),
        presenceColors: SkinPresenceColorsConfig(
            online: "#5CE02A",
            away: "#FFA500",
            busy: "#FF2D2D",
            offline: "#9E9E9E"
        ),
        assets: SkinAssetsConfig(
            buddyAvatar: "assets/ic_msn_buddy_avatar.png",
            frameOnline: "assets/frame_online.png",
            frameAway: "assets/frame_away.png",
            frameBusy: "assets/frame_busy.png",
            frameOffline: "assets/frame_offline.png",
            preview: "preview.png"
        ),
        sounds: SkinSoundsConfig(
            type: "sounds/type.mp3",
            nudge: "sounds/nudge.mp3",
            online: "sounds/online.mp3",
            newalert: "sounds/newalert.mp3",
            newemail: "sounds/newemail.mp3",
            ring: "sounds/phone.mp3",
            callstart: "sounds/outgoing.mp3"
        ),
        colors: SkinColorPalettesConfig(
            light: SkinColorsConfig(
                primary: "#0078D7",
                onPrimary: "#FFFFFF",
                primaryContainer: "#D6EFFC",
                onPrimaryContainer: "#003865",
                secondary: "#32B300",
                onSecondary: "#FFFFFF",
                secondaryContainer: "#DCF7D5",
                onSecondaryContainer: "#0C4000",
                background: "#FFFFFF",
                onBackground: "#1C2A39",
                surface: "#FFFFFF",
                onSurface: "#1C2A39",
                surfaceContainer: "#F3F8FC",
                outline: "#B5D7ED"
            ),
            dark: SkinColorsConfig(
                primary: "#5AC8FA",
                onPrimary: "#003254",
                primaryContainer: "#004F7C",
                onPrimaryContainer: "#CEECFE",
                secondary: "#55E030",
                onSecondary: "#063A00",
                secondaryContainer: "#145408",
                onSecondaryContainer: "#B3F5A4",
                background: "#0D141A",
                onBackground: "#E3EDF4",
                surface: "#121B22",
                onSurface: "#E3EDF4",
                surfaceContainer: "#1B2731",
                outline: "#4A657C"
            )
        )
    )

    /// Classic MSN Messenger 7.5 Retro theme matching Android reference.
    static let msn75 = SkinConfig(
        id: "msn75",
        name: "MSN Messenger 7.5",
        author: "Stefano De Luca & Msngr Community",
        version: "2.0",
        description: "Look nostalgico classico in blu cobalto e arancione dei primi anni 2000 con pacchetto suoni MSN originale.",
        appTitle: "MSN Messenger",
        style: SkinStyleConfig(
            enableGlossyEffects: true,
            useWlmTopHeader: false,
            use3dPresenceFrames: false,
            useSkyHeaderGradient: true,
            avatarCornerRadiusDp: 8,
            cardCornerRadiusDp: 10,
            buttonCornerRadiusDp: 14,
            avatarSizeDp: 56,
            glassSheenAlpha: 0.25,
            glassBorderAlpha: 0.20,
            cardBorderAlpha: 0.20,
            cardBorderWidthDp: 1.0
        ),
        effects: SkinEffectsConfig(
            glassSheen: 0.25,
            borderAlpha: 0.20,
            cardBorderWidthDp: 1.0,
            cardBorderAlpha: 0.20
        ),
        chatBubbles: SkinChatBubblesConfig(
            enabled: false,
            myBubbleColor: "#D6E7FC",
            myTextColor: "#002347",
            peerBubbleColor: "#E6F0F8",
            peerTextColor: "#0055AA",
            senderTitleMe: "#002347",
            senderTitleContact: "#0055AA",
            cornerRadiusDp: 10,
            borderAlpha: 0.20
        ),
        presenceColors: SkinPresenceColorsConfig(
            online: "#30B32D",
            away: "#E67E00",
            busy: "#D32F2F",
            offline: "#8E8E93"
        ),
        assets: SkinAssetsConfig(
            buddyAvatar: "assets/ic_msn_buddy_avatar.png",
            preview: "preview.png"
        ),
        sounds: SkinSoundsConfig(
            type: "sounds/type.mp3",
            nudge: "sounds/nudge.mp3",
            online: "sounds/online.mp3",
            newalert: "sounds/newalert.mp3",
            newemail: "sounds/newemail.mp3",
            ring: "sounds/phone.mp3",
            callstart: "sounds/outgoing.mp3"
        ),
        colors: SkinColorPalettesConfig(
            light: SkinColorsConfig(
                primary: "#0055AA",
                onPrimary: "#FFFFFF",
                primaryContainer: "#D6E7FC",
                onPrimaryContainer: "#002347",
                secondary: "#E67E00",
                onSecondary: "#FFFFFF",
                secondaryContainer: "#FFE0B2",
                onSecondaryContainer: "#5D2E00",
                background: "#F3F7FA",
                onBackground: "#142436",
                surface: "#FFFFFF",
                onSurface: "#142436",
                surfaceContainer: "#E6F0F8",
                outline: "#A5C2DE"
            ),
            dark: SkinColorsConfig(
                primary: "#72B3FF",
                onPrimary: "#002E5C",
                primaryContainer: "#004687",
                onPrimaryContainer: "#D6E7FC",
                secondary: "#FFB74D",
                onSecondary: "#4E2600",
                secondaryContainer: "#703800",
                onSecondaryContainer: "#FFE0B2",
                background: "#0D1620",
                onBackground: "#E1EAF2",
                surface: "#111E2B",
                onSurface: "#E1EAF2",
                surfaceContainer: "#18293A",
                outline: "#4F6882"
            )
        )
    )

    /// Clean modern unskinned standard theme.
    static let standard = SkinConfig(
        id: "standard",
        name: "Standard Modern",
        author: "Msngr Team",
        version: "1.0",
        description: "Modern clean appearance with standard system curves and colors.",
        appTitle: "Messenger",
        style: SkinStyleConfig(
            enableGlossyEffects: false,
            useWlmTopHeader: false,
            use3dPresenceFrames: false,
            useSkyHeaderGradient: false,
            avatarCornerRadiusDp: 50,
            cardCornerRadiusDp: 14,
            buttonCornerRadiusDp: 20,
            avatarSizeDp: 56,
            glassSheenAlpha: 0.0,
            glassBorderAlpha: 0.15,
            cardBorderAlpha: 0.15,
            cardBorderWidthDp: 1.0
        ),
        effects: SkinEffectsConfig(
            glassSheen: 0.0,
            borderAlpha: 0.15,
            cardBorderWidthDp: 1.0,
            cardBorderAlpha: 0.15
        ),
        chatBubbles: SkinChatBubblesConfig(
            enabled: true,
            myBubbleColor: "#0078D7",
            myTextColor: "#FFFFFF",
            peerBubbleColor: "#E5E5EA",
            peerTextColor: "#000000",
            senderTitleMe: "#0078D7",
            senderTitleContact: "#000000",
            cornerRadiusDp: 18,
            borderAlpha: 0.10
        ),
        presenceColors: SkinPresenceColorsConfig(
            online: "#34C759",
            away: "#FF9500",
            busy: "#FF3B30",
            offline: "#8E8E93"
        ),
        assets: SkinAssetsConfig(),
        sounds: SkinSoundsConfig(),
        colors: SkinColorPalettesConfig(
            light: SkinColorsConfig(
                primary: "#007AFF",
                onPrimary: "#FFFFFF",
                primaryContainer: "#D1E3FF",
                onPrimaryContainer: "#001D33",
                secondary: "#5856D6",
                onSecondary: "#FFFFFF",
                secondaryContainer: "#E5E4FF",
                onSecondaryContainer: "#170B4B",
                background: "#F2F2F7",
                onBackground: "#000000",
                surface: "#FFFFFF",
                onSurface: "#000000",
                surfaceContainer: "#FFFFFF",
                outline: "#C6C6C8"
            ),
            dark: SkinColorsConfig(
                primary: "#0A84FF",
                onPrimary: "#FFFFFF",
                primaryContainer: "#004077",
                onPrimaryContainer: "#D1E3FF",
                secondary: "#5E5CE6",
                onSecondary: "#FFFFFF",
                secondaryContainer: "#2B2A7A",
                onSecondaryContainer: "#E5E4FF",
                background: "#000000",
                onBackground: "#FFFFFF",
                surface: "#1C1C1E",
                onSurface: "#FFFFFF",
                surfaceContainer: "#2C2C2E",
                outline: "#38383A"
            )
        )
    )
}
