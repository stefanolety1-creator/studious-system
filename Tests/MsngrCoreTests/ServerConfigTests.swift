import XCTest
@testable import MsngrCore

final class ServerConfigTests: XCTestCase {

    // MARK: - Crosstalk Preset Tests

    func test_crosstalkPreset_endpoints() {
        let config = ServerConfig.crosstalk
        XCTAssertEqual(config.mainServer, "ms.msgrsvcs.ctsrv.gay", "Crosstalk NS host must match specification")
        XCTAssertEqual(config.mainPort, 1863, "Crosstalk NS port must be 1863")
        XCTAssertEqual(config.switchboardPort, 1864, "Crosstalk Switchboard port must be 1864")
        XCTAssertTrue(config.configServer.contains("conf.msgrsvcs.ctsrv.gay"), "Crosstalk config server must match")
        XCTAssertTrue(config.authServer.contains("ctas.login.ugnet.gay"), "Crosstalk RST auth server must match")
    }

    // MARK: - Escargot Preset Tests

    func test_escargotPreset_endpoints() {
        let config = ServerConfig.escargot
        XCTAssertEqual(config.mainServer, "ds.escargot.nina.chat", "Escargot NS host must match specification")
        XCTAssertEqual(config.mainPort, 1863, "Escargot NS port must be 1863")
        XCTAssertEqual(config.switchboardPort, 1863, "Escargot Switchboard port must be 1863")
        XCTAssertTrue(config.configServer.contains("escargot"), "Escargot config server must contain escargot")
        XCTAssertEqual(config.authServer, "https://nexus.escargot.chat/RST.srf", "Escargot RST auth URL must match")
        XCTAssertEqual(config.addressBookServer, "https://contacts.escargot.chat", "Escargot ABCH URL must match")
        XCTAssertEqual(config.storageServer, "https://storage.escargot.chat", "Escargot storage URL must match")
    }

    // MARK: - Custom ServerConfig Roundtrip Tests

    func test_customServerConfig_roundtrip() throws {
        let custom = ServerConfig(
            mainServer: "custom.msnp18.network",
            mainPort: 18630,
            switchboardPort: 18640,
            configServer: "cfg.msnp18.network",
            authServer: "https://auth.msnp18.network/RST.srf",
            addressBookServer: "https://ab.msnp18.network/abservice",
            storageServer: "https://storage.msnp18.network/storage"
        )

        XCTAssertEqual(custom.mainServer, "custom.msnp18.network")
        XCTAssertEqual(custom.mainPort, 18630)
        XCTAssertEqual(custom.switchboardPort, 18640)
        XCTAssertEqual(custom.configServer, "cfg.msnp18.network")
        XCTAssertEqual(custom.authServer, "https://auth.msnp18.network/RST.srf")
        XCTAssertEqual(custom.addressBookServer, "https://ab.msnp18.network/abservice")
        XCTAssertEqual(custom.storageServer, "https://storage.msnp18.network/storage")

        // JSON Codable roundtrip
        let encoder = JSONEncoder()
        let data = try encoder.encode(custom)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ServerConfig.self, from: data)

        XCTAssertEqual(custom, decoded, "Decoded ServerConfig must match original instance")
        XCTAssertEqual(decoded.mainServer, "custom.msnp18.network")
        XCTAssertEqual(decoded.mainPort, 18630)
        XCTAssertEqual(decoded.switchboardPort, 18640)
    }

    // MARK: - Storage Key Hash Isolation Tests

    func test_storageKeyIsolation_hashesMatchEmailAndEndpoint() {
        let email = "user@crosstalk.im"
        let accountCrosstalk = UserAccount(email: email, serverConfig: .crosstalk, useMockServer: false)
        let accountEscargot = UserAccount(email: email, serverConfig: .escargot, useMockServer: false)
        let accountMock = UserAccount(email: email, serverConfig: .mock, useMockServer: true)

        // Storage keys must be 64-character hex strings (SHA-256)
        XCTAssertEqual(accountCrosstalk.storageKey.count, 64, "Storage key must be SHA-256 hex string")
        XCTAssertEqual(accountEscargot.storageKey.count, 64, "Storage key must be SHA-256 hex string")
        XCTAssertEqual(accountMock.storageKey.count, 64, "Storage key must be SHA-256 hex string")

        // Endpoints isolation: same email must yield distinct keys across servers
        XCTAssertNotEqual(accountCrosstalk.storageKey, accountEscargot.storageKey, "Crosstalk and Escargot keys must differ")
        XCTAssertNotEqual(accountCrosstalk.storageKey, accountMock.storageKey, "Crosstalk and Mock keys must differ")
        XCTAssertNotEqual(accountEscargot.storageKey, accountMock.storageKey, "Escargot and Mock keys must differ")

        // Email normalization: casing and whitespace must normalize to identical storage key
        let accountUntrimmed = UserAccount(email: "  USER@crosstalk.im  ", serverConfig: .crosstalk, useMockServer: false)
        XCTAssertEqual(accountUntrimmed.email, "user@crosstalk.im", "UserAccount must normalize email")
        XCTAssertEqual(accountUntrimmed.storageKey, accountCrosstalk.storageKey, "Normalized email must produce identical storage key")

        // Different emails on same server must produce distinct storage keys
        let peerAccount = UserAccount(email: "peer@crosstalk.im", serverConfig: .crosstalk, useMockServer: false)
        XCTAssertNotEqual(accountCrosstalk.storageKey, peerAccount.storageKey, "Different emails must produce distinct storage keys")
    }
}
