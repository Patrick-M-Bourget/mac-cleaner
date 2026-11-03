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

    /// What `run` did: refused before claiming anything, with the reason, or ran.
    public enum Outcome: Sendable {
        case refused(String)
        case ran(CatalogExecutionResult)
    }

    /// Runs `report`'s picked items through the app's executor with the checks `sources` read, journaling to `journal`.
    @MainActor public static func run(_ report: SmartCleanReport, sources: SmartCleanReport.Sources, dryRun: Bool, journal: any CleanupJournaling,
                                      trash: any TrashMoving, trial: TrialController, license: LicenseState,
                                      measure: @escaping @Sendable (URL) -> CapacitySample? = CapacitySample.read) async -> Outcome {
        // An unfinished cleanup (interrupted, or one the app is running now) is reviewed in the app before another starts.
        // A journal that can't be read never lets a run start.
        guard let snapshot = try? CleanupRecoverySnapshot(journal: journal) else { return .refused("CacheDrop couldn’t open its cleanup history, so nothing was changed.") }
        guard snapshot.interruptedBatches.isEmpty else { return .refused("Review the interrupted cleanup in CacheDrop before cleaning again.") }
        let approval = CatalogApproval(candidates: report.picked.map(\.candidate), dryRun: dryRun)
        // The trial, as the review sheet applies it (Decisions 135, 137): a plan bigger than what's left never runs.
        let allowance = trial.allowance(for: license), size = approval.trialBytes(skipping: [], catalog: sources.catalog)
        if !allowance.permits(size, dryRun: dryRun) {
            return .refused((allowance.reviewLine(plan: size, dryRun: false) ?? "Free trial used") + ". Enter a license in CacheDrop’s Settings, or buy one at "
                            + LicensePrice.buyURL.absoluteString + ".")
        }
        let executor = CleanupExecutor(journal: journal, check: sources.check, measure: measure, trash: trash)
        let result = await executor.execute(approval)
        trial.record(result, of: approval, catalog: sources.catalog)
        return .ran(result)
    }
}
