import CryptoKit
import Foundation

// MARK: - AttachmentKey

/// The per-attachment symmetric key material included (encrypted) in the Signal message payload.
public struct AttachmentKey: Codable, Sendable {
    /// 32-byte AES-256 key (base64)
    public let key: Data
    /// 16-byte IV (base64)
    public let iv: Data
    /// 32-byte HMAC-SHA256 over ciphertext (base64)
    public let hmac: Data

    public init(key: Data, iv: Data, hmac: Data) {
        self.key = key
        self.iv = iv
        self.hmac = hmac
    }
}

// MARK: - EncryptedAttachment

public struct EncryptedAttachment {
    public let ciphertext: Data
    public let key: AttachmentKey
    public let mimeType: String
    public let originalSize: Int

    public init(ciphertext: Data, key: AttachmentKey, mimeType: String, originalSize: Int) {
        self.ciphertext = ciphertext
        self.key = key
        self.mimeType = mimeType
        self.originalSize = originalSize
    }
}

// MARK: - AttachmentCrypto

/// Encrypts and decrypts media attachments using AES-256-CTR + HMAC-SHA256.
/// A fresh 32-byte key and 16-byte IV are generated for every attachment.
/// The HMAC is computed over the ciphertext to provide integrity.
/// Key material is included encrypted inside the Signal message payload.
public enum AttachmentCrypto {

    /// Encrypts plaintext bytes. Generates a fresh key and IV.
    public static func encrypt(data: Data, mimeType: String) throws -> EncryptedAttachment {
        // Generate random 32-byte key and 16-byte nonce
        let keyBytes = SymmetricKey(size: .bits256)
        var ivBytes = Data(count: 12)  // 96-bit nonce for AES-GCM
        _ = ivBytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 12, $0.baseAddress!) }

        // Encrypt with AES-256-GCM
        let sealedBox = try AES.GCM.seal(data, using: keyBytes, nonce: AES.GCM.Nonce(data: ivBytes))
        let ciphertext = sealedBox.ciphertext + sealedBox.tag  // ciphertext || 16-byte auth tag

        // HMAC-SHA256 over ciphertext for additional integrity binding
        let hmacKey = SymmetricKey(data: keyBytes.withUnsafeBytes { Data($0) })
        let mac = HMAC<SHA256>.authenticationCode(for: ciphertext, using: hmacKey)

        let attachmentKey = AttachmentKey(
            key: keyBytes.withUnsafeBytes { Data($0) },
            iv: ivBytes,
            hmac: Data(mac)
        )
        return EncryptedAttachment(
            ciphertext: ciphertext,
            key: attachmentKey,
            mimeType: mimeType,
            originalSize: data.count
        )
    }

    /// Decrypts ciphertext using the provided AttachmentKey.
    /// Verifies HMAC before decrypting.
    public static func decrypt(ciphertext: Data, key: AttachmentKey) throws -> Data {
        // Verify HMAC first
        let hmacKey = SymmetricKey(data: key.key)
        guard HMAC<SHA256>.isValidAuthenticationCode(key.hmac, authenticating: ciphertext, using: hmacKey) else {
            throw AttachmentError.hmacVerificationFailed
        }

        guard ciphertext.count > 16 else { throw AttachmentError.invalidCiphertext }
        let body = ciphertext.dropLast(16)
        let tag = ciphertext.suffix(16)

        let aesKey = SymmetricKey(data: key.key)
        let nonce = try AES.GCM.Nonce(data: key.iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        return try AES.GCM.open(sealedBox, using: aesKey)
    }
}

// MARK: - AttachmentError

public enum AttachmentError: Error, LocalizedError {
    case hmacVerificationFailed
    case invalidCiphertext
    case downloadFailed(Error)
    case cacheMiss

    public var errorDescription: String? {
        switch self {
        case .hmacVerificationFailed:  return "Attachment integrity check failed"
        case .invalidCiphertext:       return "Attachment ciphertext is malformed"
        case .downloadFailed(let e):   return "Download failed: \(e.localizedDescription)"
        case .cacheMiss:               return "Attachment not in cache"
        }
    }
}
