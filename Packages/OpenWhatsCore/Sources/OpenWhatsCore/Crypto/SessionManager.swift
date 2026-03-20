import CryptoKit
import Foundation

/// SessionManager owns all Double Ratchet sessions and orchestrates
/// the encrypt/decrypt pipeline for outgoing and incoming messages.
///
/// One session exists per remote (userID, deviceID) pair.
/// Sessions are persisted via SessionStore (SQLCipher).
@MainActor
final class SessionManager {

    static let shared = SessionManager()
    private init() {}

    // In-memory session cache; persistent store is SQLCipher via SessionStore
    private var sessions: [SessionKey: RatchetSession] = [:]

    // MARK: - Send

    /// Encrypt plaintext for a remote device.
    /// If no session exists, throws — caller must establish session via X3DH first.
    func encrypt(plaintext: Data, for key: SessionKey, associatedData: Data = Data()) throws -> (MessageHeader, Data) {
        guard var session = sessions[key] ?? SessionStore.shared.load(for: key) else {
            throw SignalError.noSessionFound
        }
        let result = try DoubleRatchet.encrypt(session: &session, plaintext: plaintext, associatedData: associatedData)
        sessions[key] = session
        SessionStore.shared.save(session, for: key)
        return (result.header, result.ciphertext)
    }

    // MARK: - Receive

    /// Decrypt an incoming message. Verifies the remote identity key hasn't changed.
    func decrypt(
        header: MessageHeader,
        ciphertext: Data,
        from key: SessionKey,
        expectedIdentityKey: Data,
        associatedData: Data = Data()
    ) throws -> Data {
        guard var session = sessions[key] ?? SessionStore.shared.load(for: key) else {
            throw SignalError.noSessionFound
        }

        // Identity key change detection
        if session.remoteIdentityKey != expectedIdentityKey {
            throw SignalError.identityKeyChanged
        }

        let plaintext = try DoubleRatchet.decrypt(session: &session, header: header,
                                                   ciphertext: ciphertext,
                                                   associatedData: associatedData)
        sessions[key] = session
        SessionStore.shared.save(session, for: key)
        return plaintext
    }

    // MARK: - Session establishment (X3DH sender)

    /// Establish a new outgoing session using the recipient's pre-key bundle.
    /// Returns the session key, shared secret, and ephemeral key bytes for the PreKeyMessage header.
    func establishSenderSession(bundle: PreKeyBundle) throws -> (SessionKey, Data) {
        // Verify the signed pre-key signature using the recipient's identity key
        let signingPub = try Curve25519.Signing.PublicKey(rawRepresentation: bundle.identityKey.rawRepresentation)
        guard signingPub.isValidSignature(bundle.signedPreKeySig, for: bundle.signedPreKey.rawRepresentation) else {
            throw SignalError.invalidSignature
        }

        let myIdentity = try KeyStore.shared.identityKeyAgreementPair()
        let result = try X3DH.senderKeyAgreement(senderIdentityKey: myIdentity, recipientBundle: bundle)

        let session = try DoubleRatchet.initSender(
            sharedSecret: result.sharedSecret,
            recipientRatchetKey: bundle.signedPreKey.rawRepresentation,
            remoteIdentityKey: bundle.identityKey.rawRepresentation
        )

        let key = SessionKey(userID: bundle.deviceID, deviceID: bundle.deviceID)
        sessions[key] = session
        SessionStore.shared.save(session, for: key)

        return (key, result.ephemeralKeyData)
    }

    // MARK: - Session establishment (X3DH receiver)

    /// Establish a new incoming session upon receiving a PreKeyMessage.
    func establishReceiverSession(
        senderIdentityKeyData: Data,
        senderEphemeralKeyData: Data,
        signedPreKeyID: Int,
        oneTimePreKeyID: Int?
    ) throws -> SessionKey {
        let myIdentity = try KeyStore.shared.identityKeyAgreementPair()

        guard let spk = try KeyStore.shared.loadSignedPreKey(id: signedPreKeyID) else {
            throw SignalError.noSessionFound
        }

        var otpk: OneTimePreKeyPair?
        if let opkID = oneTimePreKeyID {
            otpk = try KeyStore.shared.consumeOneTimePreKey(id: opkID)
        }

        let sk = try X3DH.receiverKeyAgreement(
            receiverIdentityKey: myIdentity,
            receiverSignedPreKey: spk,
            receiverOneTimePreKey: otpk,
            senderIdentityKeyData: senderIdentityKeyData,
            senderEphemeralKeyData: senderEphemeralKeyData
        )

        let session = DoubleRatchet.initReceiver(
            sharedSecret: sk,
            ourRatchetKeyPair: spk,
            remoteIdentityKey: senderIdentityKeyData
        )

        // Use senderIdentityKeyData as the session key identifier (will be refined when we have user/device IDs)
        let sessionKey = SessionKey(userID: senderIdentityKeyData.base64EncodedString(),
                                    deviceID: senderIdentityKeyData.base64EncodedString())
        sessions[sessionKey] = session
        SessionStore.shared.save(session, for: sessionKey)

        return sessionKey
    }

    func clearCache() {
        sessions = [:]
    }
}

// MARK: - Session Key

struct SessionKey: Hashable, Codable {
    let userID: String
    let deviceID: String
}

// MARK: - Session Store (stub — full SQLCipher implementation in Phase 3)

/// Lightweight in-memory + UserDefaults session store.
/// Phase 3 will replace this with SQLCipher-backed storage.
final class SessionStore {
    static let shared = SessionStore()
    private var store: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func save(_ session: RatchetSession, for key: SessionKey) {
        guard let data = try? encoder.encode(session) else { return }
        store[storeKey(key)] = data
    }

    func load(for key: SessionKey) -> RatchetSession? {
        guard let data = store[storeKey(key)] else { return nil }
        return try? decoder.decode(RatchetSession.self, from: data)
    }

    func delete(for key: SessionKey) {
        store.removeValue(forKey: storeKey(key))
    }

    private func storeKey(_ key: SessionKey) -> String { "\(key.userID):\(key.deviceID)" }
}
