import SwiftUI
import MsngrCore

/// Active 1:1 / Group Chat Screen with WLM Sky Header, Dual Message Rendering Mode (Classic "You say:" vs Modern Bubbles), Nudge Shake offset, Voice Clips, and Tic-Tac-Toe.
public struct ChatView: View {
    @ObservedObject public var session: SessionViewModel
    @ObservedObject public var viewModel: ChatViewModel
    @ObservedObject private var shakeEngine: NudgeShakeEngine

    public init(session: SessionViewModel, viewModel: ChatViewModel) {
        self.session = session
        self.viewModel = viewModel
        self.shakeEngine = viewModel.shakeEngine
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Chat Header Banner
            ZStack(alignment: .leading) {
                session.activeScene.headerGradient
                    .frame(height: 76)

                HStack(spacing: 12) {
                    AeroAvatarFrameView(
                        displayName: viewModel.contact.displayName,
                        status: viewModel.contact.presence,
                        size: 50
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(MessengerPlusParser.parseToAttributedString(
                                viewModel.contact.displayName,
                                adaptiveColor: session.activeScene.isDarkText ? .wlmTextDark : .white,
                                baseFontSize: 16
                            ))
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                            MsnPresenceIcon(status: viewModel.contact.presence, size: 11)
                        }

                        if viewModel.isPeerTyping {
                            Text("\(viewModel.contact.cleanDisplayName) is typing a message...")
                                .font(.caption.italic())
                                .foregroundStyle(session.activeScene.isDarkText ? Color.wlmPrimary : Color.white)
                        } else if !viewModel.contact.statusMessage.isEmpty {
                            Text(viewModel.contact.cleanStatusMessage)
                                .font(.caption)
                                .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextMuted : Color.white.opacity(0.88))
                                .lineLimit(1)
                        } else {
                            Text(viewModel.contact.email)
                                .font(.caption)
                                .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextMuted : Color.white.opacity(0.85))
                        }
                    }

                    Spacer()

                    // Quick Toggle: Classic WLM 2009 vs Modern Aero Bubbles
                    Button {
                        session.useClassicChatLayout.toggle()
                    } label: {
                        Label(
                            session.useClassicChatLayout ? "Classic" : "Bubbles",
                            systemImage: session.useClassicChatLayout ? "text.alignleft" : "bubble.left.and.bubble.right.fill"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextDark : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 76)

            // Message History List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.messages) { msg in
                            messageRow(for: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(14)
                }
                .background(Color.white)
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            if let cooldownErr = viewModel.cooldownErrorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.msnAwayBorder)
                    Text(cooldownErr)
                        .font(.caption)
                        .foregroundStyle(Color.wlmTextDark)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.wlmSecondaryContainer)
            }

            // Bottom Composer Bar
            ChatInputBar(viewModel: viewModel)
        }
        .offset(x: shakeEngine.offsetX, y: shakeEngine.offsetY)
        .sheet(isPresented: $viewModel.isTicTacToePresented) {
            TicTacToeView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isVoiceRecorderPresented) {
            VoiceClipRecorderView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func messageRow(for message: ChatMessage) -> some View {
        switch message.kind {
        case .nudge:
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color.wlmTextDark)
                    .frame(width: 170, height: 1.5)
                Text(message.text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.wlmTextDark)
                Rectangle()
                    .fill(Color.wlmTextDark)
                    .frame(width: 170, height: 1.5)
            }
            .padding(.vertical, 4)

        case .system, .gameMove:
            HStack {
                Image(systemName: message.kind == .gameMove ? "gamecontroller.fill" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.wlmPrimary)
                Text(message.text)
                    .font(.caption.italic())
                    .foregroundStyle(Color.wlmTextMuted)
            }
            .padding(.vertical, 2)

        case .voiceClip:
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.wlmPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.caption.bold())
                        .foregroundStyle(Color.wlmTextDark)
                    HStack(spacing: 2) {
                        ForEach(0..<20, id: \.self) { idx in
                            let samples = message.voiceClip?.waveformSamples ?? []
                            let sample = idx < samples.count ? CGFloat(samples[idx]) : 0.4
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.wlmPrimary)
                                .frame(width: 3, height: 6 + sample * 16)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(message.author == .me ? Color.wlmBubbleOutgoing : Color.wlmBubbleIncoming)
            )

        default:
            if session.useClassicChatLayout {
                // Classic WLM 2009 Unbubbled Mode ("You say:" / "[Contact] says:")
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.author == .me ? "You say:" : "\(viewModel.contact.cleanDisplayName) says:")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(message.author == .me ? Color.wlmSenderMe : Color.wlmSenderPeer)

                    HStack(alignment: .firstTextBaseline) {
                        if session.enableMessengerPlusFormatting {
                            Text(message.formattedText)
                                .padding(.leading, 10)
                        } else {
                            Text(MessengerPlusParser.stripFormatting(message.text))
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.wlmTextDark)
                                .padding(.leading, 10)
                        }
                        Spacer()
                        Text(message.timestamp, style: .time)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color.wlmTextMuted.opacity(0.75))
                    }
                }
            } else {
                // Modern Frutiger Aero Bubble Mode
                HStack {
                    if message.author == .me { Spacer(minLength: 40) }

                    VStack(alignment: message.author == .me ? .trailing : .leading, spacing: 4) {
                        if session.enableMessengerPlusFormatting {
                            Text(message.formattedText)
                        } else {
                            Text(MessengerPlusParser.stripFormatting(message.text))
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.wlmTextDark)
                        }

                        Text(message.timestamp, style: .time)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color.wlmTextMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.author == .me ? Color.wlmBubbleOutgoing : Color.wlmBubbleIncoming)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.wlmOutlineVariant, lineWidth: 1)
                            )
                    )

                    if message.author != .me { Spacer(minLength: 40) }
                }
            }
        }
    }
}
