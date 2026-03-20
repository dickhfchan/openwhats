import Foundation

// MARK: - API Errors

public enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case rateLimited(retryAfter: Int)
    case serverError(String)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:          return "Authentication required"
        case .notFound:              return "Resource not found"
        case .rateLimited(let s):    return "Rate limited — retry after \(s)s"
        case .serverError(let m):    return m
        case .decodingError(let e):  return "Decode error: \(e)"
        case .networkError(let e):   return "Network error: \(e)"
        default:                     return "Unknown error"
        }
    }
}

// MARK: - APIClient

/// Central HTTP client for all REST API calls.
/// Automatically injects JWT and Device-ID headers.
public actor APIClient {

    public static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    var baseURL: URL = URL(string: "https://api.openwhats.app")!

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        // CertificatePinner enforces SPKI pinning in production.
        // Populate CertificatePinner.shared.pinnedHashes at app startup with your leaf cert hash.
        session = URLSession(configuration: config,
                             delegate: CertificatePinner.shared,
                             delegateQueue: nil)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Generic request

    func request<T: Decodable>(_ endpoint: String,
                                method: String = "GET",
                                body: (any Encodable)? = nil) async throws -> T {
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let account = AccountManager.shared
        if !account.jwtToken.isEmpty {
            req.setValue("Bearer \(account.jwtToken)", forHTTPHeaderField: "Authorization")
        }
        if !account.deviceID.isEmpty {
            req.setValue(account.deviceID, forHTTPHeaderField: "X-Device-ID")
        }

        if let body {
            req.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: req)
        let http = response as! HTTPURLResponse

        switch http.statusCode {
        case 200...299:
            do { return try decoder.decode(T.self, from: data) }
            catch { throw APIError.decodingError(error) }
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 429:
            let retry = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            throw APIError.rateLimited(retryAfter: retry)
        default:
            let msg = (try? decoder.decode([String: String].self, from: data))?["error"] ?? "Unknown"
            throw APIError.serverError(msg)
        }
    }

    // MARK: - Typed convenience methods

    // Auth
    public func appleAuth(identityToken: String) async throws -> AuthResponse {
        try await request("/auth/apple", method: "POST",
                          body: ["identity_token": identityToken])
    }

    // Users
    public func register(handle: String, displayName: String) async throws -> UserResponse {
        try await request("/users/register", method: "POST",
                          body: RegisterRequest(handle: handle, displayName: displayName))
    }

    public func getMe() async throws -> UserResponse {
        try await request("/users/me")
    }

    public func searchUser(handle: String) async throws -> UserResponse {
        try await request("/users/search?handle=\(handle)")
    }

    public func checkHandle(_ handle: String) async throws -> HandleCheckResponse {
        try await request("/users/handles/check?handle=\(handle)")
    }

    // Devices
    public func registerDevice(type: String, apnsToken: String?) async throws -> DeviceResponse {
        try await request("/devices/register", method: "POST",
                          body: DeviceRegisterRequest(deviceType: type, apnsToken: apnsToken))
    }

    public func listDevices() async throws -> DeviceListResponse {
        try await request("/devices")
    }

    public func deleteDevice(deviceID: String) async throws {
        try await requestEmpty("/devices/\(deviceID)", method: "DELETE")
    }

    // MARK: - No-content request (DELETE, PATCH with 204, etc.)

    private func requestEmpty(_ endpoint: String, method: String, body: (any Encodable)? = nil) async throws {
        guard let url = URL(string: endpoint, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let account = AccountManager.shared
        if !account.jwtToken.isEmpty {
            req.setValue("Bearer \(account.jwtToken)", forHTTPHeaderField: "Authorization")
        }
        if !account.deviceID.isEmpty {
            req.setValue(account.deviceID, forHTTPHeaderField: "X-Device-ID")
        }
        if let body {
            req.httpBody = try encoder.encode(body)
        }
        let (_, response) = try await session.data(for: req)
        let http = response as! HTTPURLResponse
        switch http.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:  throw APIError.serverError("HTTP \(http.statusCode)")
        }
    }

    // Keys
    public func uploadKeyBundle(_ bundle: KeyBundleRequest) async throws -> UploadResponse {
        try await request("/keys/bundle", method: "POST", body: bundle)
    }

    public func fetchPreKeyBundles(for userID: String) async throws -> PreKeyBundlesResponse {
        try await request("/keys/\(userID)")
    }

    public func replenishOTPKs(_ keys: OTPKReplenishRequest) async throws -> UploadResponse {
        try await request("/keys/one-time-prekeys", method: "POST", body: keys)
    }

    public func rotateSignedPreKey(_ spk: RotateSignedPreKeyRequest) async throws -> UploadResponse {
        try await request("/keys/signed-prekey", method: "PUT", body: spk)
    }

    public func updateAPNSToken(_ token: String) async throws {
        struct Body: Encodable { let apnsToken: String }
        try await requestEmpty("/devices/me", method: "PATCH", body: Body(apnsToken: token))
    }

    public func checkOTPKCount(for userID: String) async throws -> OTPKCountResponse {
        try await request("/keys/\(userID)/count")
    }

    // Messages
    public func sendEnvelopes(_ req: SendEnvelopesRequest) async throws -> SendEnvelopesResponse {
        try await request("/messages/send", method: "POST", body: req)
    }

    public func getPendingMessages() async throws -> PendingMessagesResponse {
        try await request("/messages/pending")
    }

    public func ackMessages(envelopeIDs: [String]) async throws -> AckResponse {
        try await request("/messages/ack", method: "POST",
                          body: ["envelope_ids": envelopeIDs])
    }

    // Calls
    public func getTURNCredentials() async throws -> TURNCredentials {
        try await request("/calls/turn-credentials")
    }

    // Media
    public func requestUploadURL(mimeType: String, sizeBytes: Int) async throws -> UploadURLResponse {
        struct Body: Encodable {
            let mimeType: String
            let sizeBytes: Int
        }
        return try await request("/media/upload-url", method: "POST",
                                 body: Body(mimeType: mimeType, sizeBytes: sizeBytes))
    }

    public func confirmUpload(objectKey: String) async throws -> ConfirmResponse {
        try await request("/media/confirm", method: "POST",
                          body: ["object_key": objectKey])
    }

    public func requestDownloadURL(objectKey: String) async throws -> DownloadURLResponse {
        try await request("/media/download-url/\(objectKey)")
    }
}

// MARK: - Request / Response types

public struct AuthResponse: Codable {
    public let token: String
    public let userId: String
    public let isNewUser: Bool
    public let isComplete: Bool
}

public struct UserResponse: Codable {
    public let userId: String
    public let handle: String
    public let displayName: String
    public let avatarUrl: String?
}

public struct HandleCheckResponse: Codable {
    public let handle: String
    public let available: Bool
}

public struct RegisterRequest: Codable {
    let handle: String
    let displayName: String
}

public struct DeviceResponse: Codable {
    public let deviceId: String
    public let deviceType: String
}

public struct DeviceRegisterRequest: Codable {
    let deviceType: String
    let apnsToken: String?
}

public struct DeviceInfo: Codable, Identifiable, Sendable {
    public var id: String { deviceId }
    public let deviceId: String
    public let deviceType: String   // "phone" or "desktop"
    public let lastSeenAt: Date?
    public let createdAt: Date
}

public struct DeviceListResponse: Codable {
    public let devices: [DeviceInfo]
}

public struct KeyBundleRequest: Codable {
    let identityKey: String         // base64url
    struct SPK: Codable {
        let keyId: Int
        let publicKey: String
        let signature: String
    }
    let signedPreKey: SPK
    struct OTPK: Codable {
        let keyId: Int
        let publicKey: String
    }
    let oneTimePreKeys: [OTPK]
}

public struct PreKeyBundlesResponse: Codable {
    struct Bundle: Codable {
        let deviceId: String
        let deviceType: String
        let identityKey: String
        let signedPreKeyId: Int
        let signedPreKey: String
        let signedPreKeySig: String
        let oneTimePreKeyId: Int?
        let oneTimePreKey: String?
    }
    let bundles: [Bundle]
}

public struct RotateSignedPreKeyRequest: Codable, Sendable {
    public let keyId: Int
    public let publicKey: String   // base64url
    public let signature: String   // base64url
    public init(keyId: Int, publicKey: String, signature: String) {
        self.keyId = keyId; self.publicKey = publicKey; self.signature = signature
    }
}

public struct OTPKReplenishRequest: Codable {
    struct Key: Codable { let keyId: Int; let publicKey: String }
    let keys: [Key]
}

public struct OTPKCountResponse: Codable {
    struct DeviceCount: Codable {
        let deviceId: String
        let count: Int
        let needsRefill: Bool
    }
    let devices: [DeviceCount]
}

public struct UploadResponse: Codable, Sendable {
    let uploaded: Int?
    let status: String?
}

public struct SendEnvelopesRequest: Codable {
    struct Envelope: Codable {
        let recipientUserId: String
        let recipientDeviceId: String
        let payload: Data
    }
    let envelopes: [Envelope]
}

public struct SendEnvelopesResponse: Codable {
    let envelopeIds: [String]
}

public struct PendingMessagesResponse: Codable {
    let envelopes: [IncomingEnvelope]
}

public struct AckResponse: Codable {
    let deleted: Int
}

public struct UploadURLResponse: Codable {
    let objectKey: String
    let uploadUrl: String
}

public struct ConfirmResponse: Codable {
    let status: String
}

public struct DownloadURLResponse: Codable {
    let downloadUrl: String
    let expiresIn: String
}
