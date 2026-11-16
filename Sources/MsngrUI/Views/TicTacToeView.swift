import SwiftUI
import MsngrCore

/// Interactive 3x3 Tic-Tac-Toe mini-game sheet synced over Switchboard text tokens (`[GAME:TTT:MOVE:N]`).
public struct TicTacToeView: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    private var statusText: String {
        if let winner = viewModel.ticTacToe.winner {
            return "Player \(winner.rawValue) wins!"
        }
        if viewModel.ticTacToe.isDraw {
            return "It's a draw!"
        }
        return "Current turn: \(viewModel.ticTacToe.currentTurn.rawValue)"
    }

    public var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack {
                Image(systemName: "grid")
                    .font(.title2.bold())
                    .foregroundStyle(Color.wlmPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MSN Games - Tic-Tac-Toe")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.wlmTextDark)
                    Text("Playing with \(viewModel.contact.cleanDisplayName)")
                        .font(.caption)
                        .foregroundStyle(Color.wlmTextMuted)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .font(.subheadline.bold())
            }
            .padding(.horizontal)

            Text(statusText)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Capsule().fill(Color.wlmPrimaryContainer))
                .foregroundStyle(Color.wlmOnPrimaryContainer)

            // 3x3 Grid
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            let mark = viewModel.ticTacToe.board[index]
                            Button {
                                viewModel.makeTicTacToeMove(slot: index)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white)
                                        .frame(width: 78, height: 78)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.wlmOutline, lineWidth: 1.5)
                                        )

                                    if let mark = mark {
                                        Text(mark.rawValue)
                                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                                            .foregroundStyle(mark == .x ? Color.wlmPrimary : Color.wlmSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(mark != nil || viewModel.ticTacToe.winner != nil || viewModel.ticTacToe.isDraw)
                        }
                    }
                }
            }
            .padding(14)
            .aeroGlassCard(cornerRadius: 18)

            // Controls
            HStack(spacing: 14) {
                Button {
                    viewModel.resetTicTacToe()
                } label: {
                    Label("New Game", systemImage: "arrow.counterclockwise")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .aeroGlossyButton(cornerRadius: 18, baseColor: .wlmPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(LinearGradient.wlmAtmosphereLight.ignoresSafeArea())
    }
}
