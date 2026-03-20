import Foundation

/// Handles periodic Signal Protocol key material rotation:
///   - Signed Pre-Key (SPK): rotated every 7 days via `POST /keys/bundle`
///   - One-Time Pre-Keys (OTPKs): replenished when server count falls below threshold
///
/// Call `startPeriodicRotation()` on app launch / after authentication.
@MainActor
public final class KeyRotationManager {

    public static let shared = KeyRotationManager()

    private let spkRotationInterval: TimeInterval = 7 * 24 * 3600 // 7 days
    private let otpkBatchSize     = 50
    private let otpkRefillThreshold = 10
    private let lastRotationKey   = "spk_last_rotation_ts"

    private init() {}

    // MARK: - Entry point

    /// Kick off background checks. Call on every app launch after auth completes.
    public func startPeriodicRotation() {
        Task { await checkAndRotate() }
    }

    // MARK: - Rotation checks

    private func checkAndRotate() async {
        await checkSPK()
        await checkOTPKs()
    }

    // MARK: - Signed Pre-Key rotation

    private func checkSPK() async {
        let lastRotation = UserDefaults.standard.double(forKey: lastRotationKey)
        let elapsed = Date().timeIntervalSince1970 - lastRotation
        guard elapsed >= spkRotationInterval else { return }
        await rotateSPK()
    }

    private func rotateSPK() async {
        do {
            // Use timestamp as a 24-bit key ID (wraps every ~194 days, fine for SPK rotation)
            let newID = Int(Date().timeIntervalSince1970) & 0x00_FF_FF_FF
            let (spkPair, signature) = try KeyStore.shared.generateSignedPreKey(id: newID)

            let req = RotateSignedPreKeyRequest(
                keyId: newID,
                publicKey: spkPair.publicKeyData.base64URLEncoded(),
                signature: signature.base64URLEncoded()
            )
            _ = try await APIClient.shared.rotateSignedPreKey(req)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRotationKey)
            print("[KeyRotation] SPK rotated to id=\(newID)")
        } catch {
            print("[KeyRotation] SPK rotation failed: \(error)")
        }
    }

    // MARK: - One-Time Pre-Key replenishment

    private func checkOTPKs() async {
        do {
            let myID = AccountManager.shared.userID
            guard !myID.isEmpty else { return }
            let resp = try await APIClient.shared.checkOTPKCount(for: myID)
            for device in resp.devices where device.needsRefill {
                await replenishOTPKs(currentCount: device.count)
            }
        } catch {
            print("[KeyRotation] OTPK count check failed: \(error)")
        }
    }

    private func replenishOTPKs(currentCount: Int) async {
        do {
            let startID = currentCount + 1
            let pairs = try KeyStore.shared.generateOneTimePreKeys(
                startingID: startID,
                count: otpkBatchSize
            )
            let keys = pairs.map {
                OTPKReplenishRequest.Key(
                    keyId: $0.id,
                    publicKey: $0.pair.publicKeyData.base64URLEncoded()
                )
            }
            _ = try await APIClient.shared.replenishOTPKs(OTPKReplenishRequest(keys: keys))
            print("[KeyRotation] Replenished \(keys.count) OTPKs starting at id=\(startID)")
        } catch {
            print("[KeyRotation] OTPK replenishment failed: \(error)")
        }
    }
}

// MARK: - Data base64url helper

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
