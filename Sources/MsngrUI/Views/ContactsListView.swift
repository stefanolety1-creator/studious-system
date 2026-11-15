import SwiftUI
import MsngrCore

/// Windows Live Messenger 2009 Main Contacts List Screen with Sky Header, Sunburst Glow, Profile Card, Search Toolbar, and Collapsible Accordions.
public struct ContactsListView: View {
    @ObservedObject public var session: SessionViewModel

    @State private var isOnlineExpanded: Bool = true
    @State private var isOfflineExpanded: Bool = true
    @State private var isSettingsPresented: Bool = false
    @State private var isAddContactPresented: Bool = false
    @State private var newContactEmail: String = ""
    @State private var newContactName: String = ""
    @State private var isEditingPSM: Bool = false
    @State private var psmDraft: String = ""

    public init(session: SessionViewModel) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            // WLM 2009 Sky Top Header with Overhead Sunburst
            ZStack(alignment: .topLeading) {
                session.activeScene.headerGradient
                    .frame(height: 142)

                GeometryReader { geo in
                    RadialGradient(
                        colors: [Color.white.opacity(0.40), Color.clear],
                        center: UnitPoint(x: 0.45, y: 0.0),
                        startRadius: 2,
                        endRadius: geo.size.width * 0.80
                    )
                }
                .frame(height: 142)

                VStack(alignment: .leading, spacing: 10) {
                    // User Profile Row
                    HStack(spacing: 12) {
                        AeroAvatarFrameView(
                            displayName: session.currentAccount.displayName,
                            status: session.currentAccount.presence,
                            size: 56
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(MessengerPlusParser.parseToAttributedString(
                                    session.currentAccount.displayName,
                                    adaptiveColor: session.activeScene.isDarkText ? .wlmTextDark : .white,
                                    baseFontSize: 16
                                ))
                                .font(.system(size: 16, weight: .bold, design: .rounded))

                                Menu {
                                    ForEach([PresenceStatus.online, .busy, .beRightBack, .away, .onThePhone, .outToLunch, .hidden]) { st in
                                        Button {
                                            session.updatePresence(st)
                                        } label: {
                                            Text(st.label)
                                        }
                                    }
                                    Divider()
                                    Button("Sign Out", role: .destructive) {
                                        session.signOut()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("(\(session.currentAccount.presence.label))")
                                            .font(.caption.bold())
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextDark : Color.white.opacity(0.92))
                                }
                            }

                            // Personal Status Message / Now Playing
                            if isEditingPSM {
                                HStack(spacing: 6) {
                                    TextField("Share a quick message...", text: $psmDraft)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .onSubmit {
                                            session.updatePersonalMessage(psmDraft)
                                            isEditingPSM = false
                                        }
                                    Button("Save") {
                                        session.updatePersonalMessage(psmDraft)
                                        isEditingPSM = false
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                }
                            } else {
                                Button {
                                    psmDraft = session.currentAccount.personalMessage
                                    isEditingPSM = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "music.note")
                                            .font(.caption2)
                                        Text(session.currentAccount.personalMessage.isEmpty ? "Share a quick message..." : session.currentAccount.personalMessage)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextMuted : Color.white.opacity(0.88))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        // Scene & Settings Toolbar Icons
                        HStack(spacing: 10) {
                            Menu {
                                ForEach(WlmScene.allCases) { scene in
                                    Button(scene.rawValue) {
                                        session.activeScene = scene
                                    }
                                }
                            } label: {
                                Image(systemName: "paintpalette.fill")
                                    .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextDark : Color.white)
                            }

                            Button {
                                isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextDark : Color.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Search Bar & Add Contact Row
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(Color.wlmTextMuted)
                            TextField("Search contacts or the web...", text: $session.searchQuery)
                                .font(.system(size: 13, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )

                        Button {
                            isAddContactPresented = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.subheadline.bold())
                                .foregroundStyle(session.activeScene.isDarkText ? Color.wlmTextDark : Color.white)
                                .padding(7)
                                .background(Circle().fill(Color.white.opacity(0.22)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: 142)

            // Accordion Contact Categories ("Online (N)" & "Offline (M)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // Online Section
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isOnlineExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isOnlineExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmPrimary)
                            Text("Online (\(session.onlineContacts.count))")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.wlmOnPrimaryContainer)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.wlmSurfaceVariant)
                    }
                    .buttonStyle(.plain)

                    if isOnlineExpanded {
                        ForEach(session.onlineContacts) { contact in
                            Button {
                                session.selectedContactId = contact.id
                            } label: {
                                ContactRowView(
                                    contact: contact,
                                    isSelected: session.selectedContactId == contact.id,
                                    enableBBCode: session.enableMessengerPlusFormatting
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Offline Section
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isOfflineExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isOfflineExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Color.wlmTextMuted)
                            Text("Offline (\(session.offlineContacts.count))")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.wlmTextMuted)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.wlmSurfaceVariant)
                    }
                    .buttonStyle(.plain)

                    if isOfflineExpanded {
                        ForEach(session.offlineContacts) { contact in
                            Button {
                                session.selectedContactId = contact.id
                            } label: {
                                ContactRowView(
                                    contact: contact,
                                    isSelected: session.selectedContactId == contact.id,
                                    enableBBCode: session.enableMessengerPlusFormatting
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color.white)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(session: session)
        }
        .alert("Add a Contact", isPresented: $isAddContactPresented) {
            TextField("Email (e.g. friend@escargot.chat)", text: $newContactEmail)
            TextField("Nickname (optional)", text: $newContactName)
            Button("Cancel", role: .cancel) {
                newContactEmail = ""
                newContactName = ""
            }
            Button("Add") {
                session.addContact(email: newContactEmail, displayName: newContactName)
                newContactEmail = ""
                newContactName = ""
            }
        }
    }
}
