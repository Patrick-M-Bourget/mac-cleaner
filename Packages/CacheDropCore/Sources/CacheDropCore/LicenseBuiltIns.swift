import CryptoKit
import Foundation

/// The public key license keys are checked against. Only the public half is in the app; the production private key never
/// enters the repository (Decision 135). Until the owner supplies the production public key (#593) this holds a
/// placeholder that rejects every key, and `scripts/check-release.sh` refuses a release that has gating on with it.
public enum LicensePublicKey {
    /// The production public key, 32 raw bytes in base64; `placeholder` until the owner replaces it (docs/RELEASING.md).
    static let productionBase64 = placeholder
    /// Marks the placeholder. check-release.sh looks for this text in the built app, so keep it verbatim.
    static let placeholder = "CacheDrop license public key placeholder: rejects every key"

    public static var production: Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: productionBase64) else { return nil }
        return try? .init(rawRepresentation: raw)
    }
}

/// License IDs refunded, charged back or leaked, compiled into each release. A revoked key keeps working on a Mac until
/// it installs a release that lists it; there is no online check (Decision 135). docs/RELEASING.md says how to add one.
public enum LicenseRevocations {
    public static let ids: Set<UUID> = [
    ]
}

extension LicenseVerifier {
    /// The verifier the app uses: the built-in public key and revocation list.
    public static var production: LicenseVerifier { LicenseVerifier(publicKey: LicensePublicKey.production, revoked: LicenseRevocations.ids) }
}
