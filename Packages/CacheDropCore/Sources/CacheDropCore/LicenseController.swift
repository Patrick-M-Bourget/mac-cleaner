import Foundation
import Observation

/// Where the license key is kept on this Mac: the Keychain in the app, memory in tests.
@MainActor public protocol LicenseKeyStore: AnyObject {
    func read() throws -> String?
    func write(_ value: String) throws
    func remove() throws
}

/// Settings → License: the key on this Mac and what it amounts to. Activation, the check and removal are all local; no
/// network call (Decision 135).
@MainActor @Observable public final class LicenseController {
    /// A Keychain failure, said as what it is rather than as no license (Decision 62).
    public enum Notice: Sendable { case unreadable, saveFailed, removeFailed }
    public private(set) var state: LicenseState
    /// Why the last pasted key wasn't kept (`invalid` or `revoked`), until the next paste or removal.
    public private(set) var rejected: LicenseState?
    public private(set) var notice: Notice?
    @ObservationIgnored private let store: any LicenseKeyStore
    @ObservationIgnored private let verifier: LicenseVerifier

    public init(store: any LicenseKeyStore, verifier: LicenseVerifier = .production) {
        self.store = store; self.verifier = verifier
        do { state = verifier.state(of: try store.read()) } catch { state = .none; notice = .unreadable }
    }

    /// Checks `text` and keeps it only when it is an active license; returns whether it was kept.
    @discardableResult public func activate(_ text: String) -> Bool {
        let checked = verifier.state(of: text)
        guard case .active = checked else { rejected = checked; return false }
        rejected = nil
        do { try store.write(LicenseKey.canonical(text)) } catch { notice = .saveFailed; return false }
        state = checked; notice = nil
        return true
    }

    /// Remove from this Mac: forgets the key here. The license itself is unchanged.
    public func remove() {
        rejected = nil
        do { try store.remove() } catch { notice = .removeFailed; return }
        state = .none; notice = nil
    }
}

extension LicenseState {
    /// Settings → License's line for this state (Decision 92). #595 shows the trial left in place of `none`'s line.
    public var summary: String {
        switch self {
        case .none: "No license on this Mac"
        case .active(let license): "Licensed, up to \(license.macs) \(license.macs == 1 ? "Mac" : "Macs")"
        case .invalid: "License key not valid"
        case .revoked: "License key revoked"
        }
    }
}

extension LicenseController.Notice {
    public var message: String {
        switch self {
        case .unreadable: "Couldn’t read the license key"
        case .saveFailed: "License key wasn’t saved"
        case .removeFailed: "License key wasn’t removed"
        }
    }
}
