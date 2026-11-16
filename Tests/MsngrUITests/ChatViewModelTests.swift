import XCTest
@testable import MsngrCore
@testable import MsngrUI

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: - Messenger Plus! BBCode Tag Insertion Tests

    func test_chatViewModel_bbcodeInsertionWrapsTokens() {
        let contact = Contact(
            id: "alice@crosstalk.im",
            nickname: "Alice",
            email: "alice@crosstalk.im"
        )
        let vm = ChatViewModel(contact: contact)

        // Insert bold tag
        vm.draftText = ""
        vm.insertBBCodeTag("b")
        XCTAssertEqual(vm.draftText, "[b][/b]")

        // Insert italics tag
        vm.draftText = "Hello "
        vm.insertBBCodeTag("i")
        XCTAssertEqual(vm.draftText, "Hello [i][/i]")

        // Insert color tag with parameter
        vm.draftText = "Live: "
        vm.insertBBCodeTag("c", parameter: "12")
        XCTAssertEqual(vm.draftText, "Live: [c=12][/c]")

        // Parse formatted text through MessengerPlusParser
        let attributed = MessengerPlusParser.parseToAttributedString("[b]Bold[/b] and [c=4]Red[/c]")
        XCTAssertFalse(attributed.characters.isEmpty)
    }

    // MARK: - Nudge Rate Limiting (2.0s Cooldown) Tests

    func test_chatViewModel_nudgeRateLimitingEnforces2Seconds() {
        let contact = Contact(
            id: "bob@escargot.chat",
            nickname: "Bob",
            email: "bob@escargot.chat"
        )
        let vm = ChatViewModel(contact: contact)

        XCTAssertEqual(vm.messages.count, 0)
        XCTAssertNil(vm.cooldownErrorMessage)

        // First nudge should succeed immediately
        vm.sendNudge()
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertTrue(vm.messages.first?.isNudge ?? false)
        XCTAssertEqual(vm.messages.first?.author, .me)
        XCTAssertNil(vm.cooldownErrorMessage, "First nudge must not have cooldown error")

        // Immediate second nudge within 2.0s cooldown window must be rejected
        vm.sendNudge()
        XCTAssertEqual(vm.messages.count, 1, "Second nudge within cooldown window must not be appended")
        XCTAssertNotNil(vm.cooldownErrorMessage, "Cooldown error message must be set")
        XCTAssertTrue(vm.cooldownErrorMessage?.contains("wait a moment") ?? false)

        // Incoming nudge from contact should not be blocked by outgoing cooldown
        vm.receiveNudge()
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages.last?.author, .contact)
    }

    // MARK: - Voice Clip Waveform Generation Tests

    func test_chatViewModel_voiceClipWaveformGeneration() {
        let contact = Contact(
            id: "charlie@crosstalk.im",
            nickname: "Charlie",
            email: "charlie@crosstalk.im"
        )
        let vm = ChatViewModel(contact: contact)

        let rawLevels: [Float] = [0.1, 0.4, 0.8, 0.9, 0.6, 0.3, 0.1, 0.05]
        let resampledWaveform = VoiceClipPayload.generateWaveform(levels: rawLevels, targetCount: 40)

        // Waveform must be resampled to exactly 40 bars
        XCTAssertEqual(resampledWaveform.count, 40, "Waveform must have exactly 40 bars")

        // All samples must be clamped between 0.0 and 1.0
        for level in resampledWaveform {
            XCTAssertGreaterThanOrEqual(level, 0.0)
            XCTAssertLessThanOrEqual(level, 1.0)
        }

        // Send voice clip through ChatViewModel
        vm.sendVoiceClip(durationSeconds: 3.8, waveformSamples: resampledWaveform)
        XCTAssertEqual(vm.messages.count, 1)

        let msg = vm.messages.first
        XCTAssertEqual(msg?.kind, .voiceClip)
        XCTAssertEqual(msg?.author, .me)
        XCTAssertEqual(msg?.voiceClip?.durationSeconds, 3.8)
        XCTAssertEqual(msg?.voiceClip?.waveformSamples.count, 40)
    }
}
