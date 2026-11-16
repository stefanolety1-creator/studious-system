import SwiftUI
import MsngrCore
import MsngrUI

/// Root container switching between WLM 2009 LoginView and the split Contacts + Chat workspace.
public struct RootContentView: View {
    @StateObject private var session = SessionViewModel()
    @State private var chatViewModels: [String: ChatViewModel] = [:]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init() {}

    public var body: some View {
        Group {
            if session.networkState == .connected {
                if horizontalSizeClass == .compact {
                    NavigationStack {
                        ContactsListView(session: session)
                            .navigationDestination(isPresented: Binding(
                                get: { session.selectedContactId != nil },
                                set: { if !$0 { session.selectedContactId = nil } }
                            )) {
                                if let selectedId = session.selectedContactId,
                                   let contact = session.contacts.first(where: { $0.id == selectedId }) {
                                    ChatView(
                                        session: session,
                                        viewModel: chatViewModel(for: contact)
                                    )
                                }
                            }
                    }
                } else {
                    NavigationSplitView {
                        ContactsListView(session: session)
                            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
                    } detail: {
                        if let selectedId = session.selectedContactId,
                           let contact = session.contacts.first(where: { $0.id == selectedId }) {
                            ChatView(
                                session: session,
                                viewModel: chatViewModel(for: contact)
                            )
                        } else {
                            VStack(spacing: 12) {
                                AeroAvatarFrameView(
                                    displayName: session.currentAccount.displayName,
                                    status: session.currentAccount.presence,
                                    size: 68,
                                    symbolName: "bubble.left.and.bubble.right.fill"
                                )
                                Text("Select a contact to start a conversation")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(Color.wlmOnPrimaryContainer)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(LinearGradient.wlmAtmosphereLight.ignoresSafeArea())
                        }
                    }
                }
            } else {
                LoginView(session: session)
            }
        }
    }

    private func chatViewModel(for contact: Contact) -> ChatViewModel {
        if let existing = chatViewModels[contact.id] {
            return existing
        }
        let initialMessages = session.conversations[contact.id]?.messages ?? []
        let vm = ChatViewModel(contact: contact, initialMessages: initialMessages)
        DispatchQueue.main.async {
            chatViewModels[contact.id] = vm
        }
        return vm
    }
}
