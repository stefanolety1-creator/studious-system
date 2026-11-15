import SwiftUI
import MsngrCore

/// Individual contact row in the WLM 2009 contact list with 13x13pt glossy status icon, BBCode display name, PSM, and unread badge.
public struct ContactRowView: View {
    public let contact: Contact
    public let isSelected: Bool
    public let enableBBCode: Bool

    public init(contact: Contact, isSelected: Bool = false, enableBBCode: Bool = true) {
        self.contact = contact
        self.isSelected = isSelected
        self.enableBBCode = enableBBCode
    }

    public var body: some View {
        HStack(spacing: 10) {
            MsnPresenceIcon(status: contact.presence, size: 13)

            AeroAvatarFrameView(
                displayName: contact.displayName,
                status: contact.presence,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if enableBBCode {
                        Text(MessengerPlusParser.parseToAttributedString(contact.displayName, adaptiveColor: .wlmTextDark, baseFontSize: 14))
                            .lineLimit(1)
                    } else {
                        Text(contact.cleanDisplayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.wlmTextDark)
                            .lineLimit(1)
                    }

                    if !contact.statusMessage.isEmpty {
                        Text("— \(contact.cleanStatusMessage)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.wlmTextMuted)
                            .lineLimit(1)
                    }
                }

                Text(contact.presence.label)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.wlmTextMuted.opacity(0.85))
            }

            Spacer()

            if contact.unreadCount > 0 {
                Text("\(contact.unreadCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.wlmSecondary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient.wlmContactSelection)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color(hex: 0x88C9EE), lineWidth: 1)
                        )
                } else {
                    Color.clear
                }
            }
        )
    }
}
