import XCTest
@testable import MsngrCore
@testable import MsngrUI

@MainActor
final class SessionViewModelTests: XCTestCase {

    // MARK: - Search Filtering Tests

    func test_sessionViewModel_searchFilteringByNickAndEmail() {
        let session = SessionViewModel(account: UserAccount(email: "owner@crosstalk.im"))

        let selin = Contact(
            id: "selin@crosstalk.im",
            nickname: "[c=4]Selin[/c] ✨",
            email: "selin@crosstalk.im",
            presence: .online,
            statusMessage: "Developing in SwiftUI on macOS & iOS"
        )
        let alex = Contact(
            id: "alex@escargot.chat",
            nickname: "Alex (Gaming)",
            email: "alex@escargot.chat",
            presence: .busy,
            statusMessage: "Playing Halo 3 — Do Not Disturb"
        )
        let giulia = Contact(
            id: "giulia@crosstalk.im",
            nickname: "Giulia 🌸",
            email: "giulia@crosstalk.im",
            presence: .away,
            statusMessage: "Out for espresso ☕"
        )
        let marco = Contact(
            id: "marco@escargot.chat",
            nickname: "Marco",
            email: "marco@escargot.chat",
            presence: .offline,
            statusMessage: "See you tomorrow!"
        )

        session.contacts = [selin, alex, giulia, marco]

        // Empty search returns all contacts
        session.searchQuery = ""
        XCTAssertEqual(session.filteredContacts.count, 4)

        // Filter by nickname (clean, BBCode stripped)
        session.searchQuery = "Selin"
        XCTAssertEqual(session.filteredContacts.count, 1)
        XCTAssertEqual(session.filteredContacts.first?.email, "selin@crosstalk.im")

        // Filter by email domain
        session.searchQuery = "crosstalk.im"
        XCTAssertEqual(session.filteredContacts.count, 2)
        let crosstalkEmails = Set(session.filteredContacts.map { $0.email })
        XCTAssertEqual(crosstalkEmails, ["selin@crosstalk.im", "giulia@crosstalk.im"])

        // Filter by status message content
        session.searchQuery = "espresso"
        XCTAssertEqual(session.filteredContacts.count, 1)
        XCTAssertEqual(session.filteredContacts.first?.email, "giulia@crosstalk.im")

        // Non-matching query returns empty
        session.searchQuery = "NonExistentContact"
        XCTAssertEqual(session.filteredContacts.count, 0)
    }

    // MARK: - Online and Offline Sorting Tests

    func test_sessionViewModel_onlineAndOfflineSorting() {
        let session = SessionViewModel(account: UserAccount(email: "owner@crosstalk.im"))

        let busyBob = Contact(
            id: "bob@crosstalk.im",
            nickname: "Bob",
            email: "bob@crosstalk.im",
            presence: .busy // priority 1
        )
        let onlineAlice = Contact(
            id: "alice@crosstalk.im",
            nickname: "Alice",
            email: "alice@crosstalk.im",
            presence: .online // priority 0
        )
        let awayCharlie = Contact(
            id: "charlie@crosstalk.im",
            nickname: "Charlie",
            email: "charlie@crosstalk.im",
            presence: .away // priority 2
        )
        let offlineDave = Contact(
            id: "dave@escargot.chat",
            nickname: "Dave",
            email: "dave@escargot.chat",
            presence: .offline
        )
        let offlineZoe = Contact(
            id: "zoe@escargot.chat",
            nickname: "Zoe",
            email: "zoe@escargot.chat",
            presence: .offline
        )

        session.contacts = [awayCharlie, offlineZoe, busyBob, offlineDave, onlineAlice]

        // Online contacts must be sorted by priority (Online < Busy < Away), then alphabetical
        let onlineList = session.onlineContacts
        XCTAssertEqual(onlineList.count, 3)
        XCTAssertEqual(onlineList[0].email, "alice@crosstalk.im") // online
        XCTAssertEqual(onlineList[1].email, "bob@crosstalk.im")   // busy
        XCTAssertEqual(onlineList[2].email, "charlie@crosstalk.im") // away

        // Offline contacts must be sorted alphabetically by clean display name
        let offlineList = session.offlineContacts
        XCTAssertEqual(offlineList.count, 2)
        XCTAssertEqual(offlineList[0].email, "dave@escargot.chat")
        XCTAssertEqual(offlineList[1].email, "zoe@escargot.chat")
    }

    // MARK: - Preset Switching Tests

    func test_sessionViewModel_presetSwitching() {
        let session = SessionViewModel(account: UserAccount(
            email: "stefano@crosstalk.im",
            serverConfig: .crosstalk
        ))

        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ms.msgrsvcs.ctsrv.gay")
        let crosstalkKey = session.currentAccount.storageKey

        // Switch to Escargot
        session.currentAccount.serverConfig = .escargot
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "ds.escargot.nina.chat")
        let escargotKey = session.currentAccount.storageKey

        XCTAssertNotEqual(crosstalkKey, escargotKey, "Switching presets must change storage key")

        // Switch to Custom
        let customConfig = ServerConfig(
            mainServer: "private.wlm.im",
            mainPort: 1863,
            switchboardPort: 1864,
            configServer: "conf.private.wlm.im",
            authServer: "https://auth.private.wlm.im/RST.srf",
            addressBookServer: "https://ab.private.wlm.im",
            storageServer: "https://store.private.wlm.im"
        )
        session.currentAccount.serverConfig = customConfig
        XCTAssertEqual(session.currentAccount.serverConfig.mainServer, "private.wlm.im")
        XCTAssertNotEqual(session.currentAccount.storageKey, crosstalkKey)
        XCTAssertNotEqual(session.currentAccount.storageKey, escargotKey)
    }
}
