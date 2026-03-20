import CryptoKit
import Foundation
import Security

/// KeyStore manages all Signal Protocol key material using the system Keychain.
/// All keys are stored with accessibility `.whenUnlockedThisDeviceOnly`.
final class KeyStore {

    static let shared = KeyStore()

    private let keychainService = "com.openwhats.signalkeys"
    private let identityKAKey   = "identity.keyagreement"   // Curve25519 KA private key
    private let identitySignKey = "identity.signing"        // Curve25519 Signing private key
    private let spkPrefix       = "spk."                    // signed pre-key: spk.<keyId>
    private let otpkPrefix      = "otpk."                   // one-time pre-key: otpk.<keyId>

    private init() {}

    // MARK: - Identity Keys

    /// Returns or creates the device's long-term Curve25519 key agreement key pair.
    func identityKeyAgreementPair() throws -> IdentityKeyPair {
        if let data = loadFromKeychain(account: identityKAKey) {
            let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
            return IdentityKeyPair(privateKey: priv)
        }
        let pair = IdentityKeyPair()
        try saveToKeychain(account: identityKAKey, data: pair.privateKeyData)
        return pair
    }

    /// Returns or creates the device's long-term Curve25519 signing key pair (Ed25519).
    func identitySigningPair() throws -> SigningKeyPair {
        if let data = loadFromKeychain(account: identitySignKey) {
            let priv = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
            return SigningKeyPair(privateKey: priv)
        }
        let pair = SigningKeyPair()
        try saveToKeychain(account: identitySignKey, data: pair.privateKeyData)
        return pair
    }

    // MARK: - Signed Pre-Keys

    func saveSignedPreKey(id: Int, pair: SignedPreKeyPair) throws {
        try saveToKeychain(account: "\(spkPrefix)\(id)", data: pair.privateKeyData)
    }

    func loadSignedPreKey(id: Int) throws -> SignedPreKeyPair? {
        guard let data = loadFromKeychain(account: "\(spkPrefix)\(id)") else { return nil }
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        return SignedPreKeyPair(privateKey: priv)
    }

    func deleteSignedPreKey(id: Int) {
        deleteFromKeychain(account: "\(spkPrefix)\(id)")
    }

    // MARK: - One-Time Pre-Keys

    func saveOneTimePreKey(id: Int, pair: OneTimePreKeyPair) throws {
        try saveToKeychain(account: "\(otpkPrefix)\(id)", data: pair.privateKeyData)
    }

    func loadOneTimePreKey(id: Int) throws -> OneTimePreKeyPair? {
        guard let data = loadFromKeychain(account: "\(otpkPrefix)\(id)") else { return nil }
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        return OneTimePreKeyPair(privateKey: priv)
    }

    /// Load and immediately delete a one-time pre-key (consume it).
    func consumeOneTimePreKey(id: Int) throws -> OneTimePreKeyPair? {
        let pair = try loadOneTimePreKey(id: id)
        if pair != nil { deleteFromKeychain(account: "\(otpkPrefix)\(id)") }
        return pair
    }

    // MARK: - Key generation helpers

    /// Generate a signed pre-key, store it, and return the upload payload.
    func generateSignedPreKey(id: Int) throws -> (pair: SignedPreKeyPair, signature: Data) {
        let pair = SignedPreKeyPair()
        let signingPair = try identitySigningPair()
        let signature = try signingPair.sign(pair.publicKeyData)
        try saveSignedPreKey(id: id, pair: pair)
        return (pair, signature)
    }

    /// Generate a batch of one-time pre-keys, store them, and return upload payloads.
    func generateOneTimePreKeys(startingID: Int, count: Int) throws -> [(id: Int, pair: OneTimePreKeyPair)] {
        var result: [(Int, OneTimePreKeyPair)] = []
        for i in 0..<count {
            let id = startingID + i
            let pair = OneTimePreKeyPair()
            try saveOneTimePreKey(id: id, pair: pair)
            result.append((id, pair))
        }
        return result
    }

    // MARK: - Keychain internals

    private func saveToKeychain(account: String, data: Data) throws {
        deleteFromKeychain(account: account)  // remove old value first

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      account,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyStoreError.keychainWriteFailed(status)
        }
    }

    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private func deleteFromKeychain(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

enum KeyStoreError: Error {
    case keychainWriteFailed(OSStatus)
    case keyNotFound
}
