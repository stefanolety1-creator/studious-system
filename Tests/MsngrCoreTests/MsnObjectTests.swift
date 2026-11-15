import XCTest
@testable import MsngrCore

final class MsnObjectTests: XCTestCase {

    // MARK: - 1. Verified Hash Test Vector (Reference: MsnDisplayPicture.kt)
    func testMsnObjectVerifiedHashTestVector() {
        let rawBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x4D, 0x53, 0x4E, 0x50, 0x2D, 0x4D, 0x4F, 0x43, 0x4B])
        XCTAssertEqual(rawBytes.count, 17)

        let creator = "test@example.com"
        let sha1d = MsnObject.computeSHA1D(data: rawBytes)
        XCTAssertEqual(sha1d, "LwJsJyenWhe3bXAV2cdpzq/VGQk=")

        let sha1c = MsnObject.computeSHA1C(
            creator: creator,
            size: rawBytes.count,
            type: 3,
            location: "TFR2C2.tmp",
            friendly: "AAA=",
            sha1d: sha1d
        )
        XCTAssertEqual(sha1c, "3wdNGPrZJW0TCkciKGru6hZZamw=")

        let obj = MsnObject.create(creator: creator, data: rawBytes)
        XCTAssertEqual(obj.creator, creator)
        XCTAssertEqual(obj.size, 17)
        XCTAssertEqual(obj.type, 3)
        XCTAssertEqual(obj.location, "TFR2C2.tmp")
        XCTAssertEqual(obj.friendly, "AAA=")
        XCTAssertEqual(obj.sha1d, "LwJsJyenWhe3bXAV2cdpzq/VGQk=")
        XCTAssertEqual(obj.sha1c, "3wdNGPrZJW0TCkciKGru6hZZamw=")

        let xml = obj.toXml()
        XCTAssertEqual(xml, "<msnobj Creator=\"test@example.com\" Size=\"17\" Type=\"3\" Location=\"TFR2C2.tmp\" Friendly=\"AAA=\" SHA1D=\"LwJsJyenWhe3bXAV2cdpzq/VGQk=\" SHA1C=\"3wdNGPrZJW0TCkciKGru6hZZamw=\"/>")

        XCTAssertTrue(obj.matches(data: rawBytes))
        XCTAssertFalse(obj.matches(data: Data([0x01, 0x02])))
    }

    // MARK: - 2. Parsing and Roundtrip
    func testMsnObjectXmlParsing() {
        let xml = "<msnobj Creator=\"user@live.com\" Size=\"1234\" Type=\"3\" Location=\"TFR2C2.tmp\" Friendly=\"AAA=\" SHA1D=\"abc123==\" SHA1C=\"def456==\"/>"
        guard let parsed = MsnObject.parse(xml) else {
            XCTFail("Failed to parse valid MSNObject XML")
            return
        }

        XCTAssertEqual(parsed.creator, "user@live.com")
        XCTAssertEqual(parsed.size, 1234)
        XCTAssertEqual(parsed.type, 3)
        XCTAssertEqual(parsed.location, "TFR2C2.tmp")
        XCTAssertEqual(parsed.friendly, "AAA=")
        XCTAssertEqual(parsed.sha1d, "abc123==")
        XCTAssertEqual(parsed.sha1c, "def456==")
    }

    func testMsnObjectUrlEncodedParsing() {
        let raw = "%3Cmsnobj%20Creator%3D%22alice%40example.com%22%20Size%3D%22500%22%20Type%3D%223%22%20Location%3D%22TFR2C2.tmp%22%20Friendly%3D%22AAA%3D%22%20SHA1D%3D%22testHash%3D%22%2F%3E"
        guard let parsed = MsnObject.parse(raw) else {
            XCTFail("Failed to parse URL-encoded MSNObject")
            return
        }
        XCTAssertEqual(parsed.creator, "alice@example.com")
        XCTAssertEqual(parsed.size, 500)
    }

    // MARK: - 3. Security and Malformed XML Rejection
    func testSecurityRejectsDoctypeInjection() {
        let xxe = "<!DOCTYPE foo [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><msnobj Creator=\"&xxe;\" Size=\"10\" Type=\"3\" Location=\"loc\" Friendly=\"AAA=\" SHA1D=\"hash\"/>"
        XCTAssertNil(MsnObject.parse(xxe))
    }

    func testRejectsEmptyAndZero() {
        XCTAssertNil(MsnObject.parse(nil))
        XCTAssertNil(MsnObject.parse(""))
        XCTAssertNil(MsnObject.parse("   "))
        XCTAssertNil(MsnObject.parse("0"))
    }
}
