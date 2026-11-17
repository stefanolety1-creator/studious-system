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
    @State private var hasCopiedLogs: Bool = false

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

                            if session.networkState == .connecting || session.networkState == .authenticating || session.networkState == .synchronizing {
                                Button {
                                    session.signOut()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "xmark.circle")
                                        Text("Cancel Connection")
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.msnBusy)
                                    .padding(.top, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .frame(maxWidth: 380)
                    .aeroGlassCard(cornerRadius: 20, fillOpacity: 0.90, borderAlpha: 0.65, sheenAlpha: 0.25)

                    // Real-Time Connection Diagnostics & Protocol Log Console
                    connectionLogSection

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

    private var connectionLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    session.isLogExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(Color.wlmPrimary)
                    Text("Connection Diagnostics & Log")
                        .font(.caption.bold())
                        .foregroundStyle(Color.wlmTextDark)
                    if !session.connectionLogs.isEmpty {
                        Text("\(session.connectionLogs.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.wlmPrimary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if session.networkState == .connecting || session.networkState == .authenticating || session.networkState == .synchronizing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Image(systemName: session.isLogExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .foregroundStyle(Color.wlmOnPrimaryContainer)
                }
            }
            .buttonStyle(.plain)

            if session.isLogExpanded || session.networkState == .connecting || session.networkState == .authenticating {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if session.connectionLogs.isEmpty {
                                    Text("No connection activity yet. Tap 'Sign In' or switch preset to begin.")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.gray)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(Array(session.connectionLogs.enumerated()), id: \.offset) { idx, log in
                                        Text(log)
                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                                            .foregroundStyle(
                                                log.contains("?") ? Color(red: 1.0, green: 0.45, blue: 0.45) :
                                                log.contains("?") || log.contains("??") ? Color(red: 0.4, green: 0.95, blue: 0.5) :
                                                log.contains("??") || log.contains("??") ? Color(red: 1.0, green: 0.85, blue: 0.3) :
                                                log.contains(">>") ? Color(red: 0.5, green: 0.8, blue: 1.0) :
                                                log.contains("<<") ? Color(red: 0.8, green: 0.6, blue: 1.0) :
                                                Color.white.opacity(0.92)
                                            )
                                            .textSelection(.enabled)
                                            .id(idx)
                                    }
                                }
                            }
                            .padding(10)
                        }
                        .frame(minHeight: 110, maxHeight: 180)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .onChange(of: session.connectionLogs.count) { _ in
                            if let last = session.connectionLogs.indices.last {
                                withAnimation {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = session.connectionLogs.joined(separator: "\n")
                            hasCopiedLogs = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                hasCopiedLogs = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasCopiedLogs ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(hasCopiedLogs ? "Copied!" : "Copy Log")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.wlmPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.85))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            session.clearLogs()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Clear")
                            }
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.wlmTextDark)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.55))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: 380)
        .aeroGlassCard(cornerRadius: 16, fillOpacity: 0.88, borderAlpha: 0.60, sheenAlpha: 0.20)
    }
}
