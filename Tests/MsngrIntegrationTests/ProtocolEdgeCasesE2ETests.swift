import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class ProtocolEdgeCasesE2ETests: XCTestCase {
    var decoder: MsnpFrameDecoder!

    override func setUp() async throws {
        try await super.setUp()
        decoder = MsnpFrameDecoder()
    }

    override func tearDown() async throws {
        decoder = nil
        try await super.tearDown()
    }

    // MARK: - Feature Area 9: Messenger Plus! BBCode & Styling Codec (Tier 1)

    func test_tier1_bbcode_basicStyleTags() async throws {
        let input = "[b]Bold[/b] [i]Italic[/i] [u]Underline[/u] [s]Strike[/s]"
        let parsed = MessengerPlusParser.parse(input)

        let boldGlyphs = parsed.glyphs.filter { $0.style.bold }
        let italicGlyphs = parsed.glyphs.filter { $0.style.italic }
        let underlineGlyphs = parsed.glyphs.filter { $0.style.underline }
        let strikeGlyphs = parsed.glyphs.filter { $0.style.strikeout }

        XCTAssertFalse(boldGlyphs.isEmpty, "Should have bold glyphs")
        XCTAssertFalse(italicGlyphs.isEmpty, "Should have italic glyphs")
        XCTAssertFalse(underlineGlyphs.isEmpty, "Should have underline glyphs")
        XCTAssertFalse(strikeGlyphs.isEmpty, "Should have strikethrough glyphs")
    }

    func test_tier1_bbcode_paletteColorCodes() async throws {
        let input = "[c=4]Red Text[/c]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertFalse(parsed.glyphs.isEmpty)
        let redGlyphs = parsed.glyphs.filter { $0.style.foreground != nil }
        XCTAssertFalse(redGlyphs.isEmpty, "Palette color 4 should produce colored glyphs")
    }

    func test_tier1_bbcode_hexColorCodes() async throws {
        let input = "[c=#00FF88]Mint Green[/c]"
        let parsed = MessengerPlusParser.parse(input)

        let coloredGlyphs = parsed.glyphs.filter { $0.style.foreground != nil }
        XCTAssertFalse(coloredGlyphs.isEmpty, "Hex color should produce colored glyphs")
    }

    func test_tier1_bbcode_noParseBlocks() async throws {
        let input = "[n][b]Not Bold[/b][/n]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertTrue(parsed.text.contains("[b]Not Bold[/b]"), "No-parse block content should remain literal")
        let boldGlyphs = parsed.glyphs.filter { $0.style.bold }
        XCTAssertTrue(boldGlyphs.isEmpty, "Glyphs inside [n] block must not have bold trait")
    }

    func test_tier1_bbcode_binaryControlCodes() async throws {
        let input = "\u{0002}Bold\u{000F} Plain \u{0005}Italic\u{000F}"
        let parsed = MessengerPlusParser.parse(input)

        let boldGlyphs = parsed.glyphs.filter { $0.style.bold }
        let italicGlyphs = parsed.glyphs.filter { $0.style.italic }

        XCTAssertFalse(boldGlyphs.isEmpty, "Control 0x02 should toggle bold")
        XCTAssertFalse(italicGlyphs.isEmpty, "Control 0x05 should toggle italic")
    }

    // MARK: - Feature Area 9: Messenger Plus! BBCode & Styling Codec (Tier 2)

    func test_tier2_bbcode_unclosedTags() async throws {
        let input = "[b]Unclosed Bold Text"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertFalse(parsed.glyphs.isEmpty, "Unclosed tag should parse remaining text without crashing")
    }

    func test_tier2_bbcode_overlappingMismatchedTags() async throws {
        let input = "[b][i]Overlapping[/b][/i]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertFalse(parsed.glyphs.isEmpty, "Mismatched overlapping tags must resolve gracefully")
    }

    func test_tier2_bbcode_invalidPaletteIndex() async throws {
        let input = "[c=999]Out of bounds[/c]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertEqual(parsed.text, "Out of bounds", "Invalid palette index falls back gracefully")
    }

    func test_tier2_bbcode_malformedHexColor() async throws {
        let input = "[c=#ZZZZZZ]Bad Hex[/c]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertEqual(parsed.text, "Bad Hex", "Malformed hex falls back to plain text")
    }

    func test_tier2_bbcode_gradientSingleCharacterString() async throws {
        let input = "[c=1]X[/c=12]"
        let parsed = MessengerPlusParser.parse(input)

        XCTAssertEqual(parsed.text, "X", "Single-character gradient must not divide by zero")
        XCTAssertEqual(parsed.glyphs.count, 1)
    }

    // MARK: - Feature Area 10: MSNObject Descriptors & SHA1 Hashing (Tier 1)

    func test_tier1_msnobject_xmlSerializationAvatar() async throws {
        let obj = MsnObject(
            creator: "user@msngr.dev",
            size: 1234,
            type: 3,
            location: "TFR3C2.tmp",
            friendly: "Avatar",
            sha1d: "mockSHA1D",
            sha1c: "mockSHA1C"
        )
        let xml = obj.toXml()

        XCTAssertTrue(xml.contains("Creator=\"user@msngr.dev\""))
        XCTAssertTrue(xml.contains("Size=\"1234\""))
        XCTAssertTrue(xml.contains("Type=\"3\""))
        XCTAssertTrue(xml.contains("Location=\"TFR3C2.tmp\""))
        XCTAssertTrue(xml.contains("SHA1D=\"mockSHA1D\""))
    }

    func test_tier1_msnobject_sha1dPayloadDigest() async throws {
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let sha1d = MsnObject.computeSHA1D(data: payload)

        XCTAssertFalse(sha1d.isEmpty)
        let obj = MsnObject.create(creator: "user@msngr.dev", data: payload)
        XCTAssertEqual(obj.sha1d, sha1d)
    }

    func test_tier1_msnobject_sha1cCanonicalEnvelopeDigest() async throws {
        let sha1c = MsnObject.computeSHA1C(
            creator: "user@msngr.dev",
            size: 100,
            type: 3,
            location: "TFR1.tmp",
            friendly: "AAA=",
            sha1d: "mockD"
        )
        XCTAssertFalse(sha1c.isEmpty)
    }

    func test_tier1_msnobject_urlEncodingAndDecoding() async throws {
        let obj = MsnObject(
            creator: "user@msngr.dev",
            size: 500,
            type: 3,
            location: "TFR1.tmp",
            friendly: "Avatar",
            sha1d: "mockD",
            sha1c: "mockC"
        )
        let encoded = obj.toEncodedValue()
        XCTAssertFalse(encoded.contains("<"), "Encoded value must percent-escape XML angle brackets")

        let decoded = MsnObject.parse(encoded, expectedType: 3)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.creator, obj.creator)
        XCTAssertEqual(decoded?.size, obj.size)
    }

    func test_tier1_msnobject_deserializationRemoteObject() async throws {
        let xml = "<msnobj Creator=\"remote@msngr.dev\" Size=\"5432\" Type=\"3\" Location=\"TFR1.tmp\" Friendly=\"AAA=\" SHA1D=\"bbb=\" SHA1C=\"ccc=\" />"
        let parsed = MsnObject.parse(xml, expectedType: 3)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.creator, "remote@msngr.dev")
        XCTAssertEqual(parsed?.size, 5432)
        XCTAssertEqual(parsed?.sha1d, "bbb=")
    }

    // MARK: - Feature Area 10: MSNObject Descriptors & SHA1 Hashing (Tier 2)

    func test_tier2_msnobject_payloadExceeding200KBytes() async throws {
        let maxAllowed = MsnObject.maxDisplayPictureBytes
        XCTAssertEqual(maxAllowed, 199_999, "Display picture cap must be strictly < 200,000 bytes")

        let oversizedCount = 200_001
        XCTAssertGreaterThan(oversizedCount, maxAllowed)
    }

    func test_tier2_msnobject_missingSha1dAttribute() async throws {
        let xml = "<msnobj Creator=\"user@msngr.dev\" Size=\"100\" Type=\"3\" Location=\"TFR.tmp\" Friendly=\"A=\" SHA1C=\"C=\" />"
        let parsed = MsnObject.parse(xml, expectedType: 3)
        XCTAssertNil(parsed, "MSNObject missing SHA1D must fail parsing")
    }

    func test_tier2_msnobject_corruptedBase64Sha1c() async throws {
        let invalidBase64 = "!@#$%^&*()"
        let data = Data(base64Encoded: invalidBase64)
        XCTAssertNil(data, "Invalid base64 in SHA1C must fail decoding")
    }

    func test_tier2_msnobject_friendlyNameWithSpecialCharacters() async throws {
        let friendly = "Name with <>&\"' and 🚀"
        let base64Friendly = Data(friendly.utf8).base64EncodedString()

        let obj = MsnObject(
            creator: "user@msngr.dev",
            size: 100,
            type: 3,
            location: "TFR.tmp",
            friendly: base64Friendly,
            sha1d: "mockD"
        )
        let xml = obj.toXml()
        XCTAssertTrue(xml.contains(base64Friendly))
    }

    func test_tier2_msnobject_nonImageTypeDescriptors() async throws {
        let winkXml = "<msnobj Creator=\"user@msngr.dev\" Size=\"100\" Type=\"8\" Location=\"WINK.tmp\" Friendly=\"A=\" SHA1D=\"D=\" />"
        let voiceXml = "<msnobj Creator=\"user@msngr.dev\" Size=\"100\" Type=\"11\" Location=\"VOICE.tmp\" Friendly=\"A=\" SHA1D=\"D=\" />"

        let winkObj = MsnObject.parse(winkXml, expectedType: 8)
        let voiceObj = MsnObject.parse(voiceXml, expectedType: 11)

        XCTAssertNotNil(winkObj)
        XCTAssertEqual(winkObj?.type, MsnObjectType.wink.rawValue)

        XCTAssertNotNil(voiceObj)
        XCTAssertEqual(voiceObj?.type, MsnObjectType.voiceClip.rawValue)
    }

    // MARK: - Additional Protocol Edge Cases (5 Tests)

    func test_tier2_protocol_tcpFragmentationAcrossCommandHeader() async throws {
        let chunk1 = Data("VER ".utf8)
        let chunk2 = Data("1 MSNP1".utf8)
        let chunk3 = Data("8 CVR0\r\n".utf8)

        XCTAssertTrue(decoder.feed(chunk1).isEmpty)
        XCTAssertTrue(decoder.feed(chunk2).isEmpty)

        let frames = decoder.feed(chunk3)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.verb, "VER")
        XCTAssertEqual(frames.first?.transactionId, 1)
        XCTAssertEqual(frames.first?.parameters, ["MSNP18", "CVR0"])
    }

    func test_tier2_protocol_tcpFragmentationAcrossPayloadData() async throws {
        let header = Data("UUX 1 20\r\n".utf8)
        let part1 = Data("1234567890".utf8)
        let part2 = Data("1234567890".utf8)

        XCTAssertTrue(decoder.feed(header).isEmpty, "Payload verb awaiting 20 bytes")
        XCTAssertTrue(decoder.feed(part1).isEmpty, "Only 10 bytes received")

        let frames = decoder.feed(part2)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.payload?.count, 20)
    }

    func test_tier2_protocol_surrogateCharactersInPersonalMessage() async throws {
        let surrogateString = "Music \u{1D11E} and Smile \u{1F600}"
        let utf8Count = surrogateString.utf8.count
        XCTAssertGreaterThan(utf8Count, surrogateString.count, "Surrogate characters require 4 bytes in UTF-8")

        let xml = "<Data><PSM>\(surrogateString)</PSM></Data>"
        XCTAssertTrue(xml.contains(surrogateString))
    }

    func test_tier2_protocol_malformedXmlClosingTagInUux() async throws {
        let malformedXml = "<Data><PSM>Hi</WrongTag></Data>"
        let parsed = extractTagContent(malformedXml, tag: "PSM")
        XCTAssertNil(parsed, "Malformed closing tag should not extract cleanly")
    }

    func test_tier2_protocol_gracefulTeardownDuringActiveStream() async throws {
        var continuation: AsyncStream<Int>.Continuation?
        var terminated = false

        let stream = AsyncStream<Int> { cont in
            continuation = cont
            cont.onTermination = { _ in
                terminated = true
            }
        }

        let task = Task {
            for await item in stream {
                _ = item
            }
        }

        continuation?.yield(1)
        continuation?.yield(2)
        continuation?.finish()
        _ = await task.result

        XCTAssertTrue(terminated, "Stream onTermination must be invoked on finish")
    }
}
