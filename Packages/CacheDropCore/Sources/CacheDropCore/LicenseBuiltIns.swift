import CryptoKit
import Foundation

/// The public key license keys are checked against. Only the public half is in the app; the production private key never
/// enters the repository (Decision 135). The production key arrived with #652 (2026-11-02). `scripts/check-release.sh`
/// refuses a gated release whose binary still holds #594's placeholder text, "CacheDrop license public key placeholder".
public enum LicensePublicKey {
    /// The production public key, 32 raw bytes in base64 (#652, #653). Every license ever sold is checked against it.
    static let productionBase64 = "hyBpRb4zRvBKKP/vwMcklOlN33k4IpMGqTqYKisCn8M="

    public static var production: Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: productionBase64) else { return nil }
        return try? .init(rawRepresentation: raw)
    }
}

/// License IDs refunded, charged back or leaked, compiled into each release. A revoked key keeps working on a Mac until
/// it installs a release that lists it; there is no online check (Decision 135). docs/RELEASING.md says how to add one.
public enum LicenseRevocations {
    public static let ids: Set<UUID> = [
        UUID(uuidString: "246b4873-8ea9-418d-a181-454be5450d12")!, // refunded: the first live test purchase, 2026-11-02 (#652)
    ]
}

extension LicenseVerifier {
    /// The verifier the app uses: the built-in public key and revocation list.
    public static var production: LicenseVerifier { LicenseVerifier(publicKey: LicensePublicKey.production, revoked: LicenseRevocations.ids) }
}
