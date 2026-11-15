import XCTest
@testable import MsngrCore

final class DataModelTests: XCTestCase {

    // MARK: - PresenceStatus Tests

    func testPresenceStatusWireCodeMapping() {
        XCTAssertEqual(PresenceStatus.from(wireCode: "NLN"), .online)
        XCTAssertEqual(PresenceStatus.from(wireCode: "BSY"), .busy)
        XCTAssertEqual(PresenceStatus.from(wireCode: "AWY"), .away)
        XCTAssertEqual(PresenceStatus.from(wireCode: "HDN"), .hidden)
        XCTAssertEqual(PresenceStatus.from(wireCode: "FLN"), .offline)
    }

    func testPresenceStatusAliases() {
        XCTAssertEqual(PresenceStatus.from(wireCode: "IDL"), .idle)
        XCTAssertEqual(PresenceStatus.from(wireCode: "BRB"), .beRightBack)
        XCTAssertEqual(PresenceStatus.from(wireCode: "PHN"), .onThePhone)
        XCTAssertEqual(PresenceStatus.from(wireCode: "LUN"), .outToLunch)
        XCTAssertEqual(PresenceStatus.from(wireCode: "Available"), .online)
        XCTAssertEqual(PresenceStatus.from(wireCode: "offline"), .offline)
    }

    func testPresencePriorityAndIsOnline() {
        XCTAssertTrue(PresenceStatus.online.isOnline)
        XCTAssertTrue(PresenceStatus.busy.isOnline)
        XCTAssertTrue(PresenceStatus.away.isOnline)
        XCTAssertFalse(PresenceStatus.offline.isOnline)
        XCTAssertFalse(PresenceStatus.hidden.isOnline)

        XCTAssertLessThan(PresenceStatus.online.priority, PresenceStatus.busy.priority)
        XCTAssertLessThan(PresenceStatus.busy.priority, PresenceStatus.away.priority)
        XCTAssertLessThan(PresenceStatus.away.priority, PresenceStatus.offline.priority)
    }

    func testPresenceOutboundWireCodes() {
        XCTAssertEqual(PresenceStatus.online.outboundWireCode, "NLN")
        XCTAssertEqual(PresenceStatus.busy.outboundWireCode, "BSY")
        XCTAssertEqual(PresenceStatus.away.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.idle.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.beRightBack.outboundWireCode, "AWY")
        XCTAssertEqual(PresenceStatus.hidden.outboundWireCode, "HDN")
        XCTAssertEqual(PresenceStatus.offline.outboundWireCode, "HDN")
    }

    // MARK: - Contact Tests

    func testContactDisplayNameFallback() {
        let contactWithNick = Contact(id: "alice@example.com", nickname: "Alice Wonderland", email: "alice@example.com")
        XCTAssertEqual(contactWithNick.displayName, "Alice Wonderland")

        let contactWithoutNick = Contact(id: "bob@example.com", nickname: nil, email: "bob@example.com")
        XCTAssertEqual(contactWithoutNick.displayName, "bob@example.com")

        let contactWithEmptyNick = Contact(id: "carol@example.com", nickname: "   ", email: "carol@example.com")
        XCTAssertEqual(contactWithEmptyNick.displayName, "carol@example.com")
    }

    func testContactCleanDisplayName() {
        let contact = Contact(id: "alice@example.com", nickname: "[c=4][b]Alice[/b][/c]", email: "alice@example.com")
        XCTAssertEqual(contact.cleanDisplayName, "Alice")
    }

    func testContactUnreadStatus() {
        var contact = Contact(id: "alice@example.com", email: "alice@example.com", unreadCount: 0, isMarkedUnread: false)
        XCTAssertFalse(contact.isUnread)

        contact.unreadCount = 2
        XCTAssertTrue(contact.isUnread)

        contact.unreadCount = 0
        contact.isMarkedUnread = true
        XCTAssertTrue(contact.isUnread)
    }

    // MARK: - ChatMessage Tests

    func testChatMessageNudgeBuilder() {
        let nudgeMe = ChatMessage.nudge(contactId: "alice@example.com", author: .me)
        XCTAssertTrue(nudgeMe.isNudge)
        XCTAssertEqual(nudgeMe.author, .me)
        XCTAssertEqual(nudgeMe.text, "You have just sent a Nudge.")

        let nudgeContact = ChatMessage.nudge(contactId: "alice@example.com", author: .contact)
        XCTAssertTrue(nudgeContact.isNudge)
        XCTAssertEqual(nudgeContact.author, .contact)
        XCTAssertEqual(nudgeContact.text, "You have just received a Nudge!")
    }

    func testChatMessageDeliveryTransitions() {
        var message = ChatMessage(contactId: "bob@example.com", author: .me, text: "Hello", deliveryStatus: .sending)
        XCTAssertTrue(message.isSending)

        message.deliveryStatus = .sent
        XCTAssertFalse(message.isSending)

        message.deliveryStatus = .failed
        message.deliveryError = "Connection timeout"
        XCTAssertEqual(message.deliveryError, "Connection timeout")
    }

    // MARK: - Conversation Tests

    func testConversationMessageAppendingAndReadState() {
        var convo = Conversation(id: "alice@example.com", title: "Alice")
        XCTAssertEqual(convo.messages.count, 0)
        XCTAssertEqual(convo.unreadCount, 0)

        let msgIn = ChatMessage(contactId: "alice@example.com", author: .contact, text: "Hey there")
        convo.appendMessage(msgIn)
        XCTAssertEqual(convo.messages.count, 1)
        XCTAssertEqual(convo.unreadCount, 1)

        let msgOut = ChatMessage(contactId: "alice@example.com", author: .me, text: "Hi!")
        convo.appendMessage(msgOut)
        XCTAssertEqual(convo.messages.count, 2)
        XCTAssertEqual(convo.unreadCount, 1)

        convo.markAsRead()
        XCTAssertEqual(convo.unreadCount, 0)
    }

    func testConversationTypingState() {
        var convo = Conversation(id: "bob@example.com", title: "Bob")
        XCTAssertFalse(convo.isPeerTyping)

        convo.setPeerTyping(true, peerName: "Bob")
        XCTAssertTrue(convo.isPeerTyping)
        XCTAssertEqual(convo.typingPeerName, "Bob")

        convo.setPeerTyping(false)
        XCTAssertFalse(convo.isPeerTyping)
        XCTAssertNil(convo.typingPeerName)
    }

    // MARK: - UserAccount Tests

    func testUserAccountStorageKeyIsolation() {
        let accountLive = UserAccount(email: "alice@escargot.chat", useMockServer: false)
        let accountMock = UserAccount(email: "alice@escargot.chat", useMockServer: true)

        XCTAssertNotEqual(accountLive.storageKey, accountMock.storageKey)
        XCTAssertFalse(accountLive.storageKey.isEmpty)
        XCTAssertFalse(accountMock.storageKey.isEmpty)
    }

    func testCodableRoundtrip() throws {
        let account = UserAccount(email: "test@example.com", displayName: "Test User", presence: .busy)
        let encoder = JSONEncoder()
        let data = try encoder.encode(account)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UserAccount.self, from: data)

        XCTAssertEqual(account.email, decoded.email)
        XCTAssertEqual(account.displayName, decoded.displayName)
        XCTAssertEqual(account.presence, decoded.presence)
        XCTAssertEqual(account.storageKey, decoded.storageKey)
    }
}
