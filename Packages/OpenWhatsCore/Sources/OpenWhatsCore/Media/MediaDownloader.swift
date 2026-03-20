import Foundation

// MARK: - MediaDownloader

/// Downloads, verifies, and decrypts media attachments.
/// Maintains an in-memory LRU cache keyed by object key.
public actor MediaDownloader {

    public static let shared = MediaDownloader()
    private init() {}

    // Simple in-memory cache: objectKey → decrypted Data
    private var cache: [String: Data] = [:]
    private let maxCacheEntries = 50

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        return URLSession(configuration: cfg)
    }()

    /// Returns decrypted attachment data. Uses in-memory cache if available.
    public func download(objectKey: String, attachmentKey: AttachmentKey) async throws -> Data {
        if let cached = cache[objectKey] { return cached }

        // 1. Get pre-signed download URL
        let downloadInfo = try await APIClient.shared.requestDownloadURL(objectKey: objectKey)

        // 2. Download ciphertext from S3
        let url = URL(string: downloadInfo.downloadUrl)!
        let (ciphertext, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AttachmentError.downloadFailed(URLError(.badServerResponse))
        }

        // 3. Decrypt (also verifies HMAC)
        let plaintext = try AttachmentCrypto.decrypt(ciphertext: ciphertext, key: attachmentKey)

        // Cache result
        if cache.count >= maxCacheEntries {
            cache.removeValue(forKey: cache.keys.first!)
        }
        cache[objectKey] = plaintext

        return plaintext
    }

    public func evict(objectKey: String) {
        cache.removeValue(forKey: objectKey)
    }
}
