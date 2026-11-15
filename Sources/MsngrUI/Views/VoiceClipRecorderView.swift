import SwiftUI

/// Interactive WLM 2009 Voice Clip (F2) recorder sheet with 30-second cap and 40-bar retro waveform.
public struct VoiceClipRecorderView: View {
    @ObservedObject public var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isRecording: Bool = false
    @State private var elapsedSeconds: Double = 0.0
    @State private var waveformSamples: [Float] = (0..<40).map { _ in Float.random(in: 0.15...0.35) }
    @State private var timerTask: Task<Void, Never>?

    public static let maxDurationSeconds: Double = 30.0
    public static let barCount: Int = 40

    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Voice Clip (F2)", systemImage: "mic.fill")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.wlmOnPrimaryContainer)
                Spacer()
                Text(String(format: "%.1fs / 30.0s", elapsedSeconds))
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(elapsedSeconds >= 25.0 ? Color.msnBusy : Color.wlmPrimary)
            }

            // 40-bar retro WLM waveform canvas
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<waveformSamples.count, id: \.self) { idx in
                    let amp = CGFloat(max(0.1, min(1.0, waveformSamples[idx])))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.wlmSecondary, Color.wlmPrimary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: 10 + amp * 44)
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .aeroGlassCard(cornerRadius: 14)

            // Controls
            HStack(spacing: 16) {
                Button("Cancel") {
                    stopRecording()
                    dismiss()
                }
                .foregroundStyle(Color.wlmTextMuted)

                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Label(isRecording ? "Stop" : "Record", systemImage: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .aeroGlossyButton(
                            cornerRadius: 20,
                            baseColor: isRecording ? .msnBusy : .wlmPrimary
                        )
                }
                .buttonStyle(.plain)

                Button {
                    stopRecording()
                    let duration = max(1.0, elapsedSeconds)
                    viewModel.sendVoiceClip(durationSeconds: duration, waveformSamples: waveformSamples)
                    dismiss()
                } label: {
                    Label("Send Clip", systemImage: "paperplane.fill")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .aeroGlossyButton(cornerRadius: 20, baseColor: .wlmSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(LinearGradient.wlmAtmosphereLight.ignoresSafeArea())
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        elapsedSeconds = 0.0
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled && elapsedSeconds < Self.maxDurationSeconds {
                try? await Task.sleep(nanoseconds: 100_000_000)
                elapsedSeconds = min(Self.maxDurationSeconds, elapsedSeconds + 0.1)
                var updated = Array(waveformSamples.dropFirst())
                updated.append(Float.random(in: 0.20...0.95))
                waveformSamples = updated
            }
            isRecording = false
        }
    }

    private func stopRecording() {
        isRecording = false
        timerTask?.cancel()
        timerTask = nil
    }
}
