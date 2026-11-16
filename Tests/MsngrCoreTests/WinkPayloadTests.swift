import XCTest
@testable import MsngrCore

final class WinkPayloadTests: XCTestCase {

    // MARK: - Make Offer Body Formatting Tests

    func test_winkPayload_makeOfferBodyFormatting() {
        let dummyPayload = Data(repeating: 0x57, count: 512) // 512 bytes
        let metadata = MsnObject.create(
            creator: "user@crosstalk.im",
            data: dummyPayload,
            type: WinkPayload.objectType,
            location: "knock_knock.cab",
            friendly: "Knock Knock Wink"
        )

        let offerBody = WinkPayload.makeOfferBody(metadata: metadata)

        XCTAssertTrue(offerBody.hasPrefix("ID: 2\r\nData: <msnobj "), "Offer body must begin with ID: 2 Datacast header")
        XCTAssertTrue(offerBody.contains("Type=\"8\""), "Wink MSNObject must have Type 8")
        XCTAssertTrue(offerBody.contains("Creator=\"user@crosstalk.im\""), "Creator email must be in XML")
        XCTAssertTrue(offerBody.contains("Location=\"knock_knock.cab\""), "Location CAB name must be in XML")
        XCTAssertTrue(offerBody.hasSuffix("\r\n\r\n"), "Offer body must terminate with double CRLF")
    }

    // MARK: - Parse Offer Validation Tests

    func test_winkPayload_parseOfferValidation() {
        let validPayload = Data(repeating: 0x41, count: 2048)
        let validMetadata = MsnObject.create(
            creator: "sender@escargot.chat",
            data: validPayload,
            type: WinkPayload.objectType,
            location: "water_balloon.cab",
            friendly: "Water Balloon"
        )
        let validOffer = WinkPayload.makeOfferBody(metadata: validMetadata)

        // Valid offer parsing
        let parsed = WinkPayload.parseOffer(body: validOffer)
        XCTAssertNotNil(parsed, "Valid Wink offer body must parse successfully")
        XCTAssertEqual(parsed?.type, 8)
        XCTAssertEqual(parsed?.creator, "sender@escargot.chat")
        XCTAssertEqual(parsed?.location, "water_balloon.cab")
        XCTAssertEqual(parsed?.size, 2048)

        // Missing "Data: " prefix
        let invalidNoData = "ID: 2\r\n<msnobj Type=\"8\"/>\r\n\r\n"
        XCTAssertNil(WinkPayload.parseOffer(body: invalidNoData), "Missing Data: prefix must return nil")

        // Payload with Size < 36 bytes (below min CAB header)
        let tinyPayload = Data(repeating: 0x01, count: 20)
        let tinyMetadata = MsnObject.create(
            creator: "sender@escargot.chat",
            data: tinyPayload,
            type: WinkPayload.objectType
        )
        let tinyOffer = WinkPayload.makeOfferBody(metadata: tinyMetadata)
        XCTAssertNil(WinkPayload.parseOffer(body: tinyOffer), "Wink size < 36 bytes must be rejected")

        // Payload with Size > 2MB (exceeds maxCabBytes)
        let oversizedMetadata = MsnObject(
            creator: "sender@escargot.chat",
            size: 2 * 1024 * 1024 + 100, // 2MB + 100 bytes
            type: 8,
            location: "huge.cab",
            friendly: "Huge",
            sha1d: "AQIDBAUGBwgJCgsMDQ4PEBESExQ="
        )
        let oversizedOffer = WinkPayload.makeOfferBody(metadata: oversizedMetadata)
        XCTAssertNil(WinkPayload.parseOffer(body: oversizedOffer), "Wink size exceeding 2MB must be rejected")

        // Wrong MSNObject Type (e.g. Type 3 UserTile instead of Type 8 Wink)
        let userTileMetadata = MsnObject.create(
            creator: "sender@escargot.chat",
            data: validPayload,
            type: 3
        )
        let userTileOffer = "ID: 2\r\nData: \(userTileMetadata.toXml())\r\n\r\n"
        XCTAssertNil(WinkPayload.parseOffer(body: userTileOffer), "Non-Type 8 object must be rejected")

        // Invalid SHA1D (not 20 bytes when Base64 decoded)
        let invalidShaMetadata = MsnObject(
            creator: "sender@escargot.chat",
            size: 1024,
            type: 8,
            location: "bad_sha.cab",
            friendly: "Bad",
            sha1d: "AQID" // Only 3 bytes
        )
        let invalidShaOffer = WinkPayload.makeOfferBody(metadata: invalidShaMetadata)
        XCTAssertNil(WinkPayload.parseOffer(body: invalidShaOffer), "Invalid SHA1D digest must be rejected")
    }

    // MARK: - Path Traversal Sanitization Tests

    func test_winkPayload_pathTraversalSanitization() {
        // Safe relative paths
        XCTAssertEqual(
            WinkPayload.sanitizeArchivePath("animations/wink.swf"),
            "animations/wink.swf"
        )
        XCTAssertTrue(WinkPayload.isSafeArchivePath("content/sounds/nudge.wav"))

        // Backslash conversion to forward slash
        XCTAssertEqual(
            WinkPayload.sanitizeArchivePath("animations\\sub\\wink.swf"),
            "animations/sub/wink.swf"
        )

        // Traversal with .. must be rejected
        XCTAssertNil(WinkPayload.sanitizeArchivePath("../etc/passwd"))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("animations/../../secret.txt"))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("..\\windows\\system32"))
        XCTAssertFalse(WinkPayload.isSafeArchivePath("../../outside.swf"))

        // Leading slash must be rejected
        XCTAssertNil(WinkPayload.sanitizeArchivePath("/var/log/wink.swf"))

        // Colon or Windows drive letter must be rejected
        XCTAssertNil(WinkPayload.sanitizeArchivePath("C:/Windows/win.ini"))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("http://evil.com/wink.swf"))

        // Empty, whitespace, or empty segments must be rejected
        XCTAssertNil(WinkPayload.sanitizeArchivePath(""))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("   "))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("animations//wink.swf"))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("animations/./wink.swf"))
    }
}
