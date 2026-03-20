import XCTest
import CryptoKit
@testable import OpenWhatsCore

final class SignalProtocolTests: XCTestCase {

    // MARK: - X3DH Tests

    func testX3DHKeyAgreementProducesSameSecret() throws {
        // Alice's keys
        let aliceIdentity = IdentityKeyPair()

        // Bob's keys
        let bobIdentity = IdentityKeyPair()
        let bobSignedPreKey = SignedPreKeyPair()
        let bobSigning = SigningKeyPair()
        let signature = try bobSigning.sign(bobSignedPreKey.publicKeyData)
        let bobOTPK = OneTimePreKeyPair()

        // Alice fetches Bob's bundle
        let bundle = try PreKeyBundle(
            deviceID: "bob-device-1",
            deviceType: "phone",
            identityKeyData: bobIdentity.publicKeyData,
            signedPreKeyID: 1,
            signedPreKeyData: bobSignedPreKey.publicKeyData,
            signedPreKeySig: signature,
            oneTimePreKeyID: 1,
            oneTimePreKeyData: bobOTPK.publicKeyData
        )

        // Alice computes sender SK
        let senderResult = try X3DH.senderKeyAgreement(
            senderIdentityKey: aliceIdentity,
            recipientBundle: bundle
        )

        // Bob computes receiver SK
        let receiverSK = try X3DH.receiverKeyAgreement(
            receiverIdentityKey: bobIdentity,
            receiverSignedPreKey: bobSignedPreKey,
            receiverOneTimePreKey: bobOTPK,
            senderIdentityKeyData: aliceIdentity.publicKeyData,
            senderEphemeralKeyData: senderResult.ephemeralKeyData
        )

        XCTAssertEqual(senderResult.sharedSecret, receiverSK)
        XCTAssertEqual(senderResult.sharedSecret.count, 32)
    }

    func testX3DHWithoutOTPKStillProducesSameSecret() throws {
        let aliceIdentity = IdentityKeyPair()
        let bobIdentity = IdentityKeyPair()
        let bobSPK = SignedPreKeyPair()
        let bobSigning = SigningKeyPair()
        let sig = try bobSigning.sign(bobSPK.publicKeyData)

        let bundle = try PreKeyBundle(
            deviceID: "bob-device-1",
            deviceType: "phone",
            identityKeyData: bobIdentity.publicKeyData,
            signedPreKeyID: 1,
            signedPreKeyData: bobSPK.publicKeyData,
            signedPreKeySig: sig,
            oneTimePreKeyID: nil,
            oneTimePreKeyData: nil
        )

        let senderResult = try X3DH.senderKeyAgreement(senderIdentityKey: aliceIdentity, recipientBundle: bundle)
        let receiverSK = try X3DH.receiverKeyAgreement(
            receiverIdentityKey: bobIdentity,
            receiverSignedPreKey: bobSPK,
            receiverOneTimePreKey: nil,
            senderIdentityKeyData: aliceIdentity.publicKeyData,
            senderEphemeralKeyData: senderResult.ephemeralKeyData
        )

        XCTAssertEqual(senderResult.sharedSecret, receiverSK)
    }

    // MARK: - Double Ratchet Tests

    func testRoundTripEncryptDecrypt() throws {
        let (aliceSession, bobSession) = try makeTestSessions()
        var alice = aliceSession
        var bob = bobSession

        let original = Data("Hello, Bob! This is a secret message.".utf8)
        let result = try DoubleRatchet.encrypt(session: &alice, plaintext: original)
        let decrypted = try DoubleRatchet.decrypt(
            session: &bob,
            header: result.header,
            ciphertext: result.ciphertext
        )

        XCTAssertEqual(decrypted, original)
    }

    func testMultipleMessagesAliceToBob() throws {
        let (aliceSession, bobSession) = try makeTestSessions()
        var alice = aliceSession
        var bob = bobSession

        let messages = ["Hello", "How are you?", "Great to talk!", "Goodbye"]
        for text in messages {
            let plain = Data(text.utf8)
            let result = try DoubleRatchet.encrypt(session: &alice, plaintext: plain)
            let decrypted = try DoubleRatchet.decrypt(session: &bob, header: result.header, ciphertext: result.ciphertext)
            XCTAssertEqual(decrypted, plain, "Failed for message: \(text)")
        }
    }

    func testBidirectionalConversation() throws {
        let (aliceSession, bobSession) = try makeTestSessions()
        var alice = aliceSession
        var bob = bobSession

        // Alice sends first
        let m1 = Data("Hi Bob".utf8)
        let r1 = try DoubleRatchet.encrypt(session: &alice, plaintext: m1)
        XCTAssertEqual(try DoubleRatchet.decrypt(session: &bob, header: r1.header, ciphertext: r1.ciphertext), m1)

        // Bob replies
        let m2 = Data("Hi Alice".utf8)
        let r2 = try DoubleRatchet.encrypt(session: &bob, plaintext: m2)
        XCTAssertEqual(try DoubleRatchet.decrypt(session: &alice, header: r2.header, ciphertext: r2.ciphertext), m2)

        // Alice sends again
        let m3 = Data("Nice to talk!".utf8)
        let r3 = try DoubleRatchet.encrypt(session: &alice, plaintext: m3)
        XCTAssertEqual(try DoubleRatchet.decrypt(session: &bob, header: r3.header, ciphertext: r3.ciphertext), m3)
    }

    func testOutOfOrderDelivery() throws {
        let (aliceSession, bobSession) = try makeTestSessions()
        var alice = aliceSession
        var bob = bobSession

        // Alice sends 3 messages
        let m1 = Data("First".utf8)
        let m2 = Data("Second".utf8)
        let m3 = Data("Third".utf8)

        let r1 = try DoubleRatchet.encrypt(session: &alice, plaintext: m1)
        let r2 = try DoubleRatchet.encrypt(session: &alice, plaintext: m2)
        let r3 = try DoubleRatchet.encrypt(session: &alice, plaintext: m3)

        // Bob receives out of order: 3, 1, 2
        XCTAssertEqual(try DoubleRatchet.decrypt(session: &bob, header: r3.header, ciphertext: r3.ciphertext), m3)
        XCTAssertEqual(try DoubleRatchet.decrypt(session: &bob, header: r1.header, ciphertext: r1.ciphertext), m1)
        XCTAssertEqual(try DoubleRatchet.decrypt(session: &bob, header: r2.header, ciphertext: r2.ciphertext), m2)
    }

    func testSessionSerializationRoundTrip() throws {
        let (aliceSession, bobSession) = try makeTestSessions()
        var alice = aliceSession
        var bob = bobSession

        // Exchange one message so both sessions advance
        let m1 = Data("First message".utf8)
        let r1 = try DoubleRatchet.encrypt(session: &alice, plaintext: m1)
        _ = try DoubleRatchet.decrypt(session: &bob, header: r1.header, ciphertext: r1.ciphertext)

        // Serialize Bob's session, restore it, verify it can still decrypt
        let encoded = try JSONEncoder().encode(bob)
        var restoredBob = try JSONDecoder().decode(RatchetSession.self, from: encoded)

        let m2 = Data("Second message after restore".utf8)
        let r2 = try DoubleRatchet.encrypt(session: &alice, plaintext: m2)
        let decrypted = try DoubleRatchet.decrypt(session: &restoredBob, header: r2.header, ciphertext: r2.ciphertext)
        XCTAssertEqual(decrypted, m2)
    }

    // MARK: - Safety Numbers

    func testSafetyNumbersAreSymmetric() throws {
        let aliceID = "alice-uuid-1234"
        let aliceKey = IdentityKeyPair().publicKeyData
        let bobID = "bob-uuid-5678"
        let bobKey = IdentityKeyPair().publicKeyData

        let aliceSees = SafetyNumbers.compute(
            localUserID: aliceID, localIdentityKey: aliceKey,
            remoteUserID: bobID, remoteIdentityKey: bobKey
        )
        let bobSees = SafetyNumbers.compute(
            localUserID: bobID, localIdentityKey: bobKey,
            remoteUserID: aliceID, remoteIdentityKey: aliceKey
        )

        XCTAssertEqual(aliceSees, bobSees)
        // 12 groups of 5 digits separated by spaces = 60 digits + 11 spaces = 71 chars
        XCTAssertEqual(aliceSees.count, 71)
    }

    func testDifferentUsersDifferentSafetyNumbers() throws {
        let key = IdentityKeyPair().publicKeyData
        let n1 = SafetyNumbers.compute(localUserID: "user-1", localIdentityKey: key,
                                        remoteUserID: "user-2", remoteIdentityKey: key)
        let n2 = SafetyNumbers.compute(localUserID: "user-1", localIdentityKey: key,
                                        remoteUserID: "user-3", remoteIdentityKey: key)
        XCTAssertNotEqual(n1, n2)
    }

    // MARK: - Helpers

    private func makeTestSessions() throws -> (RatchetSession, RatchetSession) {
        let aliceIdentity = IdentityKeyPair()
        let bobIdentity = IdentityKeyPair()
        let bobSPK = SignedPreKeyPair()
        let bobSigning = SigningKeyPair()
        let sig = try bobSigning.sign(bobSPK.publicKeyData)

        let bundle = try PreKeyBundle(
            deviceID: "bob", deviceType: "phone",
            identityKeyData: bobIdentity.publicKeyData,
            signedPreKeyID: 1,
            signedPreKeyData: bobSPK.publicKeyData,
            signedPreKeySig: sig,
            oneTimePreKeyID: nil, oneTimePreKeyData: nil
        )

        let senderResult = try X3DH.senderKeyAgreement(senderIdentityKey: aliceIdentity, recipientBundle: bundle)
        let receiverSK = try X3DH.receiverKeyAgreement(
            receiverIdentityKey: bobIdentity,
            receiverSignedPreKey: bobSPK,
            receiverOneTimePreKey: nil,
            senderIdentityKeyData: aliceIdentity.publicKeyData,
            senderEphemeralKeyData: senderResult.ephemeralKeyData
        )

        let aliceSession = try DoubleRatchet.initSender(
            sharedSecret: senderResult.sharedSecret,
            recipientRatchetKey: bobSPK.publicKeyData,
            remoteIdentityKey: bobIdentity.publicKeyData
        )
        let bobSession = DoubleRatchet.initReceiver(
            sharedSecret: receiverSK,
            ourRatchetKeyPair: bobSPK,
            remoteIdentityKey: aliceIdentity.publicKeyData
        )

        return (aliceSession, bobSession)
    }
}
