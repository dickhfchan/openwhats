import CryptoKit
import Foundation

// MARK: - Key type aliases

typealias IdentityKeyPair      = KeyAgreementKeyPair
typealias EphemeralKeyPair     = KeyAgreementKeyPair
typealias SignedPreKeyPair      = KeyAgreementKeyPair
typealias OneTimePreKeyPair     = KeyAgreementKeyPair

/// A Curve25519 key pair used for Diffie-Hellman key agreement.
struct KeyAgreementKeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    var publicKey: Curve25519.KeyAgreement.PublicKey { privateKey.publicKey }

    init() { privateKey = Curve25519.KeyAgreement.PrivateKey() }
    init(privateKey: Curve25519.KeyAgreement.PrivateKey) { self.privateKey = privateKey }

    var publicKeyData: Data { privateKey.publicKey.rawRepresentation }
    var privateKeyData: Data { privateKey.rawRepresentation }
}

/// A Curve25519 key pair used for signing (Ed25519 under the hood via CryptoKit).
struct SigningKeyPair {
    let privateKey: Curve25519.Signing.PrivateKey
    var publicKey: Curve25519.Signing.PublicKey { privateKey.publicKey }

    init() { privateKey = Curve25519.Signing.PrivateKey() }
    init(privateKey: Curve25519.Signing.PrivateKey) { self.privateKey = privateKey }

    var publicKeyData: Data { privateKey.publicKey.rawRepresentation }
    var privateKeyData: Data { privateKey.rawRepresentation }

    func sign(_ data: Data) throws -> Data {
        Data(try privateKey.signature(for: data))
    }
}

// MARK: - Pre-key bundle (received from server for a remote device)

struct PreKeyBundle {
    let deviceID: String
    let deviceType: String
    let identityKey: Curve25519.KeyAgreement.PublicKey
    let signedPreKeyID: Int
    let signedPreKey: Curve25519.KeyAgreement.PublicKey
    let signedPreKeySig: Data
    let oneTimePreKeyID: Int?
    let oneTimePreKey: Curve25519.KeyAgreement.PublicKey?

    init(
        deviceID: String,
        deviceType: String,
        identityKeyData: Data,
        signedPreKeyID: Int,
        signedPreKeyData: Data,
        signedPreKeySig: Data,
        oneTimePreKeyID: Int?,
        oneTimePreKeyData: Data?
    ) throws {
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.identityKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: identityKeyData)
        self.signedPreKeyID = signedPreKeyID
        self.signedPreKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: signedPreKeyData)
        self.signedPreKeySig = signedPreKeySig
        self.oneTimePreKeyID = oneTimePreKeyID
        if let opkData = oneTimePreKeyData {
            self.oneTimePreKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: opkData)
        } else {
            self.oneTimePreKey = nil
        }
    }

    /// Verify the signed pre-key signature against the sender's identity key (Ed25519).
    func verifySignedPreKey(identitySigningKey: Curve25519.Signing.PublicKey) -> Bool {
        identitySigningKey.isValidSignature(signedPreKeySig, for: signedPreKey.rawRepresentation)
    }
}

// MARK: - Message types

enum SignalMessageType: UInt8 {
    case preKey = 1    // first message in a session (contains X3DH header)
    case whisper = 2   // subsequent messages (Double Ratchet only)
}

struct MessageHeader: Codable {
    let ratchetKey: Data    // sender's current DH ratchet public key (32 bytes)
    let prevChainLen: Int   // PN: messages in previous sending chain
    let msgIndex: Int       // N: index in current sending chain
}

struct SignalMessage {
    let type: SignalMessageType
    let header: MessageHeader
    let ciphertext: Data

    // PreKey message extras (only when type == .preKey)
    let senderIdentityKey: Data?
    let senderEphemeralKey: Data?
    let oneTimePreKeyID: Int?
    let signedPreKeyID: Int?
}

// MARK: - Errors

enum SignalError: Error, LocalizedError {
    case invalidKeySize
    case invalidSignature
    case noSessionFound
    case decryptionFailed
    case tooManySkippedMessages
    case identityKeyChanged

    var errorDescription: String? {
        switch self {
        case .invalidKeySize:         return "Invalid key size"
        case .invalidSignature:       return "Signature verification failed"
        case .noSessionFound:         return "No Signal session found for this contact"
        case .decryptionFailed:       return "Message decryption failed"
        case .tooManySkippedMessages: return "Too many skipped messages"
        case .identityKeyChanged:     return "Contact's identity key has changed — verify out of band"
        }
    }
}
