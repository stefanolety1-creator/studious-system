import SwiftUI
import MsngrCore
import MsngrProtocol

/// Represents a 3x3 Tic-Tac-Toe (Tris) in-chat game synced over MSNP text tokens (`[GAME:TTT:MOVE:0..8]`, `[GAME:TTT:NEW]`).
public struct TicTacToeGameState: Sendable, Equatable {
    public enum Mark: String, Sendable, Equatable {
        case x = "X"
        case o = "O"
    }

    public var board: [Mark?] = Array(repeating: nil, count: 9)
    public var currentTurn: Mark = .x
    public var localPlayerMark: Mark = .x
    public var winner: Mark? = nil
    public var isDraw: Bool = false

    public init(localPlayerMark: Mark = .x) {
        self.localPlayerMark = localPlayerMark
    }

    public mutating func reset() {
        board = Array(repeating: nil, count: 9)
        currentTurn = .x
        winner = nil
        isDraw = false
    }

    @discardableResult
    public mutating func applyMove(at index: Int, mark: Mark? = nil) -> Bool {
        guard (0..<9).contains(index), board[index] == nil, winner == nil, !isDraw else {
            return false
        }
        let activeMark = mark ?? currentTurn
        board[index] = activeMark
        evaluateBoard()
        if winner == nil && !isDraw {
            currentTurn = (activeMark == .x) ? .o : .x
        }
        return true
    }

    private mutating func evaluateBoard() {
        let winPatterns: [[Int]] = [
            [0, 1, 2], [3, 4, 5], [6, 7, 8],
            [0, 3, 6], [1, 4, 7], [2, 5, 8],
            [0, 4, 8], [2, 4, 6]
        ]
        for pattern in winPatterns {
            if let m = board[pattern[0]], m == board[pattern[1]], m == board[pattern[2]] {
                winner = m
                return
            }
        }
        if board.allSatisfy({ $0 != nil }) {
            isDraw = true
        }
    }

    /// Parses special MSNP18 game tokens `[GAME:TTT:MOVE:N]` and `[GAME:TTT:NEW]`.
    public static func parseToken(_ text: String) -> (isNewGame: Bool, moveSlot: Int?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[GAME:TTT:NEW]" {
            return (true, nil)
        }
        if trimmed.hasPrefix("[GAME:TTT:MOVE:"), trimmed.hasSuffix("]") {
            let numStr = trimmed
                .replacingOccurrences(of: "[GAME:TTT:MOVE:", with: "")
                .replacingOccurrences(of: "]", with: "")
            if let slot = Int(numStr), (0..<9).contains(slot) {
                return (false, slot)
            }
        }
        return nil
    }
}

/// `@MainActor` ViewModel managing an active 1:1 or group conversation window, BBCode input, nudges, voice clips, and Tic-Tac-Toe.
@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public var contact: Contact
    @Published public var messages: [ChatMessage]
    @Published public var draftText: String = ""
    @Published public var isPeerTyping: Bool = false
    @Published public var ticTacToe: TicTacToeGameState = TicTacToeGameState()
    @Published public var isTicTacToePresented: Bool = false
    @Published public var isVoiceRecorderPresented: Bool = false
    @Published public var cooldownErrorMessage: String?

    public let shakeEngine = NudgeShakeEngine()
    private var switchboardSession: SwitchboardSession?
    private var lastNudgeSentAt: Date?

    public init(contact: Contact, initialMessages: [ChatMessage] = [], switchboardSession: SwitchboardSession? = nil) {
        self.contact = contact
        self.messages = initialMessages
        self.switchboardSession = switchboardSession
    }

    /// Sends a formatted text message and appends it to the conversation history.
    public func sendMessage() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftText = ""
        cooldownErrorMessage = nil

        if let token = TicTacToeGameState.parseToken(trimmed) {
            if token.isNewGame {
                ticTacToe.reset()
            } else if let slot = token.moveSlot {
                ticTacToe.applyMove(at: slot)
            }
        }

        let outgoing = ChatMessage(
            contactId: contact.id,
            author: .me,
            text: trimmed,
            kind: .text,
            deliveryStatus: .sent
        )
        messages.append(outgoing)
        MsnSoundPlayer.shared.play(.type)

        Task {
            try? await switchboardSession?.sendMessage(trimmed)
        }
    }

    /// Inserts a Messenger Plus! BBCode tag wrapper around the current draft or at the end.
    public func insertBBCodeTag(_ tag: String, parameter: String? = nil) {
        if let param = parameter {
            draftText += "[\(tag)=\(param)][/\(tag)]"
        } else {
            draftText += "[\(tag)][/\(tag)]"
        }
    }

    /// Sends a WLM 2009 Nudge with cooldown check and triggers the 13-step window shake.
    public func sendNudge() {
        if let last = lastNudgeSentAt, Date().timeIntervalSince(last) < 2.0 {
            cooldownErrorMessage = "Please wait a moment before sending another Nudge."
            return
        }
        lastNudgeSentAt = Date()
        cooldownErrorMessage = nil

        let nudgeMsg = ChatMessage.nudge(contactId: contact.id, author: .me)
        messages.append(nudgeMsg)
        MsnSoundPlayer.shared.play(.nudge)

        Task {
            try? await switchboardSession?.sendNudge()
            await shakeEngine.trigger()
        }
    }

    /// Handles an incoming Nudge from the remote contact.
    public func receiveNudge() {
        let nudgeMsg = ChatMessage.nudge(contactId: contact.id, author: .contact)
        messages.append(nudgeMsg)
        MsnSoundPlayer.shared.play(.nudge)

        Task {
            await shakeEngine.trigger()
        }
    }

    /// Sends a Tic-Tac-Toe move on the 3x3 board and syncs via `[GAME:TTT:MOVE:N]`.
    public func makeTicTacToeMove(slot: Int) {
        guard ticTacToe.applyMove(at: slot) else { return }
        let token = "[GAME:TTT:MOVE:\(slot)]"
        let gameMsg = ChatMessage(
            contactId: contact.id,
            author: .me,
            text: "Tic-Tac-Toe: placed \(ticTacToe.board[slot]?.rawValue ?? "X") at square \(slot + 1)",
            kind: .gameMove
        )
        messages.append(gameMsg)

        Task {
            try? await switchboardSession?.sendMessage(token, ackMode: .unacknowledged)
        }
    }

    public func resetTicTacToe() {
        ticTacToe.reset()
        let resetMsg = ChatMessage.system(contactId: contact.id, text: "Started a new game of Tic-Tac-Toe.")
        messages.append(resetMsg)
        Task {
            try? await switchboardSession?.sendMessage("[GAME:TTT:NEW]", ackMode: .unacknowledged)
        }
    }

    /// Appends a recorded Voice Clip (F2) message with 40-bar waveform metadata.
    public func sendVoiceClip(durationSeconds: Double, waveformSamples: [Float]) {
        let clip = VoiceClipInfo(
            id: UUID().uuidString,
            durationSeconds: durationSeconds,
            waveformSamples: waveformSamples
        )
        let msg = ChatMessage(
            contactId: contact.id,
            author: .me,
            text: String(format: "Voice Clip (%.1fs)", durationSeconds),
            kind: .voiceClip,
            voiceClip: clip
        )
        messages.append(msg)
        MsnSoundPlayer.shared.play(.outgoing)
    }

    /// Handles an incoming message from the remote contact (including game move interception).
    public func receiveIncomingMessage(_ text: String) {
        isPeerTyping = false
        if let token = TicTacToeGameState.parseToken(text) {
            if token.isNewGame {
                ticTacToe.reset()
                isTicTacToePresented = true
            } else if let slot = token.moveSlot {
                ticTacToe.applyMove(at: slot)
                isTicTacToePresented = true
            }
            return
        }

        let incoming = ChatMessage(
            contactId: contact.id,
            author: .contact,
            text: text,
            senderEmail: contact.email,
            senderName: contact.cleanDisplayName
        )
        messages.append(incoming)
        MsnSoundPlayer.shared.play(.newAlert)
    }
}
