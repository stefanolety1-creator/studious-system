import SwiftUI
import MsngrCore

/// Account, Theme, Scene, Sound, and Escargot Server configuration view.
public struct SettingsView: View {
    @ObservedObject public var session: SessionViewModel
    @ObservedObject public var soundPlayer: MsnSoundPlayer = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var mainServer: String = ""
    @State private var mainPort: String = ""
    @State private var authServer: String = ""
    @State private var addressBookServer: String = ""

    public init(session: SessionViewModel) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Frutiger Aero Appearance") {
                    Picker("Skin", selection: $session.activeSkin) {
                        ForEach(AeroSkin.allCases) { skin in
                            Text(skin.rawValue).tag(skin)
                        }
                    }

                    Picker("Header Scene", selection: $session.activeScene) {
                        ForEach(WlmScene.allCases) { scene in
                            Text(scene.rawValue).tag(scene)
                        }
                    }

                    Toggle("Classic WLM 2009 Unbubbled Chat (\"You say:\")", isOn: $session.useClassicChatLayout)
                }

                Section("Messenger Plus! Live") {
                    Toggle("Enable BBCode & Gradient Formatting", isOn: $session.enableMessengerPlusFormatting)
                }

                Section("Sounds & Alerts") {
                    Toggle("Play WLM 2009 Sound Effects", isOn: $soundPlayer.isSoundEnabled)
                    Toggle("Vibrate on Incoming Nudge", isOn: $soundPlayer.isVibrationEnabled)
                }

                Section("MSNP18 Server Configuration (Escargot / Custom)") {
                    TextField("Notification Server Host", text: $mainServer)
                    TextField("Port", text: $mainPort)
                    TextField("Passport RST2 Auth URL", text: $authServer)
                    TextField("ABCH Contacts URL", text: $addressBookServer)

                    Button("Restore Escargot Defaults") {
                        let def = ServerConfig.escargot
                        mainServer = def.mainServer
                        mainPort = String(def.mainPort)
                        authServer = def.authServer
                        addressBookServer = def.addressBookServer
                    }
                }

                Section("About") {
                    LabeledContent("Protocol", value: "MSNP18 (WLM 2009 Wave 3)")
                    LabeledContent("Client Version", value: "14.0.8117.0416 (iOS SwiftUI)")
                }
            }
            .navigationTitle("Options & Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !mainServer.isEmpty {
                            session.currentAccount.serverConfig.mainServer = mainServer
                        }
                        if let port = Int(mainPort) {
                            session.currentAccount.serverConfig.mainPort = port
                        }
                        if !authServer.isEmpty {
                            session.currentAccount.serverConfig.authServer = authServer
                        }
                        if !addressBookServer.isEmpty {
                            session.currentAccount.serverConfig.addressBookServer = addressBookServer
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                let cfg = session.currentAccount.serverConfig
                mainServer = cfg.mainServer
                mainPort = String(cfg.mainPort)
                authServer = cfg.authServer
                addressBookServer = cfg.addressBookServer
            }
        }
    }
}
