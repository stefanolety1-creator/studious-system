import SwiftUI
import MsngrCore

/// Account, Theme, Scene, Sound, and MSNP18 Server configuration view.
public struct SettingsView: View {
    @ObservedObject public var session: SessionViewModel
    @ObservedObject public var soundPlayer: MsnSoundPlayer = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: ServerPreset = .crosstalk
    @State private var mainServer: String = ""
    @State private var mainPort: String = ""
    @State private var switchboardPort: String = ""
    @State private var configServer: String = ""
    @State private var authServer: String = ""
    @State private var addressBookServer: String = ""
    @State private var storageServer: String = ""

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

                Section("MSNP18 Server Configuration") {
                    Picker("Server Preset", selection: $selectedPreset) {
                        Text("Crosstalk").tag(ServerPreset.crosstalk)
                        Text("Escargot").tag(ServerPreset.escargot)
                        Text("Custom").tag(ServerPreset.custom)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPreset) { newPreset in
                        applyPreset(newPreset)
                    }

                    TextField("Notification Server Host", text: $mainServer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Notification Port (1863)", text: $mainPort)
                        .keyboardType(.numberPad)
                    TextField("Switchboard Port (1864 / 1863)", text: $switchboardPort)
                        .keyboardType(.numberPad)
                    TextField("Configuration Host", text: $configServer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Passport RST2 Auth URL", text: $authServer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("ABCH Contacts URL", text: $addressBookServer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Storage Server URL", text: $storageServer)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack(spacing: 12) {
                        Button("Apply Crosstalk Defaults") {
                            applyPreset(.crosstalk)
                        }
                        .buttonStyle(.borderless)

                        Button("Apply Escargot Defaults") {
                            applyPreset(.escargot)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.footnote)
                }

                Section("About") {
                    LabeledContent("Protocol", value: "MSNP18 (WLM 2009 Wave 3)")
                    LabeledContent("Client Version", value: "14.0.8117.0416 (iOS SwiftUI)")
                    LabeledContent("Active Preset", value: selectedPreset.displayName)
                }
            }
            .navigationTitle("Options & Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveConfiguration()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadCurrentConfiguration()
            }
        }
    }

    private func applyPreset(_ preset: ServerPreset) {
        selectedPreset = preset
        let cfg: ServerConfig
        switch preset {
        case .crosstalk:
            cfg = .crosstalk
        case .escargot:
            cfg = .escargot
        case .custom:
            return
        }
        mainServer = cfg.mainServer
        mainPort = String(cfg.mainPort)
        switchboardPort = String(cfg.switchboardPort)
        configServer = cfg.configServer
        authServer = cfg.authServer
        addressBookServer = cfg.addressBookServer
        storageServer = cfg.storageServer
    }

    private func loadCurrentConfiguration() {
        let cfg = session.currentAccount.serverConfig
        selectedPreset = cfg.preset
        mainServer = cfg.mainServer
        mainPort = String(cfg.mainPort)
        switchboardPort = String(cfg.switchboardPort)
        configServer = cfg.configServer
        authServer = cfg.authServer
        addressBookServer = cfg.addressBookServer
        storageServer = cfg.storageServer
    }

    private func saveConfiguration() {
        var cfg = session.currentAccount.serverConfig
        let cleanMain = mainServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanMain.isEmpty {
            cfg.mainServer = cleanMain
        }
        if let port = Int(mainPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) {
            cfg.mainPort = port
        }
        if let sbPort = Int(switchboardPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(sbPort) {
            cfg.switchboardPort = sbPort
        }
        let cleanConfig = configServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanConfig.isEmpty {
            cfg.configServer = cleanConfig
        }
        let cleanAuth = authServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanAuth.isEmpty {
            cfg.authServer = cleanAuth
        }
        let cleanAbch = addressBookServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanAbch.isEmpty {
            cfg.addressBookServer = cleanAbch
        }
        let cleanStorage = storageServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanStorage.isEmpty {
            cfg.storageServer = cleanStorage
        }
        session.currentAccount.serverConfig = cfg
    }
}
