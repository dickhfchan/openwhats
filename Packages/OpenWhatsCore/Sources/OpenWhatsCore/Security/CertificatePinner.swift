import CryptoKit
import Foundation
import Security

/// URLSession delegate that enforces TLS public-key pinning (SPKI SHA-256).
///
/// Populate `pinnedHashes` with the base64-encoded SHA-256 of the DER-encoded
/// SubjectPublicKeyInfo of your server's TLS leaf or intermediate certificate.
///
/// Generate with:
///   openssl s_client -connect api.openwhats.app:443 </dev/null \
///     | openssl x509 -pubkey -noout \
///     | openssl pkey -pubin -outform der \
///     | openssl dgst -sha256 -binary \
///     | base64
///
/// Usage: set APIClient to use this as its URLSession delegate.
public final class CertificatePinner: NSObject, URLSessionDelegate, @unchecked Sendable {

    public static let shared = CertificatePinner()

    /// SHA-256 hashes of trusted SPKI bytes (base64-encoded).
    /// Leave empty in debug/simulator builds to skip pinning.
    public var pinnedHashes: Set<String> = []

    private override init() {}

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // No pins configured → fall through to system TLS validation
        if pinnedHashes.isEmpty {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Default trust evaluation first
        var cfError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &cfError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Walk the cert chain looking for a pinned key
        let certs = certChain(from: serverTrust)
        for cert in certs {
            if let hash = spkiSHA256(cert), pinnedHashes.contains(hash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Certificate chain

    private func certChain(from trust: SecTrust) -> [SecCertificate] {
        if #available(iOS 15, macOS 12, *) {
            return (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        } else {
            return (0..<SecTrustGetCertificateCount(trust)).compactMap {
                SecTrustGetCertificateAtIndex(trust, $0)
            }
        }
    }

    // MARK: - SPKI SHA-256

    private func spkiSHA256(_ certificate: SecCertificate) -> String? {
        guard
            let publicKey = SecCertificateCopyKey(certificate),
            let attrs = SecKeyCopyAttributes(publicKey) as? [String: Any],
            let keyType = attrs[kSecAttrKeyType as String] as? String,
            let keySize = attrs[kSecAttrKeySizeInBits as String] as? Int,
            let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { return nil }

        let spki = spkiDER(keyData: keyData, keyType: keyType, keySize: keySize)
        let hash = SHA256.hash(data: spki)
        return Data(hash).base64EncodedString()
    }

    // Prepend the ASN.1 SPKI header for the given key type so SHA-256 matches
    // what `openssl pkey -pubin -outform der | openssl dgst -sha256` produces.
    private func spkiDER(keyData: Data, keyType: String, keySize: Int) -> Data {
        // EC P-256 SPKI header (26 bytes before the 65-byte uncompressed point)
        let ecP256Header = Data([
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
            0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
            0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
            0x42, 0x00,
        ])
        // RSA 2048 SPKI header (24 bytes before the key bytes)
        let rsa2048Header = Data([
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00,
        ])

        if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String), keySize == 256 {
            return ecP256Header + keyData
        }
        if keyType == (kSecAttrKeyTypeRSA as String), keySize == 2048 {
            return rsa2048Header + keyData
        }
        return keyData  // unsupported key type — hash won't match any pin
    }
}
