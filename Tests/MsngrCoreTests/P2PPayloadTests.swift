import XCTest
@testable import MsngrCore

final class P2PPayloadTests: XCTestCase {

    // MARK: - 1. MsnFileContext 574-Byte Binary Tests
    func testMsnFileContext574ByteRoundTrip() {
        let fileName = "vacation_photo.jpg"
        let fileSize: UInt64 = 1_048_576 // 1 MB

        let context = MsnFileContext(fileName: fileName, fileSize: fileSize)
        let encoded = context.encode()

        XCTAssertEqual(encoded.count, 574)

        // Verify little-endian binary header fields
        XCTAssertEqual(encoded[0], 0x3E)
        XCTAssertEqual(encoded[1], 0x02)
        XCTAssertEqual(encoded[2], 0x00)
        XCTAssertEqual(encoded[3], 0x00) // 574 LE

        XCTAssertEqual(encoded[4], 0x02)
        XCTAssertEqual(encoded[5], 0x00)
        XCTAssertEqual(encoded[6], 0x00)
        XCTAssertEqual(encoded[7], 0x00) // Version 2 LE

        XCTAssertEqual(encoded[8], 0x00)
        XCTAssertEqual(encoded[9], 0x00)
        XCTAssertEqual(encoded[10], 0x10)
        XCTAssertEqual(encoded[11], 0x00)
        XCTAssertEqual(encoded[12], 0x00)
        XCTAssertEqual(encoded[13], 0x00)
        XCTAssertEqual(encoded[14], 0x00)
        XCTAssertEqual(encoded[15], 0x00) // 1,048,576 LE

        XCTAssertEqual(encoded[16], 0x01)
        XCTAssertEqual(encoded[17], 0x00)
        XCTAssertEqual(encoded[18], 0x00)
        XCTAssertEqual(encoded[19], 0x00) // Type 1 LE

        // Unknown2 at 570..573
        XCTAssertEqual(encoded[570], 0xFF)
        XCTAssertEqual(encoded[571], 0xFF)
        XCTAssertEqual(encoded[572], 0xFF)
        XCTAssertEqual(encoded[573], 0xFF)

        // Parse from raw Data
        guard let parsed = MsnFileContext.parse(data: encoded) else {
            XCTFail("Failed to parse 574-byte MsnFileContext")
            return
        }
        XCTAssertEqual(parsed.fileName, fileName)
        XCTAssertEqual(parsed.fileSize, fileSize)

        // Base64 roundtrip
        let b64 = context.encodeBase64()
        guard let parsedB64 = MsnFileContext.parse(base64: b64) else {
            XCTFail("Failed to parse Base64 MsnFileContext")
            return
        }
        XCTAssertEqual(parsedB64.fileName, fileName)
        XCTAssertEqual(parsedB64.fileSize, fileSize)
    }

    func testMsnFileContextWindowsPathSanitization() {
        let winContext = MsnFileContext(fileName: "C:\\Users\\Bob\\Documents\\presentation.pptx", fileSize: 2048)
        XCTAssertEqual(winContext.fileName, "presentation.pptx")

        let unixContext = MsnFileContext(fileName: "/var/tmp/upload/presentation.pptx", fileSize: 2048)
        XCTAssertEqual(unixContext.fileName, "presentation.pptx")

        let whitespaceContext = MsnFileContext(fileName: "   \\sub\\demo.txt  ", fileSize: 10)
        XCTAssertEqual(whitespaceContext.fileName, "demo.txt")

        let fallbackContext = MsnFileContext(fileName: "   ", fileSize: 10)
        XCTAssertEqual(fallbackContext.fileName, "file.bin")
    }

    // MARK: - 2. P2Pv1 48-byte LE Header & 4-byte BE Footer
    func testP2Pv1CodecRoundTrip() {
        let header = P2Pv1Header(
            sessionId: 100,
            id: 1,
            offset: 0,
            totalSize: 1000,
            length: 4,
            flags: P2Pv1Header.flagMsnObjectData,
            ackId: 0,
            ackSubId: 0,
            ackSize: 0
        )
        let body = Data([0x0A, 0x0B, 0x0C, 0x0D])
        let appId: UInt32 = 1 // Display picture app ID

        let packet = P2Pv1Packet(header: header, body: body, appId: appId)
        let encoded = packet.encode()
        XCTAssertEqual(encoded.count, 48 + 4 + 4)

        guard let parsed = P2Pv1Packet.parse(data: encoded) else {
            XCTFail("Failed to parse P2Pv1Packet")
            return
        }

        XCTAssertEqual(parsed.header.sessionId, 100)
        XCTAssertEqual(parsed.header.id, 1)
        XCTAssertEqual(parsed.header.offset, 0)
        XCTAssertEqual(parsed.header.totalSize, 1000)
        XCTAssertEqual(parsed.header.length, 4)
        XCTAssertEqual(parsed.header.flags, P2Pv1Header.flagMsnObjectData)
        XCTAssertEqual(parsed.body, body)
        XCTAssertEqual(parsed.appId, appId)
    }

    // MARK: - 3. P2Pv2 Big-Endian Framing & TLV Codec
    func testP2Pv2BigEndianCodecRoundTrip() {
        let packet = P2Pv2Packet(
            operationCode: 3,
            identifier: 0xF1020304,
            ackIdentifier: 0x11223344,
            sessionId: 0xA1020304,
            tfCombination: 5,
            packageNumber: 0xBEEF,
            dataRemaining: 1234,
            body: Data([1, 2, 3, 4]),
            footer: 1,
            peerInfo: true
        )

        let encoded = packet.encode()
        guard let parsed = P2Pv2Packet.parse(data: encoded) else {
            XCTFail("Failed to parse P2Pv2Packet")
            return
        }

        XCTAssertEqual(parsed.operationCode, 3)
        XCTAssertEqual(parsed.identifier, 0xF1020304)
        XCTAssertEqual(parsed.ackIdentifier, 0x11223344)
        XCTAssertEqual(parsed.sessionId, 0xA1020304)
        XCTAssertEqual(parsed.tfCombination, 5)
        XCTAssertEqual(parsed.packageNumber, 0xBEEF)
        XCTAssertEqual(parsed.dataRemaining, 1234)
        XCTAssertEqual(parsed.body, Data([1, 2, 3, 4]))
        XCTAssertEqual(parsed.footer, 1)
        XCTAssertTrue(parsed.peerInfo)
    }

    // MARK: - 4. MSNSLP Envelope Codec
    func testSlpMessageCodecRoundTrip() {
        let slp = SlpMessage(
            firstLine: "INVITE MSNMSGR:bob@example.com MSNSLP/1.0",
            to: "bob@example.com",
            from: "alice@example.com",
            branch: "1111-2222-3333",
            callId: "call-4444-5555",
            cseq: 1,
            contentType: SlpMessage.sessionRequestContentType,
            body: "EUF-GUID: {A4268EEC-FEC5-49E5-95C3-F126696BDBF6}\r\nAppID: 1\r\n"
        )

        let data = slp.encode()
        guard let parsed = SlpMessage.parse(data: data) else {
            XCTFail("Failed to parse encoded SlpMessage")
            return
        }

        XCTAssertEqual(parsed.firstLine, slp.firstLine)
        XCTAssertEqual(parsed.to, "bob@example.com")
        XCTAssertEqual(parsed.from, "alice@example.com")
        XCTAssertEqual(parsed.branch, "1111-2222-3333")
        XCTAssertEqual(parsed.callId, "call-4444-5555")
        XCTAssertEqual(parsed.cseq, 1)
        XCTAssertEqual(parsed.contentType, SlpMessage.sessionRequestContentType)
    }

    // MARK: - 5. Voice Clip Waveform & RMS
    func testVoiceClipWaveformGeneration() {
        let levels: [Float] = [0.1, 0.2, 0.5, 0.8, 0.3]
        let bars = VoiceClipPayload.generateWaveform(levels: levels, targetCount: 40)
        XCTAssertEqual(bars.count, 40)
        for val in bars {
            XCTAssertGreaterThanOrEqual(val, 0.0)
            XCTAssertLessThanOrEqual(val, 1.0)
        }

        // Empty levels
        let emptyBars = VoiceClipPayload.generateWaveform(levels: [], targetCount: 40)
        XCTAssertEqual(emptyBars.count, 40)
        XCTAssertTrue(emptyBars.allSatisfy { $0 == 0.0 })

        // Zero and negative targetCount guard
        XCTAssertEqual(VoiceClipPayload.generateWaveform(levels: levels, targetCount: 0), [])
        XCTAssertEqual(VoiceClipPayload.generateWaveform(levels: levels, targetCount: -5), [])
        XCTAssertEqual(VoiceClipPayload.resample(levels: levels, targetCount: 0), [])

        // Audio filename detector
        XCTAssertTrue(VoiceClipPayload.isAudioOrVoiceClip(fileName: "voice_clip_2026.m4a"))
        XCTAssertTrue(VoiceClipPayload.isAudioOrVoiceClip(fileName: "test.mp3"))
        XCTAssertFalse(VoiceClipPayload.isAudioOrVoiceClip(fileName: "image.png"))
    }

    // MARK: - 6. Wink Archive Path Sanitization
    func testWinkPayloadSanitizePath() {
        XCTAssertEqual(WinkPayload.sanitizeArchivePath("wink.swf"), "wink.swf")
        XCTAssertEqual(WinkPayload.sanitizeArchivePath("anim/wink.swf"), "anim/wink.swf")
        XCTAssertEqual(WinkPayload.sanitizeArchivePath("  wink.swf  "), "wink.swf")
        XCTAssertNil(WinkPayload.sanitizeArchivePath("   "))
        XCTAssertNil(WinkPayload.sanitizeArchivePath(""))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("../../hack.swf"))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("/root/hack.swf"))
        XCTAssertNil(WinkPayload.sanitizeArchivePath("C:\\system\\hack.swf"))

        XCTAssertTrue(WinkPayload.isSafeArchivePath("wink.swf"))
        XCTAssertTrue(WinkPayload.isSafeArchivePath("anim/wink.swf"))
        XCTAssertFalse(WinkPayload.isSafeArchivePath("   "))
        XCTAssertFalse(WinkPayload.isSafeArchivePath("../../hack.swf"))
    }

    // MARK: - 7. Ink Multi-Byte Encoding (MBE)
    func testInkCodecMbeEncoding() {
        let testValues: [UInt32] = [0, 1, 127, 128, 255, 16384, 0x1FFFFFFF]
        for val in testValues {
            var data = Data()
            InkCodec.writeMbe(val, into: &data)
            var offset = 0
            let decoded = InkCodec.readMbe(from: data, at: &offset)
            XCTAssertEqual(decoded, val)
            XCTAssertEqual(offset, data.count)
        }
    }
}
