import Foundation
import SwiftUI

/// Represents formatting styling for a character or text run.
public struct MessengerPlusStyle: Hashable, Sendable {
    public var bold: Bool = false
    public var italic: Bool = false
    public var underline: Bool = false
    public var strikeout: Bool = false
    public var foreground: MessengerPlusColorValue? = nil
    public var background: MessengerPlusColorValue? = nil

    public init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikeout: Bool = false,
        foreground: MessengerPlusColorValue? = nil,
        background: MessengerPlusColorValue? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikeout = strikeout
        self.foreground = foreground
        self.background = background
    }
}

/// A parsed glyph with source range and applied styling.
public struct MessengerPlusGlyph: Sendable {
    public let sourceStart: Int
    public let sourceEnd: Int
    public let value: String
    public var style: MessengerPlusStyle
}

/// Complete Messenger Plus! parser producing styled SwiftUI `AttributedString`.
public struct MessengerPlusParser {
    public static let boldControl: Character = "\u{0002}"
    public static let colorControl: Character = "\u{0003}"
    public static let italicControl: Character = "\u{0005}"
    public static let strikeoutControl: Character = "\u{0006}"
    public static let resetControl: Character = "\u{000F}"
    public static let underlineControl: Character = "\u{001F}"
    public static let middleDot: Character = "\u{00B7}"

    // Regex pattern matching tags: [b], [/b], [c=...], [/c=...], etc.
    private static let tagRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"(?:\[(/?)([biusn])\])|(?:\[(/?)([ca])(?:=([^\]\r\n]+))?\])"#,
                options: [.caseInsensitive]
            )
        } catch {
            fatalError("Failed to initialize tag regex: \(error)")
        }
    }()

    private final class Tag {
        let start: Int
        let end: Int
        let kind: Character
        let closing: Bool
        let argument: String?
        var partner: Tag?

        init(start: Int, end: Int, kind: Character, closing: Bool, argument: String?) {
            self.start = start
            self.end = end
            self.kind = kind
            self.closing = closing
            self.argument = argument
        }
    }

    /// Strips all Messenger Plus! BBCode, binary C0 controls, and readable aliases, returning pure unformatted text.
    public static func stripFormatting(_ source: String) -> String {
        let parsed = parse(source)
        return parsed.glyphs.map(\.value).joined()
    }

    /// Parses source text into a SwiftUI `AttributedString` with given adaptive color and optional base native style.
    public static func parseToAttributedString(
        _ source: String,
        adaptiveColor: Color = .primary,
        nativeStyle: NativeTextStyle = NativeTextStyle(),
        baseFontSize: CGFloat = 14
    ) -> AttributedString {
        let parsed = parse(source, adaptiveColorArgb: 0xFF000000)
        if parsed.glyphs.isEmpty {
            return AttributedString("")
        }

        var result = AttributedString()
        var currentRunText = ""
        var currentRunStyle: MessengerPlusStyle?

        func flushRun() {
            guard !currentRunText.isEmpty, let style = currentRunStyle else { return }
            var container = AttributeContainer()

            let isBold = style.bold || nativeStyle.bold
            let isItalic = style.italic || nativeStyle.italic
            let isUnderline = style.underline || nativeStyle.underline
            let isStrikeout = style.strikeout || nativeStyle.strikeout

            var font = Font.system(size: baseFontSize, weight: nativeStyle.fontFace.weight)
            if isBold { font = font.bold() }
            if isItalic { font = font.italic() }
            container.font = font

            if isUnderline { container.underlineStyle = .single }
            if isStrikeout { container.strikethroughStyle = .single }

            if let fg = style.foreground {
                if fg.isAdaptive {
                    container.foregroundColor = adaptiveColor
                } else {
                    container.foregroundColor = fg.color
                }
            } else if nativeStyle.colorRgb != 0 {
                let r = Double((nativeStyle.colorRgb >> 16) & 0xFF) / 255.0
                let g = Double((nativeStyle.colorRgb >> 8) & 0xFF) / 255.0
                let b = Double(nativeStyle.colorRgb & 0xFF) / 255.0
                container.foregroundColor = Color(red: r, green: g, blue: b)
            } else {
                container.foregroundColor = adaptiveColor
            }

            if let bg = style.background {
                container.backgroundColor = bg.color
            }

            var runAttr = AttributedString(currentRunText)
            runAttr.setAttributes(container)
            result.append(runAttr)

            currentRunText = ""
        }

        for glyph in parsed.glyphs {
            if currentRunStyle == nil {
                currentRunStyle = glyph.style
                currentRunText.append(glyph.value)
            } else if currentRunStyle == glyph.style {
                currentRunText.append(glyph.value)
            } else {
                flushRun()
                currentRunStyle = glyph.style
                currentRunText.append(glyph.value)
            }
        }
        flushRun()

        return result
    }

    /// Internal parse representation returning glyphs with exact styles.
    public static func parse(
        _ source: String,
        adaptiveColorArgb: UInt32 = 0xFF000000
    ) -> (text: String, glyphs: [MessengerPlusGlyph]) {
        let utf16 = Array(source.utf16)
        let limit = utf16.firstIndex(of: 0) ?? utf16.count

        let tags = matchTags(in: utf16, limit: limit)
        let tagsByStart = Dictionary(uniqueKeysWithValues: tags.map { ($0.start, $0) })

        var glyphs: [MessengerPlusGlyph] = []
        var fgOwners: [Tag?] = []
        var bgOwners: [Tag?] = []

        var binary = MessengerPlusStyle()
        var binaryFgStart = -1
        var binaryBgStart = -1
        var activeTags: [Tag] = []

        func colorOwner(_ kind: Character, binaryStart: Int) -> Tag? {
            if binaryStart >= 0 { return nil }
            return activeTags.last {
                $0.kind == kind && MessengerPlusColorPalette.parseColorToken($0.argument ?? "", adaptiveColor: adaptiveColorArgb) != nil
            }
        }

        func currentComputedStyle() -> MessengerPlusStyle {
            let fgTag = colorOwner("c", binaryStart: binaryFgStart)
            let bgTag = colorOwner("a", binaryStart: binaryBgStart)
            let fg = fgTag.flatMap { MessengerPlusColorPalette.parseColorToken($0.argument ?? "", adaptiveColor: adaptiveColorArgb) } ?? binary.foreground
            let bg = bgTag.flatMap { MessengerPlusColorPalette.parseColorToken($0.argument ?? "", adaptiveColor: adaptiveColorArgb) } ?? binary.background

            return MessengerPlusStyle(
                bold: binary.bold || activeTags.contains { $0.kind == "b" },
                italic: binary.italic || activeTags.contains { $0.kind == "i" },
                underline: binary.underline || activeTags.contains { $0.kind == "u" },
                strikeout: binary.strikeout || activeTags.contains { $0.kind == "s" },
                foreground: fg,
                background: bg
            )
        }

        var index = 0
        while index < limit {
            let start = index
            let tag = tagsByStart[index]
            let control = binaryControlAt(utf16: utf16, index: index, limit: limit)

            if let tag = tag {
                if tag.closing {
                    if let partner = tag.partner {
                        activeTags.removeAll { $0 === partner }
                    }
                } else {
                    activeTags.append(tag)
                }
                index = tag.end
            } else if let control = control {
                index += control.length
                switch control.code {
                case boldControl:
                    binary.bold.toggle()
                case italicControl:
                    binary.italic.toggle()
                case underlineControl:
                    binary.underline.toggle()
                case strikeoutControl:
                    binary.strikeout.toggle()
                case resetControl:
                    binary = MessengerPlusStyle()
                    binaryFgStart = -1
                    binaryBgStart = -1
                case colorControl:
                    let (fgCol, nextIdx) = binaryColorAt(utf16: utf16, start: index, limit: limit)
                    var curIdx = nextIdx
                    var bgCol: MessengerPlusColorValue? = nil
                    if curIdx < limit && utf16[curIdx] == 0x2C /* ',' */ {
                        let (parsedBg, afterBg) = binaryColorAt(utf16: utf16, start: curIdx + 1, limit: limit)
                        if let parsedBg = parsedBg {
                            bgCol = parsedBg
                            curIdx = afterBg
                        }
                    }
                    index = curIdx

                    if fgCol == nil && bgCol == nil {
                        binary.foreground = nil
                        binary.background = nil
                        binaryFgStart = -1
                        binaryBgStart = -1
                    } else {
                        if let fg = fgCol {
                            binary.foreground = fg
                            binaryFgStart = start
                        }
                        if let bg = bgCol {
                            binary.background = bg
                            binaryBgStart = start
                        }
                    }
                default:
                    break
                }
            } else {
                let codeUnit = utf16[index]
                let scalarLength: Int
                let charString: String
                if (0xD800...0xDBFF).contains(codeUnit) && index + 1 < limit && (0xDC00...0xDFFF).contains(utf16[index + 1]) {
                    scalarLength = 2
                    charString = String(decoding: [codeUnit, utf16[index + 1]], as: UTF16.self)
                } else {
                    scalarLength = 1
                    charString = String(decoding: [codeUnit], as: UTF16.self)
                }
                index += scalarLength

                let style = currentComputedStyle()
                glyphs.append(MessengerPlusGlyph(sourceStart: start, sourceEnd: index, value: charString, style: style))
                fgOwners.append(colorOwner("c", binaryStart: binaryFgStart))
                bgOwners.append(colorOwner("a", binaryStart: binaryBgStart))
            }
        }

        // Apply linear gradients
        applyGradients(glyphs: &glyphs, owners: fgOwners, isBackground: false, adaptiveColor: adaptiveColorArgb)
        applyGradients(glyphs: &glyphs, owners: bgOwners, isBackground: true, adaptiveColor: adaptiveColorArgb)

        let plain = glyphs.map(\.value).joined()
        return (plain, glyphs)
    }

    private static func matchTags(in utf16: [UInt16], limit: Int) -> [Tag] {
        let string = String(decoding: utf16[0..<limit], as: UTF16.self)
        let nsString = string as NSString
        let matches = tagRegex.matches(in: string, range: NSRange(location: 0, length: nsString.length))

        var tokens: [Tag] = []
        for match in matches {
            let basicRange = match.range(at: 2)
            let isBasic = basicRange.location != NSNotFound

            let kindRange = isBasic ? basicRange : match.range(at: 4)
            guard kindRange.location != NSNotFound else { continue }
            let kindChar = Character(nsString.substring(with: kindRange).lowercased())

            let closingRange = isBasic ? match.range(at: 1) : match.range(at: 3)
            let isClosing = closingRange.location != NSNotFound && closingRange.length > 0

            let argRange = match.range(at: 5)
            let argument = argRange.location != NSNotFound ? nsString.substring(with: argRange) : nil

            if !isBasic && !isClosing && argument == nil {
                continue
            }

            tokens.append(Tag(
                start: match.range.location,
                end: match.range.location + match.range.length,
                kind: kindChar,
                closing: isClosing,
                argument: argument
            ))
        }

        // Right-to-left pairing for [n] (no-parse literal mode)
        var noParsePairs: [(open: Tag, close: Tag)] = []
        var noParseClose: Tag? = nil
        for tag in tokens.reversed() where tag.kind == "n" {
            if tag.closing && noParseClose == nil {
                noParseClose = tag
            } else if !tag.closing, let close = noParseClose {
                noParsePairs.append((tag, close))
                tag.partner = close
                close.partner = tag
                noParseClose = nil
            }
        }

        // Pair other BBCode tags
        var stacks: [Character: [Tag]] = [:]
        for tag in tokens where tag.kind != "n" {
            if !tag.closing {
                let insideNoParse = noParsePairs.contains { tag.start >= $0.open.end && tag.start < $0.close.start }
                if !insideNoParse {
                    stacks[tag.kind, default: []].append(tag)
                }
            } else if var stack = stacks[tag.kind], !stack.isEmpty {
                let open = stack.removeLast()
                stacks[tag.kind] = stack
                open.partner = tag
                tag.partner = open
            }
        }

        return tokens.filter { $0.partner != nil }
    }

    private static func binaryControlAt(utf16: [UInt16], index: Int, limit: Int) -> (code: Character, length: Int)? {
        let cu = utf16[index]
        switch cu {
        case 0x02: return (boldControl, 1)
        case 0x03: return (colorControl, 1)
        case 0x05: return (italicControl, 1)
        case 0x06: return (strikeoutControl, 1)
        case 0x0F: return (resetControl, 1)
        case 0x1F: return (underlineControl, 1)
        default: break
        }

        // Middle dot readable aliases (·#, ·$, etc.)
        if cu == 0x00B7 && index + 1 < limit {
            let next = utf16[index + 1]
            switch next {
            case 0x23 /* '#' */: return (boldControl, 2)
            case 0x24 /* '$' */: return (colorControl, 2)
            case 0x26 /* '&' */: return (italicControl, 2)
            case 0x40 /* '@' */: return (underlineControl, 2)
            case 0x27 /* ''' */: return (strikeoutControl, 2)
            case 0x30 /* '0' */: return (resetControl, 2)
            default: return nil
            }
        }
        return nil
    }

    private static func binaryColorAt(utf16: [UInt16], start: Int, limit: Int) -> (color: MessengerPlusColorValue?, nextIndex: Int) {
        guard start < limit else { return (nil, start) }
        let cu = utf16[start]
        var end = start
        if cu == 0x23 /* '#' */ {
            end = start + 7
        } else if cu >= 0x30 && cu <= 0x39 /* '0'...'9' */ {
            if start + 1 < limit && utf16[start + 1] >= 0x30 && utf16[start + 1] <= 0x39 {
                end = start + 2
            } else {
                end = start + 1
            }
        } else {
            return (nil, start)
        }

        if end > limit { return (nil, start) }
        let token = String(decoding: utf16[start..<end], as: UTF16.self)
        if let val = MessengerPlusColorPalette.parseColorToken(token) {
            return (val, end)
        }
        return (nil, start)
    }

    private static func applyGradients(
        glyphs: inout [MessengerPlusGlyph],
        owners: [Tag?],
        isBackground: Bool,
        adaptiveColor: UInt32
    ) {
        for (i, owner) in owners.enumerated() {
            guard let owner = owner, let partner = owner.partner else { continue }
            guard let startCol = MessengerPlusColorPalette.parseColorToken(owner.argument ?? "", adaptiveColor: adaptiveColor),
                  let endCol = MessengerPlusColorPalette.parseColorToken(partner.argument ?? "", adaptiveColor: adaptiveColor)
            else { continue }

            let count = partner.start - owner.end
            let pos = glyphs[i].sourceStart
            let offset = min(max(0, pos - owner.end), max(0, count - 1))
            let argb = ColorGradientEngine.interpolate(start: startCol.argb, end: endCol.argb, index: offset, count: count)
            let gradValue = MessengerPlusColorValue(argb: argb, wireToken: String(format: "#%06X", argb & 0xFFFFFF))

            if isBackground {
                glyphs[i].style.background = gradValue
            } else {
                glyphs[i].style.foreground = gradValue
            }
        }
    }
}
