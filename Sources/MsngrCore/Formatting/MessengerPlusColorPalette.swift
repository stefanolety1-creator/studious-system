import Foundation
import SwiftUI

/// Represents a 32-bit ARGB color value compatible with Messenger Plus! and SwiftUI.
public struct MessengerPlusColorValue: Hashable, Sendable {
    public let argb: UInt32
    public let wireToken: String
    public let isAdaptive: Bool

    public init(argb: UInt32, wireToken: String, isAdaptive: Bool = false) {
        self.argb = argb
        self.wireToken = wireToken
        self.isAdaptive = isAdaptive
    }

    public var alpha: UInt8 { UInt8((argb >> 24) & 0xFF) }
    public var red: UInt8 { UInt8((argb >> 16) & 0xFF) }
    public var green: UInt8 { UInt8((argb >> 8) & 0xFF) }
    public var blue: UInt8 { UInt8(argb & 0xFF) }

    public var color: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }

    public func hexToken() -> String {
        String(format: "#%06X", argb & 0x00FFFFFF)
    }

    public func binaryToken() -> String {
        if wireToken.hasPrefix("#") || wireToken.allSatisfy({ $0.isNumber }) {
            return wireToken
        }
        return hexToken()
    }

    public static func fromHex(_ value: String) -> MessengerPlusColorValue? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        guard let rgb = UInt32(digits, radix: 16) else { return nil }
        let argb = 0xFF000000 | rgb
        return MessengerPlusColorValue(argb: argb, wireToken: "#\(digits.uppercased())")
    }
}

/// Official Messenger Plus! 5.02.712 68-color palette and color token parser.
public enum MessengerPlusColorPalette {
    private static let rawPaletteHex: [String] = [
        "FFFFFF", "000000", "00007F", "009300", "FF0000", "7F0000", "9C009C", "FC7F00",
        "FFFF00", "00FC00", "009393", "00FFFF", "0000FC", "FF00FF", "7F7F7F", "D2D2D2",
        "E7E6E4", "CFCDD0", "FFDEA4", "FFAEB9", "FFA8FF", "B4B4FC", "BAFBE5", "C1FFA3",
        "FAFDA2", "B6B4B7", "A2A0A1", "F9C152", "FF6D66", "FF62FF", "6C6CFF", "68FFC3",
        "8EFF67", "F9FF57", "858482", "6E6D7B", "FFA01E", "F92611", "FF20FF", "202BFF",
        "1EFFA5", "60F913", "FFF813", "5E6464", "4B494C", "D98812", "EB0505", "DE00DE",
        "0000D3", "03CC88", "59D80D", "D4C804", "333335", "18171C", "944E00", "9B0008",
        "980299", "01038C", "01885F", "389600", "9A9E15", "473400", "4D0000", "5F0162",
        "000047", "06502F", "1C5300", "544D05"
    ]

    private static let classicNames: [String] = [
        "White", "Black", "Dark blue", "Dark green", "Red", "Dark red", "Purple", "Orange",
        "Yellow", "Light green", "Teal", "Cyan", "Blue", "Magenta", "Gray", "Light gray"
    ]

    /// The 68 official palette colors.
    public static let palette: [MessengerPlusColorValue] = {
        rawPaletteHex.enumerated().map { index, hex in
            let rgb = UInt32(hex, radix: 16)!
            let wireToken = String(format: "%02d", index)
            return MessengerPlusColorValue(argb: 0xFF000000 | rgb, wireToken: wireToken)
        }
    }()

    /// The 16 named colors supported by Messenger Plus!.
    public static let namedColors: [String: UInt32] = [
        "white": 0xFFFFFF, "black": 0x000000, "red": 0xFF0000, "yellow": 0xFFFF00,
        "pink": 0xFFC0CB, "green": 0x008000, "orange": 0xFFA500, "purple": 0x800080,
        "blue": 0x0000FF, "beige": 0xF5F5DC, "brown": 0xA52A2A, "teal": 0x008080,
        "navy": 0x000080, "maroon": 0x800000, "limegreen": 0x32CD32, "gray": 0x808080
    ]

    /// Lookup a color by palette index (0–67).
    public static func paletteColor(index: Int) -> MessengerPlusColorValue? {
        guard index >= 0 && index < palette.count else { return nil }
        return palette[index]
    }

    /// Parse any color token (hex, palette index, named color, or "adapt").
    public static func parseColorToken(_ token: String, adaptiveColor: UInt32 = 0xFF000000) -> MessengerPlusColorValue? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("adapt") == .orderedSame {
            return MessengerPlusColorValue(argb: adaptiveColor, wireToken: "adapt", isAdaptive: true)
        }
        if trimmed.hasPrefix("#") {
            let prefix = String(trimmed.prefix(7))
            return MessengerPlusColorValue.fromHex(prefix)
        }
        if (1...2).contains(trimmed.count), trimmed.allSatisfy({ $0.isNumber }), let index = Int(trimmed) {
            if let paletteCol = paletteColor(index: index) {
                return paletteCol
            }
            // Out-of-range palette IDs 68–99 resolve to black
            if index <= 99 {
                return MessengerPlusColorValue(argb: 0xFF000000, wireToken: trimmed)
            }
        }
        if let rgb = namedColors[trimmed.lowercased()] {
            return MessengerPlusColorValue(argb: 0xFF000000 | rgb, wireToken: trimmed)
        }
        return nil
    }
}
