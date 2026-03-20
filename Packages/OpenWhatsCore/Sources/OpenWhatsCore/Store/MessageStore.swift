import Foundation

/// In-memory message store backed by UserDefaults JSON.
/// Injected into MessagePipeline via `setupMessagePipeline()`.
///
/// Phase 11: replace with SQLCipher for encrypted, paginated storage.
actor MessageStore: MessageStoreProtocol {

    static let shared = MessageStore()

    // conversationID → messages sorted by timestamp
    private var store: [String: [Message]] = [:]

    // messageID → attachment key material (not persisted — re-fetched from server if needed)
    private var attachmentKeys: [String: StoredAttachment] = [:]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaultsKey = "ow.message_store.v1"

    private init() {
        loadFromDefaults()
    }

    // MARK: - MessageStoreProtocol

    func upsert(_ message: Message) {
        var bucket = store[message.conversationID] ?? []
        if let idx = bucket.firstIndex(where: { $0.id == message.id }) {
            bucket[idx] = message
        } else {
            bucket.append(message)
        }
        bucket.sort { $0.timestamp < $1.timestamp }
        store[message.conversationID] = bucket
        saveToDefaults()
    }

    func updateStatus(_ status: MessageStatus, forEnvelopeID id: String) {
        for key in store.keys {
            guard let idx = store[key]?.firstIndex(where: { $0.id == id }) else { continue }
            store[key]![idx].status = status
            saveToDefaults()
            return
        }
    }

    func messages(for conversationID: String) -> [Message] {
        store[conversationID] ?? []
    }

    func storeAttachmentKey(messageID: String, objectKey: String, attachmentKey: AttachmentKey) {
        attachmentKeys[messageID] = StoredAttachment(objectKey: objectKey, attachmentKey: attachmentKey)
    }

    // MARK: - Additional helpers

    /// All conversations sorted by most recent message.
    func allConversationIDs() -> [String] {
        store.keys.sorted { lhs, rhs in
            let l = store[lhs]?.last?.timestamp ?? .distantPast
            let r = store[rhs]?.last?.timestamp ?? .distantPast
            return l > r
        }
    }

    // MARK: - Persistence

    private func saveToDefaults() {
        guard let data = try? encoder.encode(store) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadFromDefaults() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? decoder.decode([String: [Message]].self, from: data)
        else { return }
        store = decoded
    }
}

// MARK: - Internal helper types

private struct StoredAttachment {
    let objectKey: String
    let attachmentKey: AttachmentKey
}
