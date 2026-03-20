import CryptoKit
import Foundation

/// X3DH (Extended Triple Diffie-Hellman) key agreement.
/// Spec: https://signal.org/docs/specifications/x3dh/
enum X3DH {

    // MARK: - Sender side

    struct SenderResult {
        /// 32-byte shared secret — used to seed the Double Ratchet root key.
        let sharedSecret: Data
        /// The ephemeral key pair's public key — included in the PreKeyMessage header.
        let ephemeralKeyData: Data
    }

    /// Called by the message sender before the first message in a session.
    /// - Parameters:
    ///   - senderIdentityKey: Sender's long-term Curve25519 key pair (IK_A)
    ///   - recipientBundle: Recipient's pre-key bundle fetched from the key server
    static func senderKeyAgreement(
        senderIdentityKey: IdentityKeyPair,
        recipientBundle: PreKeyBundle
    ) throws -> SenderResult {
        // Generate a fresh ephemeral key pair for this session
        let ephemeral = EphemeralKeyPair()

        // DH1 = DH(IK_A.private, SPK_B.public)
        let dh1 = try senderIdentityKey.privateKey
            .sharedSecretFromKeyAgreement(with: recipientBundle.signedPreKey)

        // DH2 = DH(EK_A.private, IK_B.public)
        let dh2 = try ephemeral.privateKey
            .sharedSecretFromKeyAgreement(with: recipientBundle.identityKey)

        // DH3 = DH(EK_A.private, SPK_B.public)
        let dh3 = try ephemeral.privateKey
            .sharedSecretFromKeyAgreement(with: recipientBundle.signedPreKey)

        var dhConcat = Data()
        dhConcat.append(dh1.rawBytes)
        dhConcat.append(dh2.rawBytes)
        dhConcat.append(dh3.rawBytes)

        // DH4 = DH(EK_A.private, OPK_B.public) — optional, only if OTPK provided
        if let opk = recipientBundle.oneTimePreKey {
            let dh4 = try ephemeral.privateKey.sharedSecretFromKeyAgreement(with: opk)
            dhConcat.append(dh4.rawBytes)
        }

        let sk = kdfX3DH(dhConcat)

        return SenderResult(
            sharedSecret: sk,
            ephemeralKeyData: ephemeral.publicKeyData
        )
    }

    // MARK: - Receiver side

    /// Called by the message recipient upon receiving a PreKeyMessage.
    /// - Parameters:
    ///   - receiverIdentityKey: Receiver's long-term key pair (IK_B)
    ///   - receiverSignedPreKey: The signed pre-key identified in the message (SPK_B)
    ///   - receiverOneTimePreKey: The one-time pre-key if one was used (OPK_B)
    ///   - senderIdentityKeyData: Sender's identity public key from message header
    ///   - senderEphemeralKeyData: Sender's ephemeral public key from message header
    static func receiverKeyAgreement(
        receiverIdentityKey: IdentityKeyPair,
        receiverSignedPreKey: SignedPreKeyPair,
        receiverOneTimePreKey: OneTimePreKeyPair?,
        senderIdentityKeyData: Data,
        senderEphemeralKeyData: Data
    ) throws -> Data {
        let senderIK = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderIdentityKeyData)
        let senderEK = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderEphemeralKeyData)

        // DH1 = DH(SPK_B.private, IK_A.public)
        let dh1 = try receiverSignedPreKey.privateKey.sharedSecretFromKeyAgreement(with: senderIK)

        // DH2 = DH(IK_B.private, EK_A.public)
        let dh2 = try receiverIdentityKey.privateKey.sharedSecretFromKeyAgreement(with: senderEK)

        // DH3 = DH(SPK_B.private, EK_A.public)
        let dh3 = try receiverSignedPreKey.privateKey.sharedSecretFromKeyAgreement(with: senderEK)

        var dhConcat = Data()
        dhConcat.append(dh1.rawBytes)
        dhConcat.append(dh2.rawBytes)
        dhConcat.append(dh3.rawBytes)

        // DH4 = DH(OPK_B.private, EK_A.public) — if a one-time pre-key was used
        if let opk = receiverOneTimePreKey {
            let dh4 = try opk.privateKey.sharedSecretFromKeyAgreement(with: senderEK)
            dhConcat.append(dh4.rawBytes)
        }

        return kdfX3DH(dhConcat)
    }

    // MARK: - KDF

    /// X3DH KDF: HKDF-SHA256 over F || DH1 || DH2 || DH3 [|| DH4]
    /// F = 0xFF * 32 bytes (as per Signal spec, provides domain separation)
    private static func kdfX3DH(_ dhConcat: Data) -> Data {
        // F: 32 bytes of 0xFF (fixes the first part of input key material)
        let f = Data(repeating: 0xFF, count: 32)
        let ikm = f + dhConcat

        // Salt: 32 zero bytes
        let salt = Data(repeating: 0x00, count: 32)

        // Info: app-specific label
        let info = Data("OpenWhatsX3DH".utf8)

        return hkdfSHA256(inputKeyMaterial: ikm, salt: salt, info: info, outputLength: 32)
    }
}

// MARK: - HKDF helper

func hkdfSHA256(inputKeyMaterial: Data, salt: Data, info: Data, outputLength: Int) -> Data {
    let key = SymmetricKey(data: inputKeyMaterial)
    let derivedKey = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: key,
        salt: salt,
        info: info,
        outputByteCount: outputLength
    )
    return derivedKey.withUnsafeBytes { Data($0) }
}

// MARK: - SharedSecret extension

extension SharedSecret {
    var rawBytes: Data {
        withUnsafeBytes { Data($0) }
    }
}
