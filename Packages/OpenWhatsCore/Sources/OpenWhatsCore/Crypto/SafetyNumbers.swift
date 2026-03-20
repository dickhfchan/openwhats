import CryptoKit
import Foundation

/// Safety Numbers — allows users to verify their E2EE session out of band.
/// Displayed as a 60-digit numeric string (12 groups of 5 digits).
/// Spec mirrors Signal's safety number format.
enum SafetyNumbers {

    /// Compute the safety number for a conversation between two users.
    /// - Parameters:
    ///   - localUserID: Our user ID (UUID string)
    ///   - localIdentityKey: Our identity key public bytes
    ///   - remoteUserID: Their user ID
    ///   - remoteIdentityKey: Their identity key public bytes
    static func compute(
        localUserID: String,
        localIdentityKey: Data,
        remoteUserID: String,
        remoteIdentityKey: Data
    ) -> String {
        // Canonically order the two parties by user ID to ensure both sides compute
        // the same number regardless of who's local/remote.
        let (id1, key1, id2, key2) = localUserID < remoteUserID
            ? (localUserID, localIdentityKey, remoteUserID, remoteIdentityKey)
            : (remoteUserID, remoteIdentityKey, localUserID, localIdentityKey)

        let chunk1 = chunkNumber(userID: id1, identityKey: key1)
        let chunk2 = chunkNumber(userID: id2, identityKey: key2)

        return formatNumber(chunk1 + chunk2)
    }

    // MARK: - Private

    /// Compute 30 digits for one party: 5 iterations of SHA-512, each producing 5 decimal digits.
    private static func chunkNumber(userID: String, identityKey: Data) -> String {
        var input = Data()
        input.append(identityKey)
        input.append(Data(userID.utf8))

        var result = ""
        for _ in 0..<6 {        // 6 iterations × 5 digits = 30 digits per party
            let hash = Data(SHA512.hash(data: input))
            // Take first 5 bytes, interpret as big-endian UInt40 mod 100000
            let value = bigEndianValue(hash.prefix(5)) % 100_000
            result += String(format: "%05d", value)
            input = hash          // chain the hash
        }
        return result
    }

    private static func bigEndianValue(_ data: Data) -> UInt64 {
        data.reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// Format 60 digits as 12 groups of 5 separated by spaces.
    private static func formatNumber(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 5)
            .map { i -> String in
                let start = digits.index(digits.startIndex, offsetBy: i)
                let end   = digits.index(start, offsetBy: 5, limitedBy: digits.endIndex) ?? digits.endIndex
                return String(digits[start..<end])
            }
            .joined(separator: " ")
    }
}
