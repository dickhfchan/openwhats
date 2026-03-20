import XCTest
import CryptoKit
@testable import OpenWhatsCore

final class MediaTests: XCTestCase {

    // MARK: - AttachmentCrypto

    func testEncryptDecryptRoundTrip() throws {
        let original = "Hello, encrypted attachment!".data(using: .utf8)!
        let encrypted = try AttachmentCrypto.encrypt(data: original, mimeType: "text/plain")

        XCTAssertNotEqual(encrypted.ciphertext, original)
        XCTAssertEqual(encrypted.key.key.count, 32)
        XCTAssertEqual(encrypted.key.iv.count, 12)
        XCTAssertEqual(encrypted.key.hmac.count, 32)

        let decrypted = try AttachmentCrypto.decrypt(ciphertext: encrypted.ciphertext, key: encrypted.key)
        XCTAssertEqual(decrypted, original)
    }

    func testEncryptProducesUniqueCiphertexts() throws {
        let data = "same plaintext".data(using: .utf8)!
        let enc1 = try AttachmentCrypto.encrypt(data: data, mimeType: "text/plain")
        let enc2 = try AttachmentCrypto.encrypt(data: data, mimeType: "text/plain")

        // Different keys and IVs each time
        XCTAssertNotEqual(enc1.key.key, enc2.key.key)
        XCTAssertNotEqual(enc1.key.iv, enc2.key.iv)
        XCTAssertNotEqual(enc1.ciphertext, enc2.ciphertext)
    }

    func testDecryptWithWrongKeyFails() throws {
        let data = "secret data".data(using: .utf8)!
        let encrypted = try AttachmentCrypto.encrypt(data: data, mimeType: "text/plain")

        // Corrupt the key
        var keyBytes = encrypted.key.key
        keyBytes[keyBytes.startIndex] ^= 0xFF
        let wrongKey = AttachmentKey(key: keyBytes, iv: encrypted.key.iv, hmac: encrypted.key.hmac)

        var didThrow = false
        do {
            _ = try AttachmentCrypto.decrypt(ciphertext: encrypted.ciphertext, key: wrongKey)
        } catch {
            didThrow = true
        }
        XCTAssertTrue(didThrow, "Expected decryption to fail with wrong key")
    }

    func testDecryptWithTamperedCiphertextFails() throws {
        let data = "tamper test".data(using: .utf8)!
        let encrypted = try AttachmentCrypto.encrypt(data: data, mimeType: "text/plain")

        var tampered = encrypted.ciphertext
        tampered[tampered.startIndex] ^= 0x01

        var didThrow = false
        do {
            _ = try AttachmentCrypto.decrypt(ciphertext: tampered, key: encrypted.key)
        } catch {
            didThrow = true
            XCTAssertTrue(error is AttachmentError, "Expected AttachmentError, got \(error)")
        }
        XCTAssertTrue(didThrow, "Expected decryption to throw for tampered ciphertext")
    }

    func testLargeDataRoundTrip() throws {
        // 1 MB random data
        var large = Data(count: 1024 * 1024)
        let count = large.count
        _ = large.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }

        let encrypted = try AttachmentCrypto.encrypt(data: large, mimeType: "application/octet-stream")
        let decrypted = try AttachmentCrypto.decrypt(ciphertext: encrypted.ciphertext, key: encrypted.key)
        XCTAssertEqual(decrypted, large)
    }

    func testHmacVerificationFailsOnModifiedCiphertext() throws {
        let data = "integrity check".data(using: .utf8)!
        let encrypted = try AttachmentCrypto.encrypt(data: data, mimeType: "text/plain")

        // Tamper with the last byte of ciphertext
        var tampered = encrypted.ciphertext
        tampered[tampered.index(before: tampered.endIndex)] ^= 0xFF

        var thrownError: Error?
        do {
            _ = try AttachmentCrypto.decrypt(ciphertext: tampered, key: encrypted.key)
        } catch {
            thrownError = error
        }
        let attachError = try XCTUnwrap(thrownError as? AttachmentError)
        XCTAssertEqual(attachError, .hmacVerificationFailed)
    }

    func testAttachmentKeyIsCodable() throws {
        let data = "codable key test".data(using: .utf8)!
        let encrypted = try AttachmentCrypto.encrypt(data: data, mimeType: "text/plain")

        // Encode and decode the AttachmentKey
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(encrypted.key)
        let decoded = try decoder.decode(AttachmentKey.self, from: encoded)

        XCTAssertEqual(decoded.key, encrypted.key.key)
        XCTAssertEqual(decoded.iv, encrypted.key.iv)
        XCTAssertEqual(decoded.hmac, encrypted.key.hmac)

        // Decrypt using the decoded key
        let decrypted = try AttachmentCrypto.decrypt(ciphertext: encrypted.ciphertext, key: decoded)
        XCTAssertEqual(decrypted, data)
    }
}

extension AttachmentError: Equatable {
    public static func == (lhs: AttachmentError, rhs: AttachmentError) -> Bool {
        switch (lhs, rhs) {
        case (.hmacVerificationFailed, .hmacVerificationFailed): return true
        case (.invalidCiphertext, .invalidCiphertext):           return true
        case (.cacheMiss, .cacheMiss):                           return true
        default:                                                  return false
        }
    }
}
