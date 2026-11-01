import CacheDropCore
import CryptoKit
import SwiftUI

/// Settings → License (#594, Decision 136): paste a key, see what it amounts to, remove it from this Mac. Everything is
/// checked on the Mac; nothing here reaches the network. #595 puts the trial left on the first line while no key is active.
struct LicenseSettings: View {
    let license: LicenseController
    @State private var pasted = ""
    var body: some View {
        Section {
            Text(license.state.summary).accessibilityIdentifier("licenseState")
            if license.state == .none {
                TextField("License key", text: $pasted, prompt: Text("CD1-…"))
                    .onSubmit(activate).accessibilityIdentifier("licenseKeyField")
                Button("Activate", action: activate).buttonStyle(.link)
                    .disabled(pasted.allSatisfy(\.isWhitespace)).accessibilityIdentifier("licenseActivate")
            } else {
                Button("Remove from this Mac") { license.remove() }.buttonStyle(.link).accessibilityIdentifier("licenseRemove")
            }
            if let rejected = license.rejected {
                Text(rejected.summary).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("licenseRejected")
            }
            if let notice = license.notice {
                Text(notice.message).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("licenseNotice")
            }
        } header: {
            Text("License")
        }
    }
    private func activate() {
        if license.activate(pasted) { pasted = "" }
    }
}

extension LicenseController {
    /// The app's license: the Keychain and the built-in public key. A disposable test run keeps its key in memory, never
    /// in the Keychain, and may trust the test public key (`CACHEDROP_TEST_LICENSE_PUBLIC_KEY`, hex) so a journey can
    /// activate the format doc's test vector.
    static func forApp() -> LicenseController {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            let hex = LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_LICENSE_PUBLIC_KEY"] ?? ""
            let raw = Data(stride(from: 0, to: hex.count - 1, by: 2).compactMap { UInt8(hex.dropFirst($0).prefix(2), radix: 16) })
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
            return LicenseController(store: DisposableLicenseKeyStore(),
                                     verifier: key.map { LicenseVerifier(publicKey: $0, revoked: LicenseRevocations.ids) } ?? .production)
        }
        #endif
        return LicenseController(store: KeychainLicenseKeyStore())
    }
}

#if DEBUG
/// A test run's license key, in memory for that launch only.
@MainActor private final class DisposableLicenseKeyStore: LicenseKeyStore {
    private var key: String?
    func read() throws -> String? { key }
    func write(_ value: String) throws { key = value }
    func remove() throws { key = nil }
}
#endif
