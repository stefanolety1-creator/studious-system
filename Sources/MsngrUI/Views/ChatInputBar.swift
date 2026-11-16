import SwiftUI
import MsngrCore

/// WLM 2009 Chat Composer Bar with Messenger Plus! BBCode formatting buttons, Emoticon quick-insert, Nudge, Voice Clip (F2), and Aero Glossy Send button.
public struct ChatInputBar: View {
    @ObservedObject public var viewModel: ChatViewModel

    @State private var isColorPickerPresented: Bool = false

    private let quickColors: [(index: Int, hex: UInt32, name: String)] = [
        (4, 0xFF0000, "Red"),
        (12, 0x0078D7, "WLM Blue"),
        (3, 0x009300, "MSN Green"),
        (6, 0x9C009C, "Purple"),
        (7, 0xFC7F00, "Orange"),
        (13, 0xFF00FF, "Pink")
    ]

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Top Action & Formatting Toolbar
            HStack(spacing: 10) {
                // Bold [b]
                Button {
                    viewModel.insertBBCodeTag("b")
                } label: {
                    Image(systemName: "bold")
                        .font(.caption.bold())
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)

                // Italic [i]
                Button {
                    viewModel.insertBBCodeTag("i")
                } label: {
                    Image(systemName: "italic")
                        .font(.caption.bold())
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)

                // Underline [u]
                Button {
                    viewModel.insertBBCodeTag("u")
                } label: {
                    Image(systemName: "underline")
                        .font(.caption.bold())
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)

                // Strikethrough [s]
                Button {
                    viewModel.insertBBCodeTag("s")
                } label: {
                    Image(systemName: "strikethrough")
                        .font(.caption.bold())
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)

                // Messenger Plus! Color Menu [c=N]
                Menu {
                    ForEach(quickColors, id: \.index) { item in
                        Button("Color \(item.name) [c=\(item.index)]") {
                            viewModel.insertBBCodeTag("c", parameter: String(item.index))
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.caption.bold())
                        .foregroundStyle(Color.wlmPrimary)
                        .frame(width: 26, height: 24)
                }

                Divider()
                    .frame(height: 16)

                // Nudge Button
                Button {
                    viewModel.sendNudge()
                } label: {
                    Label("Nudge", systemImage: "bell.and.waves.left.and.right.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.msnAwayBorder)
                }
                .buttonStyle(.plain)

                // Winks Button
                Button {
                    viewModel.isWinkPickerPresented = true
                } label: {
                    Label("Winks", systemImage: "sparkles.tv.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.wlmSecondary)
                }
                .buttonStyle(.plain)

                // Voice Clip (F2) Button
                Button {
                    viewModel.isVoiceRecorderPresented = true
                } label: {
                    Label("Voice Clip", systemImage: "mic.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.wlmPrimary)
                }
                .buttonStyle(.plain)

                // Tic-Tac-Toe Mini-Game Button
                Button {
                    viewModel.isTicTacToePresented = true
                } label: {
                    Label("Games", systemImage: "gamecontroller.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.wlmSecondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            // Text Input & Glossy Send Button
            HStack(spacing: 10) {
                TextField("Type a message...", text: $viewModel.draftText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .rounded))
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                Button {
                    viewModel.sendMessage()
                } label: {
                    Text("Send")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .aeroGlossyButton(cornerRadius: 18, baseColor: .wlmPrimary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(Color.wlmSurfaceVariant)
        .overlay(
            Rectangle()
                .fill(Color.wlmOutline)
                .frame(height: 1),
            alignment: .top
        )
    }
}
