import CryptoKit
import Foundation

/// What a license key grants, read from its signed payload (Decision 135). No email or name, and no app version: a future
/// 2.0 tells older licenses apart by `issued`. The Mac count is honour-based and never enforced.
public struct License: Equatable, Sendable {
    public enum Edition: UInt8, Sendable { case standard = 1 }
    public let id: UUID
    public let edition: Edition
    public let macs: Int
    /// The UTC day the key was issued, at midnight UTC.
    public let issued: Date
    public init(id: UUID, edition: Edition, macs: Int, issued: Date) {
        self.id = id; self.edition = edition; self.macs = macs; self.issued = issued
    }
}

/// What the key on this Mac amounts to. The trial (#595) is not a key state: it applies while the state isn't `active`.
public enum LicenseState: Equatable, Sendable {
    case none, active(License), invalid, revoked(License)
}

/// Reads a license key: `CD1-` and the RFC 4648 base32 of the 21-byte payload followed by its 64-byte Ed25519 signature.
/// The byte layout is docs/reference/license-key-format.md, which the issuing function (cachedrop-website#64) follows.
public enum LicenseKey {
    public static let prefix = "CD1-"
    static let formatVersion: UInt8 = 1
    static let payloadLength = 21, signatureLength = 64
    /// 85 bytes are exactly 136 base32 characters, with no padding and no spare bits, so each key has one spelling.
    static let encodedLength = (payloadLength + signatureLength) * 8 / 5

    /// The payload and signature of `text`, or nil when it isn't a well-formed key. Case, spaces and line breaks are
    /// ignored, so a key that was wrapped or retyped still reads.
    static func split(_ text: String) -> (payload: Data, signature: Data)? {
        let compact = text.filter { !$0.isWhitespace }.uppercased()
        guard compact.hasPrefix(prefix), compact.count == prefix.count + encodedLength,
              let bytes = Base32.decode(compact.dropFirst(prefix.count)) else { return nil }
        return (bytes.prefix(payloadLength), bytes.suffix(signatureLength))
    }

    /// The license a verified payload describes, or nil when its version, edition or Mac count isn't one this app knows.
    static func license(from payload: Data) -> License? {
        let bytes = [UInt8](payload)
        guard bytes.count == payloadLength, bytes[0] == formatVersion, let edition = License.Edition(rawValue: bytes[17]),
              bytes[18] > 0 else { return nil }
        let id = UUID(uuid: (bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                             bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15], bytes[16]))
        let days = Int(bytes[19]) << 8 | Int(bytes[20])
        return License(id: id, edition: edition, macs: Int(bytes[18]), issued: Date(timeIntervalSince1970: Double(days) * 86_400))
    }
}

/// Checks keys on the Mac against the public key built into the app; no network call (Decision 135).
public struct LicenseVerifier: Sendable {
    let publicKey: Curve25519.Signing.PublicKey?
    let revoked: Set<UUID>
    /// A nil `publicKey` (the placeholder before the owner supplies the production key) rejects every key.
    public init(publicKey: Curve25519.Signing.PublicKey?, revoked: Set<UUID>) {
        self.publicKey = publicKey; self.revoked = revoked
    }

    public func state(of key: String?) -> LicenseState {
        guard let key else { return .none }
        guard let publicKey, let (payload, signature) = LicenseKey.split(key),
              publicKey.isValidSignature(signature, for: payload), let license = LicenseKey.license(from: payload) else { return .invalid }
        return revoked.contains(license.id) ? .revoked(license) : .active(license)
    }
}

/// RFC 4648 base32, upper case, without padding.
enum Base32 {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static func decode(_ text: some StringProtocol) -> Data? {
        var bytes = Data(), buffer = 0, bits = 0
        for character in text {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5 | value) & 0xFFFF; bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8(truncatingIfNeeded: buffer >> bits)) }
        }
        return bytes
    }
}
