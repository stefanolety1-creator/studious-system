import SwiftUI
import MsngrCore

/// Authentic Windows Live Messenger 2009 Frutiger Aero Login Screen.
public struct LoginView: View {
    @ObservedObject public var session: SessionViewModel

    @State private var email: String = "stefano@crosstalk.im"
    @State private var password: String = ""
    @State private var selectedPresence: PresenceStatus = .online
    @State private var rememberMe: Bool = true
    @State private var automaticSignIn: Bool = false
    @State private var isServerSettingsPresented: Bool = false
    @State private var selectedPreset: ServerPreset = .crosstalk
    @State private var validationError: String?

    public init(session: SessionViewModel) {
        self.session = session
    }

    private var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
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
                        // One-Tap Server Preset Switching
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Service:")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextDark)
                            Picker("Service Preset", selection: $selectedPreset) {
                                Text("Crosstalk").tag(ServerPreset.crosstalk)
                                Text("Escargot").tag(ServerPreset.escargot)
                                Text("Custom").tag(ServerPreset.custom)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedPreset) { newPreset in
                                switch newPreset {
                                case .crosstalk:
                                    session.currentAccount.serverConfig = .crosstalk
                                case .escargot:
                                    session.currentAccount.serverConfig = .escargot
                                case .custom:
                                    isServerSettingsPresented = true
                                }
                            }
                        }

                        // Windows Live ID / Email field (strictly email, not alias/username)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Windows Live ID (Email):")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextDark)
                            TextField("user@domain.com", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .onChange(of: email) { _ in
                                    validationError = nil
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password:")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextDark)
                            SecureField("Enter your password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
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

                        if let err = validationError ?? session.lastErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(Color.msnBusy)
                                .padding(.top, 2)
                        }

                        // Action Buttons
                        VStack(spacing: 10) {
                            Button {
                                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard isEmailValid else {
                                    validationError = "Please enter a valid Windows Live ID email address (e.g. name@domain.com)."
                                    return
                                }
                                validationError = nil

                                Task {
                                    if password.isEmpty {
                                        session.signInDemoMode(email: trimmedEmail, initialPresence: selectedPresence)
                                    } else {
                                        await session.signInLive(email: trimmedEmail, password: password, initialPresence: selectedPresence)
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
                                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                session.signInDemoMode(email: trimmedEmail.isEmpty ? "stefano@crosstalk.im" : trimmedEmail, initialPresence: selectedPresence)
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

                    // Server Config Link & Preset Indicator
                    Button {
                        isServerSettingsPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack")
                            Text("\(selectedPreset.rawValue): \(session.currentAccount.serverConfig.mainServer):\(session.currentAccount.serverConfig.mainPort)")
                        }
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
        .onAppear {
            selectedPreset = session.currentAccount.serverConfig.preset
            if email == "stefano@escargot.chat" {
                email = "stefano@crosstalk.im"
            }
        }
    }
}
