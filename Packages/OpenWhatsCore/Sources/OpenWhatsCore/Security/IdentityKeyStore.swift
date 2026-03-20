import Foundation
import Security

/// Stores trusted remote identity keys on a per-(userID, deviceID) basis using Keychain.
///
/// Trust model: Trust On First Use (TOFU).
///   - First contact: the identity key is stored and trusted automatically.
///   - Subsequent contacts: the stored key is compared against the incoming key.
///   - Mismatch: callers should surface a security warning to the user.
final class IdentityKeyStore {

    static let shared = IdentityKeyStore()

    private let keychainService = "com.openwhats.identitykeys"
    private init() {}

    // MARK: - Public interface

    /// Returns the trusted identity key for a peer device, or nil if never seen.
    func trustedKey(for userID: String, deviceID: String) -> Data? {
        loadFromKeychain(account: storeKey(userID: userID, deviceID: deviceID))
    }

    /// Overwrite the trusted identity key (used after the user acknowledges a key change).
    func setTrustedKey(_ key: Data, for userID: String, deviceID: String) {
        try? saveToKeychain(account: storeKey(userID: userID, deviceID: deviceID), data: key)
    }

    /// TOFU verify: if no key is stored, store and return `true` (first contact).
    /// If a key is stored and matches, return `true`.
    /// If a key is stored and differs, return `false` (key change detected).
    @discardableResult
    func verifyOrTrust(_ key: Data, for userID: String, deviceID: String) -> Bool {
        let account = storeKey(userID: userID, deviceID: deviceID)
        if let stored = loadFromKeychain(account: account) {
            return stored == key
        }
        // First contact — trust and persist
        try? saveToKeychain(account: account, data: key)
        return true
    }

    /// Remove the trusted key (e.g. when a device is unlinked).
    func removeTrustedKey(for userID: String, deviceID: String) {
        deleteFromKeychain(account: storeKey(userID: userID, deviceID: deviceID))
    }

    // MARK: - Keychain internals

    private func storeKey(userID: String, deviceID: String) -> String {
        "\(userID):\(deviceID)"
    }

    private func saveToKeychain(account: String, data: Data) throws {
        deleteFromKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
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
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
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
