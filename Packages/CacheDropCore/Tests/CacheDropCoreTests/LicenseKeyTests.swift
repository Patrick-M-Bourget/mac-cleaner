import CryptoKit
import Foundation
import Testing
import CacheDropCore

/// The TEST key pair of docs/reference/license-key-format.md. Its private half signs test keys only: it is not, and never
/// becomes, the production key, whose private half never enters the repository (#594, Decision 135).
enum LicenseTestKeyPair {
    static let testOnlyPrivateKeySeed = "8ad278073221015096d53c67edfe8c6adf17680b519f6d7e1febd21f875ae5ae"
    static let publicKey = "281edbf56bcb31e08ce7365ddfc3c2b7e48543b62e182a97f68c5dbd359100ea"
    static var signingKey: Curve25519.Signing.PrivateKey { try! .init(rawRepresentation: hex(testOnlyPrivateKeySeed)) }
    static var verifyingKey: Curve25519.Signing.PublicKey { try! .init(rawRepresentation: hex(publicKey)) }
    /// The format doc's test vector, signed by the issuing function's Web Crypto code with the test private key.
    static let vector = "CD1-AFPQYKUOHMOUY342PYWUXDA6N4YACA2RCZNANLQOLOVBPE7YY2TQLLQHQYCN2NRSAPS25JC6ZXJASXVXWQY6FRAPPNOSR6XEHBQHV2WWO7ZYV6VXQL3AAIERS5UY3GQNOF2UIWIJ"
    static let vectorID = UUID(uuidString: "5f0c2a8e-3b1d-4c6f-9a7e-2d4b8c1e6f30")!
    static func hex(_ text: String) -> Data {
        Data(stride(from: 0, to: text.count, by: 2).map { UInt8(text.dropFirst($0).prefix(2), radix: 16)! })
    }
}

private func day(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T00:00:00Z")! }

@Test func theTestVectorVerifiesAsAStandardLicenseForThreeMacs() {
    let verifier = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [])
    let license = License(id: LicenseTestKeyPair.vectorID, edition: .standard, macs: 3, issued: day("2026-11-01"))
    #expect(verifier.state(of: LicenseTestKeyPair.vector) == .active(license))
}

private let testVerifier = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [])

/// Changing any one byte of the key, in its payload or its signature, makes it invalid.
@Test func aKeyWithAnyByteChangedIsInvalid() throws {
    let bytes = try #require(LicenseKeyTesting.bytes(of: LicenseTestKeyPair.vector))
    #expect(bytes.count == 85)
    for index in bytes.indices {
        var changed = bytes; changed[index] ^= 0x01
        #expect(testVerifier.state(of: LicenseKeyTesting.key(changed)) == .invalid, "byte \(index)")
    }
}

/// Re-encodes keys for tests, with the same RFC 4648 base32 the format doc uses.
enum LicenseKeyTesting {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static func key(_ bytes: [UInt8]) -> String {
        var out = "CD1-", buffer = 0, bits = 0
        for byte in bytes {
            buffer = (buffer << 8 | Int(byte)) & 0xFFFF; bits += 8
            while bits >= 5 { bits -= 5; out.append(alphabet[(buffer >> bits) & 31]) }
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }
    static func bytes(of key: String) -> [UInt8]? {
        var bytes: [UInt8] = [], buffer = 0, bits = 0
        for character in key.dropFirst(4) {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5 | value) & 0xFFFF; bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8(truncatingIfNeeded: buffer >> bits)) }
        }
        return bytes
    }
    /// A key for `payload`, signed now with the test private key.
    static func signed(_ payload: [UInt8]) throws -> String {
        key(payload + [UInt8](try LicenseTestKeyPair.signingKey.signature(for: Data(payload))))
    }
}

/// Only the one canonical spelling's bytes read: a key with a character added or dropped is invalid, never trimmed.
@Test func aKeyWithACharacterAddedOrDroppedIsInvalid() {
    #expect(testVerifier.state(of: LicenseTestKeyPair.vector + "A") == .invalid)
    #expect(testVerifier.state(of: LicenseTestKeyPair.vector + "AA") == .invalid)
    #expect(testVerifier.state(of: String(LicenseTestKeyPair.vector.dropLast())) == .invalid)
}

/// A pasted key may be lower case, wrapped over lines or padded with spaces, as email and retyping leave it.
@Test func aWrappedOrLowerCaseKeyStillReads() {
    let key = LicenseTestKeyPair.vector
    let wrapped = "  " + key.prefix(70) + "\n" + key.dropFirst(70) + " \n"
    #expect(testVerifier.state(of: wrapped) == testVerifier.state(of: key))
    #expect(testVerifier.state(of: key.lowercased()) == testVerifier.state(of: key))
}

/// No key is `none`; anything that isn't a key signed by the built-in public key is `invalid`.
@Test func noKeyIsNoneAndAnythingElseIsInvalid() {
    #expect(testVerifier.state(of: nil) == .none)
    for text in ["", "hello", "CD1-", String(LicenseTestKeyPair.vector.dropFirst(4)), "CD2-" + LicenseTestKeyPair.vector.dropFirst(4),
                 "CD1-" + String(repeating: "1", count: 136)] {
        #expect(testVerifier.state(of: text) == .invalid, "\(text)")
    }
    let otherSigner = Curve25519.Signing.PrivateKey().publicKey
    #expect(LicenseVerifier(publicKey: otherSigner, revoked: []).state(of: LicenseTestKeyPair.vector) == .invalid)
}

/// Until the owner supplies the production public key, the app's placeholder rejects every key, the test vector included.
@Test func thePlaceholderPublicKeyRejectsEveryKey() {
    #expect(LicenseVerifier(publicKey: nil, revoked: []).state(of: LicenseTestKeyPair.vector) == .invalid)
    #expect(LicensePublicKey.production == nil)
    #expect(LicenseVerifier.production.state(of: LicenseTestKeyPair.vector) == .invalid)
}

private func payload(version: UInt8 = 1, id: UUID = LicenseTestKeyPair.vectorID, edition: UInt8 = 1, macs: UInt8 = 3, days: UInt16 = 20758) -> [UInt8] {
    let u = id.uuid
    return [version, u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15, edition, macs,
            UInt8(days >> 8), UInt8(days & 0xFF)]
}

/// A correctly signed key whose format version, edition or Mac count this app doesn't know is still invalid.
@Test func aSignedKeyThisAppCannotReadIsInvalid() throws {
    #expect(testVerifier.state(of: try LicenseKeyTesting.signed(payload())) == testVerifier.state(of: LicenseTestKeyPair.vector))
    for unknown in [payload(version: 2), payload(version: 0), payload(edition: 2), payload(edition: 0), payload(macs: 0)] {
        #expect(testVerifier.state(of: try LicenseKeyTesting.signed(unknown)) == .invalid, "\(unknown)")
    }
}

/// A key on the revocation list reads as revoked, with what it was; other keys stay active.
@Test func aKeyOnTheRevocationListIsRevoked() throws {
    let verifier = LicenseVerifier(publicKey: LicenseTestKeyPair.verifyingKey, revoked: [LicenseTestKeyPair.vectorID])
    guard case .active(let license) = testVerifier.state(of: LicenseTestKeyPair.vector) else { Issue.record("not active"); return }
    #expect(verifier.state(of: LicenseTestKeyPair.vector) == .revoked(license))
    let other = try LicenseKeyTesting.signed(payload(id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!, macs: 5))
    guard case .active(let five) = verifier.state(of: other) else { Issue.record("other not active"); return }
    #expect(five.macs == 5)
}
