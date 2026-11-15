import SwiftUI
import MsngrCore

/// Authentic Windows Live Messenger 2009 Frutiger Aero Login Screen.
public struct LoginView: View {
    @ObservedObject public var session: SessionViewModel

    @State private var email: String = "stefano@escargot.chat"
    @State private var password: String = ""
    @State private var selectedPresence: PresenceStatus = .online
    @State private var rememberMe: Bool = true
    @State private var automaticSignIn: Bool = false
    @State private var isServerSettingsPresented: Bool = false

    public init(session: SessionViewModel) {
        self.session = session
    }

    public var body: some View {
        ZStack {
            // Atmospheric Sky-to-Meadow Backdrop
            (session.activeSkin.isDark ? LinearGradient.wlmAtmosphereDark : LinearGradient.wlmAtmosphereLight)
                .ignoresSafeArea()

            // Overhead Sunburst Glow
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color.white.opacity(0.45), Color.clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: geo.size.width * 0.75
                )
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 22) {
                    // Top WLM Banner & Dual Buddy Logo
                    VStack(spacing: 10) {
                        ZStack {
                            AeroAvatarFrameView(
                                displayName: email,
                                status: selectedPresence,
                                size: 78,
                                symbolName: "person.2.fill"
                            )
                        }
                        .padding(.top, 16)

                        Text("Windows Live")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.wlmOnPrimaryContainer)
                        Text("Messenger")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.wlmPrimary)
                    }

                    // Aero Glass Login Card
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Windows Live ID:")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextDark)
                            TextField("name@example.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password:")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextDark)
                            SecureField("Enter your password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Sign-in Status Picker
                        HStack {
                            Text("Sign in as:")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextDark)
                            MsnPresenceIcon(status: selectedPresence)
                            Picker("Sign in as", selection: $selectedPresence) {
                                Text("Online").tag(PresenceStatus.online)
                                Text("Busy").tag(PresenceStatus.busy)
                                Text("Away").tag(PresenceStatus.away)
                                Text("Appear Offline").tag(PresenceStatus.hidden)
                            }
                            .labelsHidden()
                            Spacer()
                        }

                        Toggle("Remember my ID and password", isOn: $rememberMe)
                            .font(.caption)
                            .foregroundStyle(Color.wlmTextDark)

                        Toggle("Sign me in automatically", isOn: $automaticSignIn)
                            .font(.caption)
                            .foregroundStyle(Color.wlmTextDark)

                        if let err = session.lastErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(Color.msnBusy)
                                .padding(.top, 2)
                        }

                        // Action Buttons
                        VStack(spacing: 10) {
                            Button {
                                Task {
                                    if password.isEmpty {
                                        session.signInDemoMode(email: email, initialPresence: selectedPresence)
                                    } else {
                                        await session.signInLive(email: email, password: password, initialPresence: selectedPresence)
                                    }
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(session.networkState == .disconnected ? "Sign In" : session.networkState.rawValue)
                                        .font(.system(.body, design: .rounded).bold())
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 11)
                                .aeroGlossyButton(cornerRadius: 22, baseColor: .wlmPrimary, highlightIntensity: 0.40)
                            }
                            .buttonStyle(.plain)

                            Button {
                                session.signInDemoMode(email: email, initialPresence: selectedPresence)
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Explore Offline / Demo Mode", systemImage: "sparkles")
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .aeroGlossyButton(cornerRadius: 20, baseColor: .wlmSecondary, highlightIntensity: 0.35)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .frame(maxWidth: 380)
                    .aeroGlassCard(cornerRadius: 20, fillOpacity: 0.90, borderAlpha: 0.65, sheenAlpha: 0.25)

                    // Server Config Link
                    Button {
                        isServerSettingsPresented = true
                    } label: {
                        Label(
                            "Server: \(session.currentAccount.serverConfig.mainServer):\(session.currentAccount.serverConfig.mainPort)",
                            systemImage: "server.rack"
                        )
                        .font(.caption)
                        .foregroundStyle(Color.wlmOnPrimaryContainer)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $isServerSettingsPresented) {
            SettingsView(session: session)
        }
    }
}
