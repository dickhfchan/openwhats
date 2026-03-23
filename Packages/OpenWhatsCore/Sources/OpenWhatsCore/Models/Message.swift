import Foundation
import Security

// MARK: - Message

public enum MessageType: String, Codable {
    case text
    case image
    case voice
    case deliveryReceipt = "delivery_receipt"
    case readReceipt     = "read_receipt"
}

public enum MessageStatus: String, Codable {
    case sending    // locally enqueued, not yet acked by server
    case sent       // server acked the envelope
    case delivered  // recipient device received it
    case read       // recipient opened it
    case failed
}

public struct Message: Identifiable, Codable, Equatable, Hashable {
    public let id: String               // server-assigned envelope UUID
    public let conversationID: String   // == peerUserID for 1:1 chats
    public let senderID: String
    public let senderDeviceID: String
    public let type: MessageType
    /// Decrypted text body (nil for media messages until downloaded)
    public var body: String?
    /// Local file URL for downloaded media
    public var localPath: String?
    public var timestamp: Date
    public var status: MessageStatus

    public var isMine: Bool {
        senderID == AccountManager.shared.userID || senderID == "me"
    }

    public init(id: String, conversationID: String, senderID: String, senderDeviceID: String,
                type: MessageType, body: String?, localPath: String?, timestamp: Date, status: MessageStatus) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.senderDeviceID = senderDeviceID
        self.type = type
        self.body = body
        self.localPath = localPath
        self.timestamp = timestamp
        self.status = status
    }
}

// MARK: - Conversation

public struct Conversation: Identifiable, Codable, Hashable {
    public let id: String          // peerUserID
    public var peerUserID: String
    public var peerDisplayName: String
    public var peerAvatarURL: String?
    public var lastMessage: Message?
    public var unreadCount: Int
    public var updatedAt: Date

    public init(id: String, peerUserID: String, peerDisplayName: String, peerAvatarURL: String?,
                lastMessage: Message?, unreadCount: Int, updatedAt: Date) {
        self.id = id
        self.peerUserID = peerUserID
        self.peerDisplayName = peerDisplayName
        self.peerAvatarURL = peerAvatarURL
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }
}

// MARK: - Wire types (server ↔ client)

/// Raw envelope received from server WebSocket or REST — still encrypted.
public struct IncomingEnvelope: Codable {
    public let id: String
    public let senderUserID: String
    public let senderDeviceID: String
    public let recipientDeviceID: String
    public let payload: Data
    public let timestamp: Int64      // milliseconds since epoch

    public var date: Date { Date(timeIntervalSince1970: Double(timestamp) / 1000) }

    public enum CodingKeys: String, CodingKey {
        case id
        case senderUserID      = "sender_user_id"
        case senderDeviceID    = "sender_device_id"
        case recipientDeviceID = "recipient_device_id"
        case payload
        case timestamp
    }
}

/// Decrypted plaintext message payload (encoded inside the Signal ciphertext).
public struct MessagePayload: Codable {
    public let id: String
    public let type: MessageType
    /// Non-nil for text messages.
    public let body: String?
    /// The peer user ID this conversation belongs to.
    /// Required in sender-copy envelopes so the receiving own-device knows which conversation to store the message in.
    public let conversationUserID: String?
    /// Non-nil for image/voice messages — contains the S3 object key.
    public let mediaObjectKey: String?
    /// Non-nil for image/voice messages — the per-attachment encryption key material.
    public let mediaAttachmentKey: AttachmentKey?
    public let mediaMimeType: String?
    public let mediaSize: Int?

    public enum CodingKeys: String, CodingKey {
        case id, type, body
        case conversationUserID  = "conversation_user_id"
        case mediaObjectKey      = "media_object_key"
        case mediaAttachmentKey  = "media_attachment_key"
        case mediaMimeType       = "media_mime_type"
        case mediaSize           = "media_size"
    }

    public init(id: String, type: MessageType, body: String?,
                conversationUserID: String?,
                mediaObjectKey: String?,
                mediaAttachmentKey: AttachmentKey?, mediaMimeType: String?, mediaSize: Int?) {
        self.id = id
        self.type = type
        self.body = body
        self.conversationUserID = conversationUserID
        self.mediaObjectKey = mediaObjectKey
        self.mediaAttachmentKey = mediaAttachmentKey
        self.mediaMimeType = mediaMimeType
        self.mediaSize = mediaSize
    }
}

/// WebSocket frame wrapper.
public struct WSFrame<T: Codable>: Codable {
    public let type: String
    public let data: T?
}

public struct WSFrameRaw: Codable {
    public let type: String
    public let data: AnyCodable?
}

// MARK: - AccountManager

/// Stores authentication credentials in the system Keychain.
/// Keys survive app reinstalls on macOS; on iOS they are cleared on device wipe.
public final class AccountManager {

    public static let shared = AccountManager()
    private init() {}

    private let service = "com.openwhats.account"

    public var userID: String {
        get { keychainLoad("user_id") ?? "" }
        set { keychainSave("user_id", value: newValue) }
    }

    public var deviceID: String {
        get { keychainLoad("device_id") ?? "" }
        set { keychainSave("device_id", value: newValue) }
    }

    public var jwtToken: String {
        get { keychainLoad("jwt_token") ?? "" }
        set { keychainSave("jwt_token", value: newValue) }
    }

    // MARK: - Keychain helpers

    private func keychainLoad(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainSave(_ key: String, value: String) {
        keychainDelete(key)
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    key,
            kSecValueData as String:      Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    @discardableResult
    private func keychainDelete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - AnyCodable helper

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v; return }
        if let v = try? container.decode(Int.self)    { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self) { value = v; return }
        value = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        default:              try container.encodeNil()
        }
    }
}
