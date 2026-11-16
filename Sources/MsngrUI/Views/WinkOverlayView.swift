import SwiftUI
import MsngrCore

/// Catalog of classic Windows Live Messenger 2009 animated Winks.
public struct ClassicWinks {
    public static let catalog: [WinkReference] = [
        WinkReference(id: "knock_knock", name: "Knock Knock", thumbnailUri: "hand.raised.fill"),
        WinkReference(id: "laugh", name: "Laughing", thumbnailUri: "face.smiling.inverse"),
        WinkReference(id: "kiss", name: "Big Kiss", thumbnailUri: "mouth.fill"),
        WinkReference(id: "water_balloon", name: "Water Balloon", thumbnailUri: "drop.fill"),
        WinkReference(id: "guitar", name: "Guitar Smash", thumbnailUri: "guitars.fill"),
        WinkReference(id: "ghost", name: "Spooky Ghost", thumbnailUri: "moon.stars.fill"),
        WinkReference(id: "heart", name: "Glowing Heart", thumbnailUri: "heart.fill"),
        WinkReference(id: "bye", name: "Bye Bye", thumbnailUri: "hand.wave.fill")
    ]
}

/// Full-screen animated overlay for playing WLM 2009 Winks with scaling, rotation, and auto-dismiss.
public struct WinkOverlayView: View {
    public let wink: WinkReference
    public let onFinished: () -> Void

    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 0.0
    @State private var rotation: Double = -15
    @State private var bounceOffset: CGFloat = 0
    @State private var secondaryScale: CGFloat = 0.8

    public init(wink: WinkReference, onFinished: @escaping () -> Void) {
        self.wink = wink
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            // Subtle frosted background
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    onFinished()
                }

            VStack(spacing: 16) {
                ZStack {
                    // Outer glow pulse
                    Circle()
                        .fill(RadialGradient(
                            colors: [winkColor.opacity(0.45), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 110
                        ))
                        .frame(width: 220, height: 220)
                        .scaleEffect(secondaryScale)

                    // Wink Icon / Artwork
                    winkVisual
                        .font(.system(size: 84, weight: .bold))
                        .foregroundStyle(winkColor)
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(rotation))
                        .offset(y: bounceOffset)
                        .shadow(color: winkColor.opacity(0.6), radius: 18, x: 0, y: 6)
                }

                Text(wink.name)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .shadow(radius: 4)
            }
            .opacity(opacity)
        }
        .onAppear {
            MsnSoundPlayer.shared.play(.callstart)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                scale = 1.2
                opacity = 1.0
                rotation = 0
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                secondaryScale = 1.3
                bounceOffset = -12
            }
            // Auto-dismiss after 2.6 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation(.easeOut(duration: 0.35)) {
                    scale = 0.1
                    opacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFinished()
                }
            }
        }
    }

    private var winkColor: Color {
        switch wink.id {
        case "kiss", "heart":
            return Color.red
        case "laugh":
            return Color.yellow
        case "water_balloon":
            return Color.cyan
        case "guitar":
            return Color.orange
        case "ghost":
            return Color.purple
        case "knock_knock":
            return Color.wlmPrimary
        default:
            return Color.wlmSecondary
        }
    }

    @ViewBuilder
    private var winkVisual: some View {
        switch wink.id {
        case "knock_knock":
            Image(systemName: "hand.raised.fill")
        case "laugh":
            Image(systemName: "face.smiling.inverse")
        case "kiss":
            Image(systemName: "mouth.fill")
        case "water_balloon":
            Image(systemName: "drop.fill")
        case "guitar":
            Image(systemName: "guitars.fill")
        case "ghost":
            Image(systemName: "moon.stars.fill")
        case "heart":
            Image(systemName: "heart.fill")
        default:
            Image(systemName: "hand.wave.fill")
        }
    }
}

/// Catalog Grid Picker for selecting and sending Winks.
public struct WinkPickerSheet: View {
    public let onSelect: (WinkReference) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 14)
    ]

    public init(onSelect: @escaping (WinkReference) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ClassicWinks.catalog) { wink in
                        Button {
                            onSelect(wink)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.wlmSurfaceVariant)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.wlmOutline, lineWidth: 1)
                                        )

                                    Image(systemName: wink.thumbnailUri ?? "sparkles")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.wlmPrimary)
                                }

                                Text(wink.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.wlmTextDark)
                                    .lineLimit(1)
                            }
                            .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .navigationTitle("Select a Wink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
