import AppKit
import CacheDropCore
import CryptoKit
import SwiftUI

/// Settings › License (#594, Decision 136): paste a key, see what it amounts to, remove it from this Mac. Everything is
/// checked on the Mac; nothing here reaches the network. While the trial applies (#595, Decision 137) its first line says
/// what the trial has left, with Buy and the price below the field.
struct LicenseSettings: View {
    let license: LicenseController
    let trial: TrialController
    @State private var pasted = ""
    var body: some View {
        Section {
            stateLines
            if license.state == .none {
                TextField("License key", text: $pasted, prompt: Text("CD1-…"))
                    .onSubmit(activate).accessibilityIdentifier("licenseKeyField")
                Button("Activate", action: activate).buttonStyle(.link)
                    .disabled(pasted.allSatisfy(\.isWhitespace)).accessibilityIdentifier("licenseActivate")
            } else {
                Button("Remove from this Mac") { license.remove() }.buttonStyle(.link).accessibilityIdentifier("licenseRemove")
            }
            if let rejected = license.rejected { caption(rejected.summary, "licenseRejected") }
            if let notice = license.notice { caption(notice.message, "licenseNotice") }
            if trialLine != nil {
                HStack(spacing: CacheDropDesign.Space.sm) {
                    Button("Buy", action: LicensePrice.openBuy).buttonStyle(.link).accessibilityIdentifier("licenseBuy")
                    LicensePriceText()
                }
            }
            if let notice = trial.notice { caption(notice.message, "trialNotice") }
        } header: {
            Text("License")
        }
    }
    private var trialLine: String? { trial.allowance(for: license.state).settingsLine }
    /// The first line: the trial left while it applies, else the key's state. A kept key that isn't active says so below it.
    @ViewBuilder private var stateLines: some View {
        if let trialLine {
            Text(trialLine).accessibilityIdentifier("licenseState")
            if license.state != .none { caption(license.state.summary, "licenseKeyState") }
        } else {
            Text(license.state.summary).accessibilityIdentifier("licenseState")
        }
    }
    private func caption(_ text: String, _ identifier: String) -> some View {
        Text(text).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).accessibilityIdentifier(identifier)
    }
    private func activate() {
        if license.activate(pasted) { pasted = "" }
    }
}

/// The price beside Buy: 29.99 struck through, then 19.99, in the Mac's region currency (Decision 135).
struct LicensePriceText: View {
    private let price = LicensePrice.text()
    var body: some View {
        Text("\(Text(price.was).strikethrough()) \(price.now)").foregroundStyle(.secondary)
            .accessibilityLabel(price.now + ", was " + price.was).accessibilityIdentifier("licensePrice")
    }
}

extension LicensePrice {
    /// Buy: the website forwards to the checkout with the promotion code, so the app holds only this link.
    @MainActor static func openBuy() { NSWorkspace.shared.open(buyURL) }
}

/// The review sheet's trial line and offer (Decision 137): what the trial has left against the plan, and over the cap
/// Enter license and Buy in the footer, with Clean up unavailable until the plan fits or a license is active.
struct TrialReviewGate {
    let review: CatalogReview?
    let held: ReviewHeldItems?
    let catalog: Catalog
    @MainActor private var allowance: CleanupAllowance { AppLifecycleController.shared.cleanupAllowance }
    private var dryRun: Bool { review?.approval.dryRun ?? false }
    /// What Clean up will act on now: a row a Quit freed counts, one still skipped doesn't.
    private var plan: Int64 {
        review.map { $0.approval.trialBytes(skipping: Set((held?.refusals ?? $0.refusals).keys), catalog: catalog) } ?? 0
    }
    @MainActor var fits: Bool { allowance.permits(plan, dryRun: dryRun) }
    @MainActor @ViewBuilder var line: some View {
        if let text = allowance.reviewLine(plan: plan, dryRun: dryRun) {
            StatusRow(text: text, symbol: fits ? "info.circle" : "exclamationmark.circle", role: fits ? .neutral : .caution, identifier: "reviewTrial")
        }
    }
}

/// Over the cap: the review sheet footer's Enter license (Settings, where the License section takes a key) and Buy.
struct TrialOfferButtons: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button("Enter license") { openSettings() }.accessibilityIdentifier("reviewEnterLicense")
        Button(action: LicensePrice.openBuy) { HStack(spacing: CacheDropDesign.Space.xs) { Text("Buy"); LicensePriceText() } }
            .accessibilityIdentifier("reviewBuy")
    }
}

extension AppLifecycleController {
    /// What Clean up may free now: the trial's rules against the license on this Mac.
    var cleanupAllowance: CleanupAllowance { trial.allowance(for: license.state) }
}

/// Gating is off unless the app is built with the Swift condition `LICENSE_GATING` (Decision 137; check-release.sh reads
/// that name). A disposable Debug test run may turn it on with `CACHEDROP_TEST_LICENSE_GATING=1`; the build setting stays off.
enum LicenseGating {
    static var isOn: Bool {
        #if LICENSE_GATING
        return true
        #else
        #if DEBUG
        if LocalStateLocation.isDisposableTest, LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_LICENSE_GATING"] == "1" { return true }
        #endif
        return false
        #endif
    }
}

extension TrialController {
    /// The app's trial: its own Keychain item, read only while gating is on. A disposable test run keeps the count in
    /// memory, never the Keychain, starting from `CACHEDROP_TEST_TRIAL_USED` bytes so a journey can reach the cap.
    static func forApp() -> TrialController {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            let used = LocalStateLocation.fixtureEnvironment["CACHEDROP_TEST_TRIAL_USED"].flatMap { Int64($0) }
            return TrialController(store: DisposableTrialStore(used), gating: LicenseGating.isOn)
        }
        #endif
        return TrialController(store: KeychainTrialStore(), gating: LicenseGating.isOn)
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
/// A test run's trial count, in memory for that launch only.
@MainActor private final class DisposableTrialStore: TrialStore {
    private var used: Int64?
    init(_ used: Int64?) { self.used = used }
    func read() throws -> Int64? { used }
    func write(_ value: Int64) throws { used = value }
}
#endif
