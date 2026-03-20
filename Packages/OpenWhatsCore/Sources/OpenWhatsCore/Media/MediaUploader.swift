import Foundation

// MARK: - MediaUploader

/// Handles the full attachment upload flow:
/// 1. Request a pre-signed S3 PUT URL from the server.
/// 2. Upload the encrypted blob directly to S3.
/// 3. Confirm upload with the server.
/// Returns the committed object key.
public actor MediaUploader {

    public static let shared = MediaUploader()
    private init() {}

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        return URLSession(configuration: cfg)
    }()

    /// Encrypts `data`, uploads to S3, confirms with server. Returns (objectKey, attachmentKey).
    public func upload(data: Data, mimeType: String) async throws -> (objectKey: String, key: AttachmentKey) {
        // 1. Encrypt
        let encrypted = try AttachmentCrypto.encrypt(data: data, mimeType: mimeType)

        // 2. Get pre-signed PUT URL
        let uploadInfo = try await APIClient.shared.requestUploadURL(
            mimeType: mimeType,
            sizeBytes: encrypted.ciphertext.count
        )

        // 3. Upload directly to S3
        var s3Req = URLRequest(url: URL(string: uploadInfo.uploadUrl)!)
        s3Req.httpMethod = "PUT"
        s3Req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        s3Req.httpBody = encrypted.ciphertext

        let (_, response) = try await session.data(for: s3Req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MediaUploadError.s3UploadFailed
        }

        // 4. Confirm with server
        try await APIClient.shared.confirmUpload(objectKey: uploadInfo.objectKey)

        return (uploadInfo.objectKey, encrypted.key)
    }
}

// MARK: - MediaUploadError

public enum MediaUploadError: Error, LocalizedError {
    case s3UploadFailed

    public var errorDescription: String? {
        "S3 upload failed"
    }
}
