import XCTest
import Foundation
@testable import MsngrCore
@testable import MsngrProtocol

final class NotificationServerClientTests: XCTestCase {

    // MARK: - Transaction ID Monotonicity Tests

    func test_nsClient_transactionIdMonotonicity() {
        let client = NotificationServerClient(host: "127.0.0.1", port: 1863)

        // Monotonic increase on sequential calls
        let first = client.nextTransactionId()
        let second = client.nextTransactionId()
        let third = client.nextTransactionId()

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(third, 3)

        // Thread-safety under concurrent calls
        let iterations = 1000
        let group = DispatchGroup()
        let lock = NSLock()
        var generatedIds = Set<Int>()

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let id = client.nextTransactionId()
            lock.lock()
            generatedIds.insert(id)
            lock.unlock()
        }

        XCTAssertEqual(generatedIds.count, iterations + 3, "All concurrent transaction IDs must be strictly unique")
    }

    // MARK: - CHG Presence Wire Code Mapping Tests

    func test_nsClient_chgPresenceOutboundWireCodes() {
        // Outbound wire codes for presence states
        XCTAssertEqual(PresenceStatus.online.outboundWireCode, "NLN")
        XCTAssertEqual(PresenceStatus.busy.outboundWireCode, "BSY")
        XCTAssertEqual(PresenceStatus.away.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.idle.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.beRightBack.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.onThePhone.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.outToLunch.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.hidden.outboundWireCode, "HDN")
        XCTAssertEqual(PresenceStatus.offline.outboundWireCode, "HDN")

        // Inbound wire code resolution
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "NLN"), .online)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "BSY"), .busy)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "AWY"), .away)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "HDN"), .hidden)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "FLN"), .offline)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "IDL"), .idle)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "BRB"), .beRightBack)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "PHN"), .onThePhone)
        XCTAssertEqual(PresenceStatus(msnpPresenceCode: "LUN"), .outToLunch)
    }

    // MARK: - UUX Personal Message Formatting Tests

    func test_nsClient_uuxPersonalMessageFormatting() {
        let rawMessage = "Listening to \"Rock & Roll\" <Music> '2009' by Stefano"
        let escaped = SOAPXmlBuilder.escapeXml(rawMessage)

        // XML entities escaping
        XCTAssertFalse(escaped.contains("<Music>"))
        XCTAssertTrue(escaped.contains("&lt;Music&gt;"))
        XCTAssertTrue(escaped.contains("&amp;"))
        XCTAssertTrue(escaped.contains("&quot;"))
        XCTAssertTrue(escaped.contains("&apos;"))

        // Full UUX payload format
        let guid = "{11111111-2222-3333-4444-555555555555}"
        let xmlPayload = "<Data><PSM>\(escaped)</PSM><CurrentMedia></CurrentMedia><MachineGuidName>\(guid)</MachineGuidName></Data>"

        XCTAssertTrue(xmlPayload.hasPrefix("<Data><PSM>"))
        XCTAssertTrue(xmlPayload.contains("<MachineGuidName>\(guid)</MachineGuidName>"))
        XCTAssertTrue(xmlPayload.hasSuffix("</Data>"))

        // Roundtrip parsing via extractTag and unescapeXml
        let extractedPsm = SOAPXmlBuilder.extractTag(xmlPayload, tag: "PSM")
        XCTAssertNotNil(extractedPsm)
        let restored = SOAPXmlBuilder.unescapeXml(extractedPsm ?? "")
        XCTAssertEqual(restored, rawMessage, "Extracted and unescaped PSM must exactly match original message")
    }
}
