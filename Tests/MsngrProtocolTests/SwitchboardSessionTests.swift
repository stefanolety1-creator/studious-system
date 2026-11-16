import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class SwitchboardSessionTests: XCTestCase {

    // MARK: - MIME Text Serialization Tests

    func test_sbSession_mimeMessageSerialization() {
        let text = "Hello from Windows Live Messenger 2009! 🚀"
        let fontName = "Segoe UI"
        let colorHex = "0078D7"
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nX-MMS-IM-Format: FN=\(fontName); EF=; CO=\(colorHex); CS=0; PF=00\r\n\r\n\(text)"

        XCTAssertTrue(mime.contains("Content-Type: text/plain; charset=UTF-8"))
        XCTAssertTrue(mime.contains("FN=Segoe UI"))
        XCTAssertTrue(mime.contains("CO=0078D7"))
        XCTAssertTrue(mime.hasSuffix("\r\n\r\n\(text)"))

        // Verify byte count length matching wire framing
        let length = mime.utf8.count
        XCTAssertGreaterThan(length, text.utf8.count)

        // Parse with SwitchboardMimeParser
        let parsed = SwitchboardMimeParser.parse(mimeText: mime)
        if case .text(let body, let formatHeader) = parsed {
            XCTAssertEqual(body, text)
            XCTAssertNotNil(formatHeader)
            XCTAssertTrue(formatHeader?.contains("FN=Segoe UI") ?? false)
            XCTAssertTrue(formatHeader?.contains("CO=0078D7") ?? false)
        } else {
            XCTFail("Parsed MIME should be .text")
        }
    }

    // MARK: - Typing Indicator MIME Encoding Tests

    func test_sbSession_typingIndicatorMimeEncoding() async {
        let userEmail = "alice@crosstalk.im"
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msmsgscontrol\r\nTypingUser: \(userEmail)\r\n\r\n\r\n"

        XCTAssertTrue(mime.contains("Content-Type: text/x-msmsgscontrol"))
        XCTAssertTrue(mime.contains("TypingUser: alice@crosstalk.im"))
        XCTAssertTrue(mime.hasSuffix("\r\n\r\n\r\n"))

        // Parse typing notification
        let parsed = SwitchboardMimeParser.parse(mimeText: mime)
        XCTAssertEqual(parsed, .typing(user: "alice@crosstalk.im"))

        // Test TypingStateTracker actor
        let tracker = TypingStateTracker(timeout: 0.1)
        await tracker.setTyping()
        let isTypingImmediately = await tracker.getIsTyping()
        XCTAssertTrue(isTypingImmediately, "Typing tracker must report true immediately after setTyping()")

        // Await expiry
        try? await Task.sleep(nanoseconds: 150_000_000)
        let isTypingExpired = await tracker.getIsTyping()
        XCTAssertFalse(isTypingExpired, "Typing tracker must expire back to false after timeout")
    }

    // MARK: - Nudge Datacast Encoding Tests

    func test_sbSession_nudgeDatacastEncoding() {
        let senderEmail = "bob@escargot.chat"
        let mime = "MIME-Version: 1.0\r\nContent-Type: text/x-msnmsgr-datacast\r\n\r\nID: 1\r\n"

        XCTAssertTrue(mime.contains("Content-Type: text/x-msnmsgr-datacast"))
        XCTAssertTrue(mime.contains("ID: 1"))

        // Parse with SwitchboardMimeParser
        let parsed = SwitchboardMimeParser.parse(mimeText: mime, sender: senderEmail)
        XCTAssertEqual(parsed, .nudge(sender: senderEmail))

        // Wire command format verification
        let trId = 42
        let wireCommand = "MSG \(trId) \(SwitchboardAckMode.negativeAck.rawValue) \(mime.utf8.count)\r\n\(mime)"
        XCTAssertTrue(wireCommand.hasPrefix("MSG 42 N "))
        XCTAssertTrue(wireCommand.contains("ID: 1"))
    }
}
