import Foundation
import CryptoKit

// MARK: - MessagePipeline

/// Orchestrates the full outgoing and incoming message flow:
/// Outgoing: plaintext → Signal encrypt → envelope → REST POST → local DB
/// Incoming: envelope → Signal decrypt → local DB → UI update
@MainActor
final class MessagePipeline {

    static let shared = MessagePipeline()
    private init() { setupWebSocket() }

    // Injected by the app on startup
    var messageStore: MessageStoreProtocol?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Send a text message

    /// Encrypt and send a text message to a peer. Stores locally with .sending status.
    func send(text: String, to peerUserID: String) async throws {
        try await sendMessage(
            payload: MessagePayload(
                id: UUID().uuidString,
                type: .text,
                body: text,
                conversationUserID: peerUserID,
                mediaObjectKey: nil,
                mediaAttachmentKey: nil,
                mediaMimeType: nil,
                mediaSize: nil
            ),
            displayBody: text,
            type: .text,
            to: peerUserID
        )
    }

    // MARK: - Send a media message

    /// Encrypt, upload, and send an image or voice message.
    func send(mediaData: Data, mimeType: String, type: MessageType, to peerUserID: String) async throws {
        let (objectKey, attachmentKey) = try await MediaUploader.shared.upload(
            data: mediaData,
            mimeType: mimeType
        )
        try await sendMessage(
            payload: MessagePayload(
                id: UUID().uuidString,
                type: type,
                body: nil,
                conversationUserID: peerUserID,
                mediaObjectKey: objectKey,
                mediaAttachmentKey: attachmentKey,
                mediaMimeType: mimeType,
                mediaSize: mediaData.count
            ),
            displayBody: type == .image ? "📷 Photo" : "🎤 Voice message",
            type: type,
            to: peerUserID
        )
    }

    // MARK: - Shared send logic

    private func sendMessage(
        payload: MessagePayload,
        displayBody: String,
        type: MessageType,
        to peerUserID: String
    ) async throws {
        let myID = AccountManager.shared.userID

        // 1. Fetch recipient's pre-key bundles (one per registered device)
        let bundleResp = try await APIClient.shared.fetchPreKeyBundles(for: peerUserID)
        guard !bundleResp.bundles.isEmpty else {
            throw SignalError.noSessionFound
        }

        // 2. Encode plaintext payload
        let plaintext = try encoder.encode(payload)

        // 3. Encrypt for each recipient device
        var envelopes: [SendEnvelopesRequest.Envelope] = []

        for serverBundle in bundleResp.bundles {
            let bundle = try serverBundle.toPreKeyBundle()
            let sessionKey = SessionKey(userID: peerUserID, deviceID: serverBundle.deviceId)

            let ciphertext: Data
            let header: MessageHeader

            if SessionStore.shared.load(for: sessionKey) != nil {
                (header, ciphertext) = try await SessionManager.shared.encrypt(
                    plaintext: plaintext, for: sessionKey
                )
            } else {
                let (_, ephemeralKeyData) = try await SessionManager.shared.establishSenderSession(bundle: bundle)
                (header, ciphertext) = try await SessionManager.shared.encrypt(
                    plaintext: plaintext, for: sessionKey
                )
                _ = ephemeralKeyData
            }

            let wirePayload = try buildWirePayload(header: header, ciphertext: ciphertext)
            envelopes.append(.init(
                recipientUserId: peerUserID,
                recipientDeviceId: serverBundle.deviceId,
                payload: wirePayload
            ))
        }

        // 3b. Also encrypt for own other devices (sender copies — so Mac sees what phone sent)
        let myDeviceID = AccountManager.shared.deviceID
        if let ownBundleResp = try? await APIClient.shared.fetchPreKeyBundles(for: myID) {
            for serverBundle in ownBundleResp.bundles where serverBundle.deviceId != myDeviceID {
                let bundle = try serverBundle.toPreKeyBundle()
                let sessionKey = SessionKey(userID: myID, deviceID: serverBundle.deviceId)
                let ciphertext: Data
                let header: MessageHeader
                if SessionStore.shared.load(for: sessionKey) != nil {
                    (header, ciphertext) = try await SessionManager.shared.encrypt(plaintext: plaintext, for: sessionKey)
                } else {
                    let (_, _) = try await SessionManager.shared.establishSenderSession(bundle: bundle)
                    (header, ciphertext) = try await SessionManager.shared.encrypt(plaintext: plaintext, for: sessionKey)
                }
                let wirePayload = try buildWirePayload(header: header, ciphertext: ciphertext)
                envelopes.append(.init(recipientUserId: myID,
                                       recipientDeviceId: serverBundle.deviceId,
                                       payload: wirePayload))
            }
        }

        // 4. Save locally as .sending
        let message = Message(
            id: payload.id,
            conversationID: peerUserID,
            senderID: myID,
            senderDeviceID: AccountManager.shared.deviceID,
            type: type,
            body: displayBody,
            localPath: nil,
            timestamp: Date(),
            status: .sending
        )
        await messageStore?.upsert(message)

        // 5. POST envelopes to server
        _ = try await APIClient.shared.sendEnvelopes(SendEnvelopesRequest(envelopes: envelopes))

        // 6. Update status to .sent
        let sent = Message(
            id: message.id,
            conversationID: message.conversationID,
            senderID: message.senderID,
            senderDeviceID: message.senderDeviceID,
            type: message.type,
            body: message.body,
            localPath: nil,
            timestamp: message.timestamp,
            status: .sent
        )
        await messageStore?.upsert(sent)
    }

    // MARK: - Receive an envelope

    /// Decrypt an incoming envelope and store it locally.
    func receive(envelope: IncomingEnvelope) async {
        do {
            let (header, ciphertext) = try parseWirePayload(envelope.payload)
            let sessionKey = SessionKey(userID: envelope.senderUserID,
                                        deviceID: envelope.senderDeviceID)

            // Resolve the expected identity key via TOFU:
            //   • First contact: load the key from the existing session and trust it.
            //   • Subsequent contacts: compare against the previously trusted key.
            //   • No session at all: drop the message (session must be established first).
            let expectedIdentityKey: Data
            if let trusted = IdentityKeyStore.shared.trustedKey(
                for: envelope.senderUserID,
                deviceID: envelope.senderDeviceID
            ) {
                expectedIdentityKey = trusted
            } else if let session = SessionStore.shared.load(for: sessionKey) {
                // TOFU — trust and persist the key already recorded in the session
                IdentityKeyStore.shared.setTrustedKey(
                    session.remoteIdentityKey,
                    for: envelope.senderUserID,
                    deviceID: envelope.senderDeviceID
                )
                expectedIdentityKey = session.remoteIdentityKey
            } else {
                print("[MessagePipeline] no session for (\(envelope.senderUserID), \(envelope.senderDeviceID)) — dropping envelope")
                return
            }

            let plaintext = try await SessionManager.shared.decrypt(
                header: header,
                ciphertext: ciphertext,
                from: sessionKey,
                expectedIdentityKey: expectedIdentityKey
            )

            let payload = try decoder.decode(MessagePayload.self, from: plaintext)

            // For media messages, the displayBody is the mime type hint until downloaded
            let displayBody: String
            switch payload.type {
            case .text:   displayBody = payload.body ?? ""
            case .image:  displayBody = "📷 Photo"
            case .voice:  displayBody = "🎤 Voice message"
            default:      displayBody = ""
            }

            // Sender copy: envelope arrived from our own user ID (different device sent it)
            let myID = AccountManager.shared.userID
            let isSenderCopy = envelope.senderUserID == myID

            let conversationID: String
            let status: MessageStatus
            if isSenderCopy {
                // Recover conversation from payload; fall back to own ID if missing
                conversationID = payload.conversationUserID ?? envelope.senderUserID
                status = .sent
            } else {
                conversationID = envelope.senderUserID
                status = .delivered
            }

            let message = Message(
                id: payload.id,
                conversationID: conversationID,
                senderID: isSenderCopy ? myID : envelope.senderUserID,
                senderDeviceID: envelope.senderDeviceID,
                type: payload.type,
                body: displayBody,
                localPath: nil,
                timestamp: envelope.date,
                status: status
            )
            await messageStore?.upsert(message)

            // Store attachment key for later download
            if let objectKey = payload.mediaObjectKey, let attachmentKey = payload.mediaAttachmentKey {
                await messageStore?.storeAttachmentKey(
                    messageID: payload.id,
                    objectKey: objectKey,
                    attachmentKey: attachmentKey
                )
            }

            // Send delivery receipt back via WebSocket (not for own sender copies)
            if !isSenderCopy {
                WebSocketClient.shared.sendDeliveryReceipt(
                    envelopeID: envelope.id,
                    senderUserID: envelope.senderUserID,
                    senderDeviceID: envelope.senderDeviceID
                )
            }
        } catch SignalError.identityKeyChanged {
            NotificationCenter.default.post(
                name: .identityKeyChanged,
                object: envelope.senderUserID
            )
        } catch {
            print("[MessagePipeline] decrypt error: \(error)")
        }
    }

    // MARK: - Wire payload format
    // Wire format: 1 byte type | 4 bytes header length (big-endian) | header JSON | ciphertext

    private func buildWirePayload(header: MessageHeader, ciphertext: Data) throws -> Data {
        let headerData = try encoder.encode(header)
        var result = Data()
        result.append(0x02)  // Whisper message type
        let headerLen = UInt32(headerData.count).bigEndian
        result.append(contentsOf: withUnsafeBytes(of: headerLen) { Data($0) })
        result.append(headerData)
        result.append(ciphertext)
        return result
    }

    private func parseWirePayload(_ data: Data) throws -> (MessageHeader, Data) {
        guard data.count > 5 else { throw SignalError.decryptionFailed }
        let headerLen = Int(UInt32(bigEndian: data[1..<5].withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard data.count > 5 + headerLen else { throw SignalError.decryptionFailed }
        let headerData = data[5..<(5 + headerLen)]
        let ciphertext = data[(5 + headerLen)...]
        let header = try decoder.decode(MessageHeader.self, from: headerData)
        return (header, Data(ciphertext))
    }

    // MARK: - WebSocket wiring

    private func setupWebSocket() {
        let ws = WebSocketClient.shared
        ws.onEnvelope = { [weak self] envelope in
            Task { await self?.receive(envelope: envelope) }
        }
        ws.onDeliveryReceipt = { envelopeID in
            Task { await MessagePipeline.shared.messageStore?.updateStatus(.delivered, forEnvelopeID: envelopeID) }
        }
        ws.onReadReceipt = { envelopeID in
            Task { await MessagePipeline.shared.messageStore?.updateStatus(.read, forEnvelopeID: envelopeID) }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let identityKeyChanged = Notification.Name("OpenWhatsIdentityKeyChanged")
    // .signOut is declared public in OpenWhatsCoreSetup.swift
}

// MARK: - MessageStore protocol

protocol MessageStoreProtocol: Actor {
    func upsert(_ message: Message) async
    func updateStatus(_ status: MessageStatus, forEnvelopeID id: String) async
    func messages(for conversationID: String) async -> [Message]
    func storeAttachmentKey(messageID: String, objectKey: String, attachmentKey: AttachmentKey) async
}

// MARK: - PreKeyBundle server response extension

private extension PreKeyBundlesResponse.Bundle {
    func toPreKeyBundle() throws -> PreKeyBundle {
        let ikData = try decodeBase64URL(identityKey)
        let spkData = try decodeBase64URL(signedPreKey)
        let sigData = try decodeBase64URL(signedPreKeySig)
        let opkData: Data? = try oneTimePreKey.map { try decodeBase64URL($0) }

        return try PreKeyBundle(
            deviceID: deviceId,
            deviceType: deviceType,
            identityKeyData: ikData,
            signedPreKeyID: signedPreKeyId,
            signedPreKeyData: spkData,
            signedPreKeySig: sigData,
            oneTimePreKeyID: oneTimePreKeyId,
            oneTimePreKeyData: opkData
        )
    }
}

// MARK: - Base64URL helper

private func decodeBase64URL(_ string: String) throws -> Data {
    var s = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s += "=" }
    guard let d = Data(base64Encoded: s) else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid base64url: \(string.prefix(20))"))
    }
    return d
}
