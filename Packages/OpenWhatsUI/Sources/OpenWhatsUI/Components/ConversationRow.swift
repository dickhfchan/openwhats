import SwiftUI
import OpenWhatsCore

/// A single row in the chats list — avatar, name, last message, timestamp, unread badge.
public struct ConversationRow: View {
    let conversation: Conversation
    var compact: Bool = false   // macOS uses a compact variant

    public init(conversation: Conversation, compact: Bool = false) {
        self.conversation = conversation
        self.compact = compact
    }

    private var avatarSize: CGFloat { compact ? 32 : 40 }

    public var body: some View {
        HStack(spacing: 10) {
            AvatarView(
                url: conversation.peerAvatarURL.flatMap { URL(string: $0) },
                name: conversation.peerDisplayName,
                size: avatarSize
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.peerDisplayName)
                        .font(.system(size: compact ? 13 : 16, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.updatedAt.relativeString)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            conversation.unreadCount > 0 ? Color.owGreen : .secondary
                        )
                }

                HStack {
                    Text(conversation.lastMessage?.body ?? "")
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text("\(min(conversation.unreadCount, 99))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.owGreen)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
    }
}

extension Color {
    static let owGreen = Color(hex: "#25D366")
}

extension Date {
    /// "3:45 PM" for today, "Mon" for this week, "12/31" for this year, "12/31/23" otherwise.
    var relativeString: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: self)
        } else if cal.isDateInYesterday(self) {
            return "Yesterday"
        } else if let days = cal.dateComponents([.day], from: self, to: Date()).day, days < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: self)
        } else {
            let f = DateFormatter()
            f.dateFormat = "M/d/yy"
            return f.string(from: self)
        }
    }
}
