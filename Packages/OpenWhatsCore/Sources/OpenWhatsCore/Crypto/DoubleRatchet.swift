import CryptoKit
import Foundation

// MARK: - Double Ratchet session state

/// Serializable Double Ratchet session state.
/// Spec: https://signal.org/docs/specifications/doubleratchet/
struct RatchetSession: Codable {
    // DH ratchet keys
    var DHs: DHKeyPairCodable       // our current sending DH key pair
    var DHr: Data?                  // remote's current DH ratchet public key

    // Chain keys
    var RK: Data                    // 32-byte root key
    var CKs: Data?                  // 32-byte sending chain key
    var CKr: Data?                  // 32-byte receiving chain key

    // Message counters
    var Ns: Int                     // next send message index
    var Nr: Int                     // next receive message index
    var PN: Int                     // prev chain message count

    // Skipped message keys: (ratchetKey || chainIndex) → message key
    var skippedMessageKeys: [String: Data]

    // Identity key of the remote party (for change detection)
    var remoteIdentityKey: Data

    static let maxSkip = 1000       // max skipped messages per ratchet step
}

/// Codable wrapper for a Curve25519 key pair (raw bytes only; private key in Keychain in prod).
struct DHKeyPairCodable: Codable {
    var privateKeyData: Data
    var publicKeyData: Data

    init(from pair: KeyAgreementKeyPair) {
        privateKeyData = pair.privateKeyData
        publicKeyData = pair.publicKeyData
    }

    func toKeyPair() throws -> KeyAgreementKeyPair {
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        return KeyAgreementKeyPair(privateKey: priv)
    }
}

// MARK: - Double Ratchet engine

enum DoubleRatchet {

    // MARK: - Initialise (sender)

    /// Create a new session on the sender side after X3DH.
    /// - Parameters:
    ///   - sharedSecret: 32-byte SK from X3DH
    ///   - recipientRatchetKey: Recipient's signed pre-key public key (used as initial DHr)
    ///   - remoteIdentityKey: Recipient's identity key (stored for change detection)
    static func initSender(
        sharedSecret: Data,
        recipientRatchetKey: Data,
        remoteIdentityKey: Data
    ) throws -> RatchetSession {
        let dhsPair = KeyAgreementKeyPair()
        let recipientPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientRatchetKey)

        // Root key ratchet step to derive initial sending chain key
        let dh = try dhsPair.privateKey.sharedSecretFromKeyAgreement(with: recipientPub)
        let (newRK, CKs) = kdfRootKey(rootKey: sharedSecret, dhOutput: dh.rawBytes)

        return RatchetSession(
            DHs: DHKeyPairCodable(from: dhsPair),
            DHr: recipientRatchetKey,
            RK: newRK,
            CKs: CKs,
            CKr: nil,
            Ns: 0, Nr: 0, PN: 0,
            skippedMessageKeys: [:],
            remoteIdentityKey: remoteIdentityKey
        )
    }

    // MARK: - Initialise (receiver)

    /// Create a new session on the receiver side after X3DH.
    /// - Parameters:
    ///   - sharedSecret: 32-byte SK from X3DH
    ///   - ourRatchetKeyPair: The signed pre-key that was used (acts as initial DHs)
    ///   - remoteIdentityKey: Sender's identity key
    static func initReceiver(
        sharedSecret: Data,
        ourRatchetKeyPair: KeyAgreementKeyPair,
        remoteIdentityKey: Data
    ) -> RatchetSession {
        RatchetSession(
            DHs: DHKeyPairCodable(from: ourRatchetKeyPair),
            DHr: nil,
            RK: sharedSecret,
            CKs: nil,
            CKr: nil,
            Ns: 0, Nr: 0, PN: 0,
            skippedMessageKeys: [:],
            remoteIdentityKey: remoteIdentityKey
        )
    }

    // MARK: - Encrypt

    struct EncryptResult {
        let header: MessageHeader
        let ciphertext: Data
    }

    static func encrypt(
        session: inout RatchetSession,
        plaintext: Data,
        associatedData: Data = Data()
    ) throws -> EncryptResult {
        guard var CKs = session.CKs else {
            throw SignalError.noSessionFound
        }

        let (newCKs, mk) = kdfChainKey(chainKey: CKs)
        CKs = newCKs
        session.CKs = CKs

        let header = MessageHeader(
            ratchetKey: session.DHs.publicKeyData,
            prevChainLen: session.PN,
            msgIndex: session.Ns
        )
        session.Ns += 1

        let ciphertext = try encryptMessage(key: mk, plaintext: plaintext,
                                            associatedData: associatedData + encodeHeader(header))
        return EncryptResult(header: header, ciphertext: ciphertext)
    }

    // MARK: - Decrypt

    static func decrypt(
        session: inout RatchetSession,
        header: MessageHeader,
        ciphertext: Data,
        associatedData: Data = Data()
    ) throws -> Data {
        let ad = associatedData + encodeHeader(header)

        // Check skipped message keys first
        let skippedKey = skippedKeyID(ratchetKey: header.ratchetKey, index: header.msgIndex)
        if let mk = session.skippedMessageKeys[skippedKey] {
            session.skippedMessageKeys.removeValue(forKey: skippedKey)
            return try decryptMessage(key: mk, ciphertext: ciphertext, associatedData: ad)
        }

        // New ratchet key? Perform DH ratchet step
        if header.ratchetKey != session.DHr {
            try skipMessageKeys(&session, until: header.prevChainLen)
            try dhRatchetStep(&session, remoteRatchetKey: header.ratchetKey)
        }

        try skipMessageKeys(&session, until: header.msgIndex)

        guard let CKr = session.CKr else { throw SignalError.decryptionFailed }
        let (newCKr, mk) = kdfChainKey(chainKey: CKr)
        session.CKr = newCKr
        session.Nr += 1

        return try decryptMessage(key: mk, ciphertext: ciphertext, associatedData: ad)
    }

    // MARK: - DH ratchet step

    private static func dhRatchetStep(_ session: inout RatchetSession, remoteRatchetKey: Data) throws {
        session.PN = session.Ns
        session.Ns = 0
        session.Nr = 0
        session.DHr = remoteRatchetKey

        let remotePub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteRatchetKey)
        let currentPair = try session.DHs.toKeyPair()

        // Receiving chain key from new DHr
        let dh1 = try currentPair.privateKey.sharedSecretFromKeyAgreement(with: remotePub)
        let (rk1, CKr) = kdfRootKey(rootKey: session.RK, dhOutput: dh1.rawBytes)

        // Generate new sending DH key pair
        let newDHs = KeyAgreementKeyPair()
        session.DHs = DHKeyPairCodable(from: newDHs)

        // Sending chain key from new DHs
        let dh2 = try newDHs.privateKey.sharedSecretFromKeyAgreement(with: remotePub)
        let (rk2, CKs) = kdfRootKey(rootKey: rk1, dhOutput: dh2.rawBytes)

        session.RK = rk2
        session.CKr = CKr
        session.CKs = CKs
    }

    // MARK: - Skip message keys

    private static func skipMessageKeys(_ session: inout RatchetSession, until index: Int) throws {
        guard let CKr = session.CKr else { return }
        guard index >= session.Nr else { return }

        if index - session.Nr > RatchetSession.maxSkip {
            throw SignalError.tooManySkippedMessages
        }

        var chainKey = CKr
        while session.Nr < index {
            let (newCK, mk) = kdfChainKey(chainKey: chainKey)
            chainKey = newCK
            let id = skippedKeyID(ratchetKey: session.DHr ?? Data(), index: session.Nr)
            session.skippedMessageKeys[id] = mk
            session.Nr += 1
        }
        session.CKr = chainKey
    }

    // MARK: - KDF functions

    /// KDF_RK: HKDF-SHA256(RK, DH output) → (new RK 32 bytes, new CK 32 bytes)
    private static func kdfRootKey(rootKey: Data, dhOutput: Data) -> (Data, Data) {
        let out = hkdfSHA256(
            inputKeyMaterial: dhOutput,
            salt: rootKey,
            info: Data("OpenWhatsRatchet".utf8),
            outputLength: 64
        )
        return (out.prefix(32), out.suffix(32))
    }

    /// KDF_CK: HMAC-SHA256 chain ratchet → (new CK, message key)
    private static func kdfChainKey(chainKey: Data) -> (Data, Data) {
        let ck = SymmetricKey(data: chainKey)
        let newCK = Data(HMAC<SHA256>.authenticationCode(for: Data([0x02]), using: ck))
        let mk    = Data(HMAC<SHA256>.authenticationCode(for: Data([0x01]), using: ck))
        return (newCK, mk)
    }

    // MARK: - Message encryption (AES-256-GCM)

    private static func encryptMessage(key: Data, plaintext: Data, associatedData: Data) throws -> Data {
        // Derive 32-byte encryption key + 12-byte nonce from message key
        let expanded = hkdfSHA256(
            inputKeyMaterial: key,
            salt: Data(repeating: 0x00, count: 32),
            info: Data("OpenWhatsMessageKeys".utf8),
            outputLength: 44    // 32 (aes key) + 12 (nonce)
        )
        let aesKey = SymmetricKey(data: expanded.prefix(32))
        let nonce = try AES.GCM.Nonce(data: expanded.suffix(12))

        let sealed = try AES.GCM.seal(plaintext, using: aesKey, nonce: nonce,
                                       authenticating: associatedData)
        // ciphertext || tag (combined representation without nonce, nonce is deterministic)
        return sealed.ciphertext + sealed.tag
    }

    private static func decryptMessage(key: Data, ciphertext: Data, associatedData: Data) throws -> Data {
        guard ciphertext.count > 16 else { throw SignalError.decryptionFailed }

        let expanded = hkdfSHA256(
            inputKeyMaterial: key,
            salt: Data(repeating: 0x00, count: 32),
            info: Data("OpenWhatsMessageKeys".utf8),
            outputLength: 44
        )
        let aesKey = SymmetricKey(data: expanded.prefix(32))
        let nonce = try AES.GCM.Nonce(data: expanded.suffix(12))

        let ct = ciphertext.dropLast(16)
        let tag = ciphertext.suffix(16)

        do {
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
            return try AES.GCM.open(box, using: aesKey, authenticating: associatedData)
        } catch {
            throw SignalError.decryptionFailed
        }
    }

    // MARK: - Helpers

    private static func encodeHeader(_ header: MessageHeader) -> Data {
        var data = Data()
        data.append(contentsOf: header.ratchetKey)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(bigEndian: UInt32(header.prevChainLen))) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(bigEndian: UInt32(header.msgIndex))) { Data($0) })
        return data
    }

    private static func skippedKeyID(ratchetKey: Data, index: Int) -> String {
        "\(ratchetKey.base64EncodedString()):\(index)"
    }
}

// MARK: - Data comparison helper

private func != (lhs: Data, rhs: Data?) -> Bool {
    guard let rhs else { return true }
    return lhs != rhs
}
