import XCTest
@testable import MsngrCore
@testable import MsngrUI

@MainActor
final class MsngrUIUnitTests: XCTestCase {
    // MARK: - Nudge Shake Engine Unit Tests

    func test_nudgeShakeEngine_deltaTableSumsToZeroOrigin() {
        let deltas = NudgeShakeEngine.wlmNudgeDeltas
        XCTAssertEqual(deltas.count, 13, "WLM 2009 nudge table must have exactly 13 steps per cycle")

        let sumX = deltas.reduce(CGFloat(0)) { $0 + $1.x }
        let sumY = deltas.reduce(CGFloat(0)) { $0 + $1.y }
        XCTAssertEqual(sumX, 0, "Cumulative X offset per cycle must return to 0")
        XCTAssertEqual(sumY, 0, "Cumulative Y offset per cycle must return to 0")
    }

    func test_nudgeShakeEngine_triggerReturnsToZeroAfterFourCycles() async {
        let engine = NudgeShakeEngine()
        await engine.trigger(stepNanoseconds: 0)
        XCTAssertFalse(engine.isShaking)
        XCTAssertEqual(engine.offsetX, 0)
        XCTAssertEqual(engine.offsetY, 0)
    }

    // MARK: - Tic-Tac-Toe Mini-Game State Machine Tests

    func test_ticTacToe_winAndDrawDetection() {
        var game = TicTacToeGameState()
        XCTAssertTrue(game.applyMove(at: 0)) // X
        XCTAssertTrue(game.applyMove(at: 3)) // O
        XCTAssertTrue(game.applyMove(at: 1)) // X
        XCTAssertTrue(game.applyMove(at: 4)) // O
        XCTAssertTrue(game.applyMove(at: 2)) // X wins top row (0, 1, 2)

        XCTAssertEqual(game.winner, .x)
        XCTAssertFalse(game.applyMove(at: 5), "Moves after win must be rejected")
    }

    func test_ticTacToe_protocolTokenParsing() {
        let moveToken = TicTacToeGameState.parseToken("[GAME:TTT:MOVE:4]")
        XCTAssertNotNil(moveToken)
        XCTAssertEqual(moveToken?.isNewGame, false)
        XCTAssertEqual(moveToken?.moveSlot, 4)

        let newToken = TicTacToeGameState.parseToken("[GAME:TTT:NEW]")
        XCTAssertNotNil(newToken)
        XCTAssertEqual(newToken?.isNewGame, true)
        XCTAssertNil(newToken?.moveSlot)

        XCTAssertNil(TicTacToeGameState.parseToken("Hello regular chat"))
    }

    // MARK: - SessionViewModel & ChatViewModel Tests

    func test_sessionViewModel_demoSignInPopulatesRosterAndSelectsContact() {
        let session = SessionViewModel()
        session.signInDemoMode(email: "stefano@escargot.chat")

        XCTAssertEqual(session.networkState, .connected)
        XCTAssertEqual(session.onlineContacts.count, 3)
        XCTAssertEqual(session.offlineContacts.count, 1)
        XCTAssertNotNil(session.selectedContactId)
    }

    func test_chatViewModel_sendMessageAndVoiceClipAndBBCode() {
        let contact = Contact(id: "selin@escargot.chat", email: "selin@escargot.chat", displayName: "Selin")
        let vm = ChatViewModel(contact: contact)

        vm.draftText = "Hello"
        vm.insertBBCodeTag("b")
        XCTAssertEqual(vm.draftText, "Hello[b][/b]")

        vm.sendMessage()
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages.first?.author, .me)

        vm.sendVoiceClip(durationSeconds: 4.5, waveformSamples: [0.3, 0.7, 0.5])
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages.last?.kind, .voiceClip)
    }
}
