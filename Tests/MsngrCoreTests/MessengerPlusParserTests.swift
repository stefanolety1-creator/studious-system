import XCTest
import SwiftUI
@testable import MsngrCore

final class MessengerPlusParserTests: XCTestCase {

    // MARK: - 1. Palette Verification
    func testClassicPaletteMatchesMessengerPlusIndicesExactly() {
        XCTAssertEqual(MessengerPlusColorPalette.palette.count, 68)
        XCTAssertEqual(MessengerPlusColorPalette.palette[0].hexToken(), "#FFFFFF")
        XCTAssertEqual(MessengerPlusColorPalette.palette[1].hexToken(), "#000000")
        XCTAssertEqual(MessengerPlusColorPalette.palette[2].hexToken(), "#00007F")
        XCTAssertEqual(MessengerPlusColorPalette.palette[3].hexToken(), "#009300")
        XCTAssertEqual(MessengerPlusColorPalette.palette[4].hexToken(), "#FF0000")
        XCTAssertEqual(MessengerPlusColorPalette.palette[12].hexToken(), "#0000FC")
        XCTAssertEqual(MessengerPlusColorPalette.palette[67].hexToken(), "#544D05")
    }

    func testNamedColorsVsPaletteDiscrepancies() {
        // Named green is 0x008000, while palette index 3 is 0x009300
        let namedGreen = MessengerPlusColorPalette.parseColorToken("green")!
        let paletteGreen = MessengerPlusColorPalette.paletteColor(index: 3)!
        XCTAssertEqual(namedGreen.argb & 0xFFFFFF, 0x008000)
        XCTAssertEqual(paletteGreen.argb & 0xFFFFFF, 0x009300)
        XCTAssertNotEqual(namedGreen.argb, paletteGreen.argb)

        // Named blue is 0x0000FF, while palette index 12 is 0x0000FC
        let namedBlue = MessengerPlusColorPalette.parseColorToken("blue")!
        let paletteBlue = MessengerPlusColorPalette.paletteColor(index: 12)!
        XCTAssertEqual(namedBlue.argb & 0xFFFFFF, 0x0000FF)
        XCTAssertEqual(paletteBlue.argb & 0xFFFFFF, 0x0000FC)
        XCTAssertNotEqual(namedBlue.argb, paletteBlue.argb)
    }

    func testOutOfRangePaletteIndicesResolveToBlack() {
        let col68 = MessengerPlusColorPalette.parseColorToken("68")!
        XCTAssertEqual(col68.argb, 0xFF000000)
        XCTAssertEqual(col68.wireToken, "68")

        let col99 = MessengerPlusColorPalette.parseColorToken("99")!
        XCTAssertEqual(col99.argb, 0xFF000000)
        XCTAssertEqual(col99.wireToken, "99")

        XCTAssertNil(MessengerPlusColorPalette.parseColorToken("100"))
    }

    // MARK: - 2. Gradient Engine Arithmetic
    func testGradientInterpolationMatchesNativePlusRamp() {
        // Native counts the 3 chars in [b] and 4 in [/b] in the ramp
        let (text, glyphs) = MessengerPlusParser.parse("[c=#000000]AA[b]BB[/b]CC[/c=#FFFFFF]")
        XCTAssertEqual(text, "AABBCC")
        XCTAssertEqual(glyphs.count, 6)

        let blues = glyphs.map { $0.style.foreground!.blue }
        XCTAssertEqual(blues, [0, 21, 106, 127, 233, 255])

        let bolds = glyphs.map { $0.style.bold }
        XCTAssertEqual(bolds, [false, false, true, true, false, false])
    }

    func testOneCharacterGradientAndUnicodeSurrogates() {
        // Single character uses start color
        let (_, single) = MessengerPlusParser.parse("[c=4]X[/c=12]")
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].style.foreground?.hexToken(), "#FF0000")

        // Emoji 😀 uses 2 UTF-16 code units
        let (emojiText, emojiGlyphs) = MessengerPlusParser.parse("[c=#000000]A😀B[/c=#FFFFFF]")
        XCTAssertEqual(emojiText, "A😀B")
        XCTAssertEqual(emojiGlyphs.count, 3)
        let blues = emojiGlyphs.map { $0.style.foreground!.blue }
        XCTAssertEqual(blues, [0, 85, 255])
    }

    // MARK: - 3. BBCode Tag Parsing
    func testBasicBBCodeAndCaseInsensitivity() {
        let (text, glyphs) = MessengerPlusParser.parse("[B][i][u][s][c=4]Plus[/c][/s][/u][/i][/b]")
        XCTAssertEqual(text, "Plus")
        XCTAssertEqual(glyphs.count, 4)
        for g in glyphs {
            XCTAssertTrue(g.style.bold)
            XCTAssertTrue(g.style.italic)
            XCTAssertTrue(g.style.underline)
            XCTAssertTrue(g.style.strikeout)
            XCTAssertEqual(g.style.foreground?.hexToken(), "#FF0000")
        }
    }

    func testLiteralNoParseRightToLeftPairing() {
        let (text, glyphs) = MessengerPlusParser.parse("[n][b]literal[/b][/n]")
        XCTAssertEqual(text, "[b]literal[/b]")
        XCTAssertTrue(glyphs.allSatisfy { !$0.style.bold })

        let stripped = MessengerPlusParser.stripFormatting("A[n][b]B[/b][/n]C")
        XCTAssertEqual(stripped, "A[b]B[/b]C")
    }

    func testUnmatchedTagsRemainLiteral() {
        let source = "[g=1,5]text[/g](!s12) [b]orphan"
        XCTAssertEqual(MessengerPlusParser.stripFormatting(source), source)
    }

    // MARK: - 4. Binary C0 and Readable Controls
    func testBinaryControlTogglesIndependently() {
        let (text, glyphs) = MessengerPlusParser.parse("\u{0002}Bold \u{0005}and italic\u{0005}\u{0002} plain \u{001F}under\u{001F} \u{0006}strike\u{0006}")
        XCTAssertEqual(text, "Bold and italic plain under strike")
        XCTAssertTrue(glyphs[0].style.bold)
        XCTAssertTrue(glyphs[5].style.bold && glyphs[5].style.italic)
        XCTAssertFalse(glyphs[16].style.bold || glyphs[16].style.italic)
        XCTAssertTrue(glyphs[22].style.underline)
        XCTAssertTrue(glyphs[28].style.strikeout)
    }

    func testReadableAliasesMatchBinaryControls() {
        let binaryResult = MessengerPlusParser.stripFormatting("\u{0002}Hello\u{0002}")
        let readableResult = MessengerPlusParser.stripFormatting("·#Hello·#")
        XCTAssertEqual(binaryResult, "Hello")
        XCTAssertEqual(readableResult, "Hello")

        let (_, binaryGlyphs) = MessengerPlusParser.parse("\u{0002}Bold\u{0002}")
        let (_, readableGlyphs) = MessengerPlusParser.parse("·#Bold·#")
        XCTAssertTrue(binaryGlyphs.first!.style.bold)
        XCTAssertTrue(readableGlyphs.first!.style.bold)
    }

    func testBinaryAndBbcodeLayerIndependence() {
        // Binary reset \u000F does not clear enclosing [b] tag
        let (text, glyphs) = MessengerPlusParser.parse("[b]A\u{0002}B\u{0002}C\u{000F}D[/b]E")
        XCTAssertEqual(text, "ABCDE")
        XCTAssertEqual(glyphs.map(\.style.bold), [true, true, true, true, false])
    }

    func testNulByteTermination() {
        let (text, _) = MessengerPlusParser.parse("Hello\0World")
        XCTAssertEqual(text, "Hello")
    }

    func testBinaryColorTrailingCommaPreservesComma() {
        let stripped = MessengerPlusParser.stripFormatting("\u{0003}4,Text\u{0003}X")
        XCTAssertEqual(stripped, ",TextX")

        let (text, glyphs) = MessengerPlusParser.parse("\u{0003}4,Text\u{0003}X")
        XCTAssertEqual(text, ",TextX")
        XCTAssertEqual(glyphs.count, 6)
        XCTAssertEqual(glyphs[0].value, ",")
        XCTAssertEqual(glyphs[0].style.foreground?.hexToken(), "#FF0000")
        XCTAssertNil(glyphs[0].style.background)
        XCTAssertEqual(glyphs[1].value, "T")
        XCTAssertEqual(glyphs[1].style.foreground?.hexToken(), "#FF0000")
    }

    // MARK: - 5. NativeTextStyle (X-MMS-IM-Format)
    func testNativeTextStyleSerializationAndParsing() {
        let style = NativeTextStyle(
            bold: true,
            italic: true,
            strikeout: false,
            underline: false,
            colorRgb: 0xFF0000, // Red
            fontFace: .semibold
        )
        let header = style.toFormatHeader()
        XCTAssertTrue(header.contains("FN=Segoe%20UI%20Semibold"))
        XCTAssertTrue(header.contains("EF=BI"))
        XCTAssertTrue(header.contains("CO=ff")) // BGR for red is 0x0000FF

        let parsed = NativeTextStyle.fromFormatHeader(header)
        XCTAssertEqual(parsed.bold, true)
        XCTAssertEqual(parsed.italic, true)
        XCTAssertEqual(parsed.strikeout, false)
        XCTAssertEqual(parsed.underline, false)
        XCTAssertEqual(parsed.colorRgb, 0xFF0000)
        XCTAssertEqual(parsed.fontFace, .semibold)
    }

    // MARK: - 6. AttributedString Output
    func testParseToAttributedStringGeneratesFormattedRuns() {
        let formatted = MessengerPlusParser.parseToAttributedString("[b]Hello[/b] World")
        XCTAssertFalse(formatted.characters.isEmpty)
        XCTAssertEqual(String(formatted.characters), "Hello World")
    }
}
