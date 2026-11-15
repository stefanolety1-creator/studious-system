import Foundation
import SwiftUI

/// Segoe UI font face options supported by Windows Live Messenger.
public enum NativeFontFace: String, CaseIterable, Codable, Sendable {
    case regular = "Segoe UI"
    case light = "Segoe UI Light"
    case semilight = "Segoe UI Semilight"
    case semibold = "Segoe UI Semibold"
    case black = "Segoe UI Black"

    public var wireName: String { rawValue }

    public var weight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .light: return .light
        case .semilight: return .regular
        case .semibold: return .semibold
        case .black: return .black
        }
    }
}

/// Whole-message styling transmitted in Switchboard `X-MMS-IM-Format` MIME header.
public struct NativeTextStyle: Hashable, Codable, Sendable {
    public var bold: Bool
    public var italic: Bool
    public var strikeout: Bool
    public var underline: Bool
    public var colorRgb: UInt32
    public var fontFace: NativeFontFace

    public init(
        bold: Bool = false,
        italic: Bool = false,
        strikeout: Bool = false,
        underline: Bool = false,
        colorRgb: UInt32 = 0x000000,
        fontFace: NativeFontFace = .regular
    ) {
        self.bold = bold
        self.italic = italic
        self.strikeout = strikeout
        self.underline = underline
        self.colorRgb = colorRgb & 0xFFFFFF
        self.fontFace = fontFace
    }

    /// Serialize to `X-MMS-IM-Format` header value.
    public func toFormatHeader() -> String {
        var effects = ""
        if bold { effects.append("B") }
        if italic { effects.append("I") }
        if strikeout { effects.append("S") }
        if underline { effects.append("U") }

        // RGB to BGR conversion: (R << 16) | (G << 8) | B -> (B << 16) | (G << 8) | R
        let bgr = ((colorRgb & 0xFF) << 16) | (colorRgb & 0xFF00) | ((colorRgb >> 16) & 0xFF)
        let bgrHex = String(bgr, radix: 16)
        let encodedFont = fontFace.wireName.replacingOccurrences(of: " ", with: "%20")
        return "FN=\(encodedFont); EF=\(effects); CO=\(bgrHex); CS=0; PF=22"
    }

    /// Parse from `X-MMS-IM-Format` header value.
    public static func fromFormatHeader(_ header: String?) -> NativeTextStyle {
        guard let header = header, !header.isEmpty else {
            return NativeTextStyle()
        }

        var fields: [String: String] = [:]
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces).uppercased()
                let val = kv[1].trimmingCharacters(in: .whitespaces)
                fields[key] = val
            }
        }

        let effects = fields["EF"]?.uppercased() ?? ""
        let bold = effects.contains("B")
        let italic = effects.contains("I")
        let strikeout = effects.contains("S")
        let underline = effects.contains("U")

        let bgrHex = fields["CO"] ?? ""
        let bgr = UInt32(bgrHex, radix: 16) ?? 0
        let rgb = ((bgr & 0xFF) << 16) | (bgr & 0xFF00) | ((bgr >> 16) & 0xFF)

        let rawFont = fields["FN"]?.removingPercentEncoding ?? ""
        let face = NativeFontFace.allCases.first { $0.wireName.caseInsensitiveCompare(rawFont) == .orderedSame } ?? .regular

        return NativeTextStyle(
            bold: bold,
            italic: italic,
            strikeout: strikeout,
            underline: underline,
            colorRgb: rgb,
            fontFace: face
        )
    }
}
