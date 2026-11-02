import Foundation
import Observation

/// Where the trial's count is kept on this Mac: its own Keychain item in the app, so a reinstall or Reset in Saved data
/// keeps it; memory in tests.
@MainActor public protocol TrialStore: AnyObject {
    func read() throws -> Int64?
    func write(_ value: Int64) throws
}

/// The trial on this Mac (Decision 137): how much Clean up has freed, counted from zero once gating is on. With gating
/// off it reads and writes nothing, so nothing changes.
@MainActor @Observable public final class TrialController {
    /// A Keychain failure, said as what it is (Decision 62). The count goes on in memory for this launch.
    public enum Notice: Sendable { case unreadable, saveFailed }
    public let gating: Bool
    public private(set) var used: Int64 = 0
    public private(set) var notice: Notice?
    @ObservationIgnored private let store: any TrialStore
    /// False while the stored count couldn't be read: `used` then holds only this launch's runs, and saving it would
    /// overwrite a larger stored count, which would start the trial over.
    @ObservationIgnored private var loaded = false

    public init(store: any TrialStore, gating: Bool) {
        self.store = store; self.gating = gating
        guard gating else { return }
        do { used = max(0, try store.read() ?? 0); loaded = true } catch { notice = .unreadable }
    }

    public func allowance(for license: LicenseState) -> CleanupAllowance {
        CleanupAllowance(gating: gating, license: license, used: used)
    }

    /// Adds what a finished run removed or moved to the Trash.
    public func record(_ result: CatalogExecutionResult, of approval: CatalogApproval, catalog: Catalog) {
        let freed = result.trialBytes(of: approval, catalog: catalog)
        guard gating, freed > 0 else { return }
        used += freed
        if !loaded {
            // Read again before saving, and add this launch's runs to what's stored; while it still can't be read, save nothing.
            guard let stored = try? store.read() else { return }
            used += max(0, stored ?? 0); loaded = true
        }
        do { try store.write(used); notice = nil } catch { notice = .saveFailed }
    }
}

extension TrialController.Notice {
    public var message: String {
        switch self {
        case .unreadable: "Couldn’t read the free trial"
        case .saveFailed: "The free trial’s count wasn’t saved"
        }
    }
}
