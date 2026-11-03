import Foundation

/// `cachedrop clean` (#627): Smart clean's plan, run through the app's own `CleanupExecutor`, so every item is checked
/// again just before acting and every run lands in the app's journal, which History reads. There is no other way to act.
public enum CommandLineClean {
    /// What `clean` does before acting: run, ask on the terminal, or refuse.
    public enum Start: Equatable, Sendable { case run, ask, refuse }

    /// `--yes` runs; otherwise it asks on a terminal and refuses without one. A dry run changes nothing on disk, so it runs.
    public static func start(yes: Bool, dryRun: Bool, interactive: Bool) -> Start {
        if yes || dryRun { return .run }
        return interactive ? .ask : .refuse
    }

    /// What `run` did: refused before claiming anything, with the reason, or ran, with a trial notice to print (Decision 62).
    public enum Outcome: Sendable {
        case refused(String)
        case ran(CatalogExecutionResult, notice: String?)
    }

    /// The lines `run` refuses with; each changes nothing and claims nothing.
    public enum Refusal {
        public static let busy = "A cleanup is already running, so nothing was changed."
        public static let journal = "CacheDrop couldn’t open its cleanup history, so nothing was changed."
        public static let interrupted = "Review the interrupted cleanup in CacheDrop before cleaning again."
        public static let licenseUnreadable = "CacheDrop couldn’t read the license on this Mac, so nothing was changed."
        public static let trialUnreadable = "CacheDrop couldn’t read the free trial, so nothing was changed."
        public static let trialMissing = "Open CacheDrop once first, so it can keep the free trial’s count. Nothing was changed."
    }

    /// Runs `report`'s picked items through the app's executor with the checks `sources` read, journaling to `journal`,
    /// while holding the cleanup lock at `lock` (`CleanupLock`), so the app can't clean at the same time.
    /// With `gating` (LICENSE_GATING) it reads the license and the trial from the stores, which only update items the app
    /// made (#627): one it can't read refuses rather than reading as no license or a fresh trial (Decision 137), and a
    /// trial item the app hasn't made yet refuses too, since this run's count couldn't be kept. A dry run reads neither.
    @MainActor public static func run(_ report: SmartCleanReport, sources: SmartCleanReport.Sources, dryRun: Bool, journal: any CleanupJournaling, lock: URL,
                                      trash: any TrashMoving, licenseStore: any LicenseKeyStore, trialStore: any TrialStore, gating: Bool,
                                      verifier: LicenseVerifier = .production,
                                      measure: @escaping @Sendable (URL) -> CapacitySample? = CapacitySample.read) async -> Outcome {
        // One cleanup at a time with the app, held from reading the journal until the run ends.
        let held: CleanupLock
        do { guard let acquired = try CleanupLock.acquire(at: lock) else { return .refused(Refusal.busy) }; held = acquired }
        catch { return .refused(Refusal.journal) }
        defer { held.release() }
        // An unfinished cleanup is reviewed in the app before another starts. A journal that can't be read never lets a run start.
        guard let snapshot = try? CleanupRecoverySnapshot(journal: journal) else { return .refused(Refusal.journal) }
        guard snapshot.interruptedBatches.isEmpty else { return .refused(Refusal.interrupted) }
        // The license and trial, as the review sheet applies them (Decisions 135, 137); a dry run counts nothing and is never blocked.
        var license = LicenseState.none, trial = TrialController(store: trialStore, gating: false)
        if gating, !dryRun {
            let controller = LicenseController(store: licenseStore, verifier: verifier)
            if controller.notice == .unreadable { return .refused(Refusal.licenseUnreadable) }
            license = controller.state
            if case .active = license {} else {
                do { guard try trialStore.read() != nil else { return .refused(Refusal.trialMissing) } }
                catch { return .refused(Refusal.trialUnreadable) }
                trial = TrialController(store: trialStore, gating: true)
                if trial.notice == .unreadable { return .refused(Refusal.trialUnreadable) }
            }
        }
        let approval = CatalogApproval(candidates: report.picked.map(\.candidate), dryRun: dryRun)
        // A plan bigger than what's left never runs.
        let allowance = trial.allowance(for: license), size = approval.trialBytes(skipping: [], catalog: sources.catalog)
        if !allowance.permits(size, dryRun: dryRun) {
            return .refused((allowance.reviewLine(plan: size, dryRun: false) ?? "Free trial used") + ". Enter a license in CacheDrop’s Settings, or buy one at "
                            + LicensePrice.buyURL.absoluteString + ".")
        }
        let executor = CleanupExecutor(journal: journal, check: sources.check, measure: measure, trash: trash)
        let result = await executor.execute(approval)
        trial.record(result, of: approval, catalog: sources.catalog)
        return .ran(result, notice: trial.notice?.message)
    }
}
