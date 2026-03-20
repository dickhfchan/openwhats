import Foundation
import OpenWhatsCore

// MARK: - Shared preview / stub data (available on all platforms)

extension Conversation {
    public static let previews: [Conversation] = [
        Conversation(
            id: "user-alice",
            peerUserID: "user-alice",
            peerDisplayName: "Alice Johnson",
            peerAvatarURL: nil,
            lastMessage: Message(
                id: "m1", conversationID: "user-alice",
                senderID: "user-alice", senderDeviceID: "dev1",
                type: .text, body: "Hey, are you free later?",
                localPath: nil, timestamp: Date().addingTimeInterval(-300),
                status: .read
            ),
            unreadCount: 0,
            updatedAt: Date().addingTimeInterval(-300)
        ),
        Conversation(
            id: "user-bob",
            peerUserID: "user-bob",
            peerDisplayName: "Bob Smith",
            peerAvatarURL: nil,
            lastMessage: Message(
                id: "m2", conversationID: "user-bob",
                senderID: "user-bob", senderDeviceID: "dev2",
                type: .image, body: "📷 Photo",
                localPath: nil, timestamp: Date().addingTimeInterval(-3600),
                status: .delivered
            ),
            unreadCount: 3,
            updatedAt: Date().addingTimeInterval(-3600)
        ),
        Conversation(
            id: "user-carol",
            peerUserID: "user-carol",
            peerDisplayName: "Carol Williams",
            peerAvatarURL: nil,
            lastMessage: Message(
                id: "m3", conversationID: "user-carol",
                senderID: "me", senderDeviceID: "mydev",
                type: .text, body: "Sounds good!",
                localPath: nil, timestamp: Date().addingTimeInterval(-86400),
                status: .sent
            ),
            unreadCount: 0,
            updatedAt: Date().addingTimeInterval(-86400)
        ),
    ]
}

extension Message {
    public static func previews(for conversationID: String) -> [Message] {
        [
            Message(id: "1", conversationID: conversationID, senderID: conversationID,
                    senderDeviceID: "d", type: .text, body: "Hey! How are you doing?",
                    localPath: nil, timestamp: Date().addingTimeInterval(-7200), status: .read),
            Message(id: "2", conversationID: conversationID, senderID: "me",
                    senderDeviceID: "mydev", type: .text, body: "Pretty good! Working on something cool.",
                    localPath: nil, timestamp: Date().addingTimeInterval(-7100), status: .read),
            Message(id: "3", conversationID: conversationID, senderID: conversationID,
                    senderDeviceID: "d", type: .text, body: "Oh yeah? Tell me more!",
                    localPath: nil, timestamp: Date().addingTimeInterval(-7000), status: .read),
            Message(id: "4", conversationID: conversationID, senderID: "me",
                    senderDeviceID: "mydev", type: .image, body: "📷 Photo",
                    localPath: nil, timestamp: Date().addingTimeInterval(-100), status: .delivered),
            Message(id: "5", conversationID: conversationID, senderID: "me",
                    senderDeviceID: "mydev", type: .text, body: "That's the project 👆",
                    localPath: nil, timestamp: Date().addingTimeInterval(-90), status: .sent),
        ]
    }
}
