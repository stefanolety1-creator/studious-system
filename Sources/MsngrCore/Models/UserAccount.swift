import Foundation
import CryptoKit

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
        mainServer: String = "ds.escargot.nina.chat",
        mainPort: Int = 1863,
        switchboardPort: Int = 1863,
        configServer: String = "mconf.escargot.nina.chat",
        authServer: String = "https://nexus.escargot.chat/RST.srf",
        addressBookServer: String = "https://contacts.escargot.chat",
        storageServer: String = "https://storage.escargot.chat"
    ) {
        self.mainServer = mainServer
        self.mainPort = mainPort
        self.switchboardPort = switchboardPort
        self.configServer = configServer
        self.authServer = authServer
        self.addressBookServer = addressBookServer
        self.storageServer = storageServer
    }

    /// Standard Escargot community server preset.
    public static let escargot = ServerConfig()

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
        serverConfig: ServerConfig = .escargot,
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
