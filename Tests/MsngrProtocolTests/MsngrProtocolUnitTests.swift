import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class MsngrProtocolUnitTests: XCTestCase {
    // MARK: - RPS Proof Generator Unit Tests

    func test_rpsProofGenerator_producesValid28ByteLittleEndianHeader() throws {
        let generator = RPSProofGenerator()
        let secretBase64 = Data((1...24).map { UInt8($0) }).base64EncodedString()
        let fixedIv = Data([1, 2, 3, 4, 5, 6, 7, 8])

        let proofBase64 = try generator.generateProof(
            binarySecretBase64: secretBase64,
            nonce: "MSNP18-TEST-NONCE",
            iv: fixedIv
        )

        guard let proofData = Data(base64Encoded: proofBase64) else {
            XCTFail("Proof must be valid Base64")
            return
        }

        // 28 header + 8 IV + 20 HMAC + 24 ciphertext = 80 bytes
        XCTAssertEqual(proofData.count, 80)

        let headerSize = proofData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let structVer = proofData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let cipherAlg = proofData.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let hashAlg = proofData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let ivLen = proofData.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let hashLen = proofData.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        XCTAssertEqual(headerSize, 28)
        XCTAssertEqual(structVer, 1)
        XCTAssertEqual(cipherAlg, 0x6603)
        XCTAssertEqual(hashAlg, 0x8004)
        XCTAssertEqual(ivLen, 8)
        XCTAssertEqual(hashLen, 20)
    }

    func test_rpsProofGenerator_deterministicWithFixedIv() throws {
        let generator = RPSProofGenerator()
        let secretBase64 = Data(repeating: 0xAB, count: 24).base64EncodedString()
        let iv = Data([10, 20, 30, 40, 50, 60, 70, 80])

        let p1 = try generator.generateProof(binarySecretBase64: secretBase64, nonce: "NONCE123", iv: iv)
        let p2 = try generator.generateProof(binarySecretBase64: secretBase64, nonce: "NONCE123", iv: iv)
        XCTAssertEqual(p1, p2)
    }

    // MARK: - SOAP XML Builder Unit Tests

    func test_soapXmlBuilder_escapesAndUnescapesEntities() {
        let raw = "User <Admin> & \"Friends\" '2009'"
        let escaped = SOAPXmlBuilder.escapeXml(raw)
        XCTAssertFalse(escaped.contains("<Admin>"))
        XCTAssertTrue(escaped.contains("&lt;Admin&gt;"))
        XCTAssertEqual(SOAPXmlBuilder.unescapeXml(escaped), raw)
        XCTAssertEqual(SOAPXmlBuilder.unescapeXml("A &#x3D; B"), "A = B")
    }

    func test_soapXmlBuilder_rst2EnvelopeTruncatesLongPasswordTo16Chars() {
        let envelope = SOAPXmlBuilder.buildRST2Envelope(
            email: "user@escargot.chat",
            password: "1234567890123456EXTRA_IGNORED",
            policy: "MBI_KEY_OLD"
        )
        XCTAssertTrue(envelope.contains("1234567890123456"))
        XCTAssertFalse(envelope.contains("EXTRA_IGNORED"))
    }

    // MARK: - MSNP Frame Decoder Unit Tests

    func test_frameDecoder_parsesCommandAndPayloadAcrossChunks() {
        let decoder = MsnpFrameDecoder()
        let chunk1 = Data("MSG 42 A 15\r\nHello ".utf8)
        let chunk2 = Data("MSNP18!!!\r\nPNG\r\n".utf8)

        let frames1 = decoder.feed(chunk1)
        XCTAssertTrue(frames1.isEmpty)

        let frames2 = decoder.feed(chunk2)
        XCTAssertEqual(frames2.count, 2)
        XCTAssertEqual(frames2[0].verb, "MSG")
        XCTAssertEqual(frames2[0].transactionId, 42)
        XCTAssertEqual(String(data: frames2[0].payload ?? Data(), encoding: .utf8), "Hello MSNP18!!!")
        XCTAssertEqual(frames2[1].verb, "PNG")
        XCTAssertNil(frames2[1].transactionId)
    }

    // MARK: - Switchboard MIME Parser Unit Tests

    func test_switchboardMimeParser_parsesTextTypingAndNudge() {
        let textMime = "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nX-MMS-IM-Format: FN=Segoe UI; CO=FF0000\r\n\r\nHello World"
        if case .text(let body, let fmt) = SwitchboardMimeParser.parse(mimeText: textMime) {
            XCTAssertEqual(body, "Hello World")
            XCTAssertTrue(fmt?.contains("Segoe UI") ?? false)
        } else {
            XCTFail("Expected .text MIME result")
        }

        let typingMime = "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\nTypingUser: selin@escargot.chat\r\n\r\n\r\n"
        XCTAssertEqual(
            SwitchboardMimeParser.parse(mimeText: typingMime),
            .typing(user: "selin@escargot.chat")
        )

        let nudgeMime = "MIME-Version: 1.0\r\nContent-Type: text/x-msnmsgr-datacast\r\n\r\nID: 1\r\n"
        XCTAssertEqual(
            SwitchboardMimeParser.parse(mimeText: nudgeMime, sender: "selin@escargot.chat"),
            .nudge(sender: "selin@escargot.chat")
        )
    }
}
