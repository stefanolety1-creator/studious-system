import Foundation
import CryptoKit

/// Supported MSNP18 server presets.
public enum ServerPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case crosstalk = "Crosstalk"
    case escargot = "Escargot"
    case custom = "Custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crosstalk:
            return "Crosstalk (Default)"
        case .escargot:
            return "Escargot"
        case .custom:
            return "Custom"
        }
    }
}

/// Configuration endpoints for MSNP18 Notification Server, SOAP services, and switches.
public struct ServerConfig: Hashable, Codable, Sendable {
    public var mainServer: String
    public var mainPort: Int
    public var switchboardPort: Int
    public var configServer: String
    public var authServer: String
    public var addressBookServer: String
    public var storageServer: String

    public init(
        mainServer: String = "ms.msgrsvcs.ctsrv.gay",
        mainPort: Int = 1863,
        switchboardPort: Int = 1864,
        configServer: String = "conf.msgrsvcs.ctsrv.gay",
        authServer: String = "https://ctas.login.ugnet.gay/RST.srf",
        addressBookServer: String = "https://ctsvcs.addressbook.ugnet.gay/abservice/abservice.asmx",
        storageServer: String = "https://cts.storage.ugnet.gay/storageservice/SchematizedStore.asmx"
    ) {
        self.mainServer = mainServer
        self.mainPort = mainPort
        self.switchboardPort = switchboardPort
        self.configServer = configServer
        self.authServer = authServer
        self.addressBookServer = addressBookServer
        self.storageServer = storageServer
    }

    /// Active default community preset (Crosstalk).
    public static let crosstalk = ServerConfig(
        mainServer: "ms.msgrsvcs.ctsrv.gay",
        mainPort: 1863,
        switchboardPort: 1864,
        configServer: "conf.msgrsvcs.ctsrv.gay",
        authServer: "https://ctas.login.ugnet.gay/RST.srf",
        addressBookServer: "https://ctsvcs.addressbook.ugnet.gay/abservice/abservice.asmx",
        storageServer: "https://cts.storage.ugnet.gay/storageservice/SchematizedStore.asmx"
    )

    /// Standard Escargot retro server preset.
    public static let escargot = ServerConfig(
        mainServer: "ds.escargot.nina.chat",
        mainPort: 1863,
        switchboardPort: 1863,
        configServer: "mconf.escargot.nina.chat",
        authServer: "https://nexus.escargot.chat/RST.srf",
        addressBookServer: "https://contacts.escargot.chat",
        storageServer: "https://storage.escargot.chat"
    )

    /// Local offline mock server preset for unit and integration testing.
    public static let mock = ServerConfig(
        mainServer: "127.0.0.1",
        mainPort: 1863,
        switchboardPort: 1863,
        configServer: "127.0.0.1",
        authServer: "http://127.0.0.1:8080/RST.srf",
        addressBookServer: "http://127.0.0.1:8080/abservice",
        storageServer: "http://127.0.0.1:8080/storage"
    )

    /// Factory for custom server configuration matching SCOPE.md interface contract.
    public static func custom(
        host: String,
        port: Int = 1863,
        switchboardPort: Int = 1864,
        authServerUrl: String = ""
    ) -> ServerConfig {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let auth = authServerUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://\(cleanHost)/RST.srf"
            : authServerUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuth = auth.hasPrefix("http://") || auth.hasPrefix("https://") ? auth : "https://\(auth)/RST.srf"
        return ServerConfig(
            mainServer: cleanHost,
            mainPort: port,
            switchboardPort: switchboardPort,
            configServer: cleanHost,
            authServer: resolvedAuth,
            addressBookServer: "https://\(cleanHost)",
            storageServer: "https://\(cleanHost)"
        )
    }

    /// Evaluates which preset matches this configuration.
    public var preset: ServerPreset {
        if mainServer == Self.crosstalk.mainServer &&
           mainPort == Self.crosstalk.mainPort &&
           switchboardPort == Self.crosstalk.switchboardPort {
            return .crosstalk
        } else if mainServer == Self.escargot.mainServer &&
                  mainPort == Self.escargot.mainPort {
            return .escargot
        } else {
            return .custom
        }
    }

    /// Resolves valid URL for Passport SOAP RST authentication.
    public var authServerUrl: URL? {
        let trimmed = authServer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        } else if !trimmed.isEmpty {
            return URL(string: "https://\(trimmed)/RST.srf")
        }
        return nil
    }

    /// Validates endpoint sanity matching Android ServerOverrides.isValid().
    public var isValid: Bool {
        !mainServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !configServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...65535).contains(mainPort) &&
        (1...65535).contains(switchboardPort)
    }
}

/// Represents the local authenticated user profile, saved settings, and active session preferences.
public struct UserAccount: Identifiable, Hashable, Codable, Sendable {
    /// Unique storage key derived from email and server endpoint.
    public var id: String { storageKey }

    /// Normalized passport email address.
    public let email: String

    /// Friendly display name.
    public var displayName: String

    /// Personal status message (PSM / "Now Playing").
    public var personalMessage: String

    /// Initial or active presence status.
    public var presence: PresenceStatus

    /// Local file path or cached URI of display picture.
    public var avatarUri: String?

    /// Saved password string (if rememberPassword == true).
    public var savedPassword: String?

    /// Indicates whether password should be persisted in keychain / local store.
    public var rememberPassword: Bool

    /// Indicates whether client should automatically log in on application launch.
    public var automaticSignIn: Bool

    /// Active network endpoints configuration.
    public var serverConfig: ServerConfig

    /// Indicates whether to direct connections to local mock server.
    public var useMockServer: Bool

    /// Timestamp of last successful login.
    public var lastLoginDate: Date?

    public init(
        email: String,
        displayName: String? = nil,
        personalMessage: String = "",
        presence: PresenceStatus = .online,
        avatarUri: String? = nil,
        savedPassword: String? = nil,
        rememberPassword: Bool = false,
        automaticSignIn: Bool = false,
        serverConfig: ServerConfig = .crosstalk,
        useMockServer: Bool = false,
        lastLoginDate: Date? = nil
    ) {
        self.email = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName ?? self.email
        self.personalMessage = personalMessage
        self.presence = presence
        self.avatarUri = avatarUri
        self.savedPassword = savedPassword
        self.rememberPassword = rememberPassword
        self.automaticSignIn = automaticSignIn
        self.serverConfig = serverConfig
        self.useMockServer = useMockServer
        self.lastLoginDate = lastLoginDate
    }

    /// Storage key isolating mock accounts from live server accounts.
    public var storageKey: String {
        let service = useMockServer ? "mock" : "msnp://\(serverConfig.mainServer.lowercased()):\(serverConfig.mainPort)"
        let raw = "\(email)\0\(service)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
