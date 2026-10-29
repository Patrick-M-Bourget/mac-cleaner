import Foundation

/// The plan CacheDrop recommends from the latest scan, Smart clean's (#319, amending Decisions 28 and 31): data that comes
/// back on its own, a tool's own cleanup of its cache, old downloads (#342) and leftovers tied to a removed app, that
/// pass the checks now. Everything else is left to the user. Its items start ticked on every page (#349, `CleanupSelections`).
public struct RecommendedPlan: Sendable {
    /// The scan's candidates the plan takes, in scan order.
    public let candidates: [Candidate]
    /// What the plan would take but something holds now (#374): the scan found it in use, or `check` says its owner is running
    /// or using it. Smart clean lists them unticked with their `hold`; never taken unless ticked.
    public let held: [Candidate]

    /// `check` is the check run just before acting (SPEC section 4); anything it would refuse is left out, or held while in use.
    /// `now` dates the downloads: one is taken only when nothing opened or changed it in `downloadUnusedDays`.
    public init(catalog: Catalog, candidates: [Candidate], now: Date = Date(), check: (Candidate) -> CheckRefusal?) {
        var taken: [Candidate] = [], held: [Candidate] = []
        for candidate in candidates {
            // Unknown is never 0, and never recommended (SPEC section 1); nor is an item that measures 0 bytes, which frees nothing (#319).
            let size = SizeEstimate(candidate)
            guard size != .unknown, size != .measured(0), let rule = catalog.rule(candidate.ruleID), Self.recommends(candidate, rule: rule, now: now) else { continue }
            if candidate.hold != nil { held.append(candidate); continue }
            guard let refusal = check(candidate) else { taken.append(candidate); continue }
            // One rule says whether the refusal is a hold, and whose (Decision 79).
            guard let hold = CandidateHold(refusal, of: candidate, catalog: catalog) else { continue }
            var found = candidate
            found.hold = hold
            held.append(found)
        }
        self.candidates = taken; self.held = held
    }

    /// Kinds of data that come back on their own when deleted, or cleaned by their tool (Decision 3).
    static let rebuildsItself: Set<RegenClass> = [.cache, .build, .updaterDownload, .log, .leakedCopy]
    /// A file in Downloads, of any kind or size, is taken once it hasn't been opened or changed in this many days (#342,
    /// amending #319's 90-day installers; 7 by the owner, 2026-10-29: Put back covers a mistake). The Cleanup plan still
    /// offers every download at any age (Decision 83).
    public static let downloadUnusedDays = 7

    /// Whether the plan takes `candidate`, found by `rule`. The candidate must be acted on as its rule acts: a leftover of a
    /// tool rule (Homebrew) is offered as a plain delete, so it is left to the user.
    static func recommends(_ candidate: Candidate, rule: CleanupRule, now: Date) -> Bool { basis(candidate, rule: rule, now: now) != nil }

    /// Why the plan takes `candidate`, found by `rule`; nil when it doesn't. The Smart clean report words its reason from it.
    enum Basis { case rebuildsItself, oldDownload, leftover(LeftoverTie) }
    static func basis(_ candidate: Candidate, rule: CleanupRule, now: Date) -> Basis? {
        guard candidate.action == rule.action else { return nil }
        switch rule.action {
        case .delete, .tool:
            // Items the user chooses one by one (an Android system image, #134; a JetBrains version, #144; each simulator) are left
            // to the user, and so is Docker, whose prune reaches past what CacheDrop sees.
            return rebuildsItself.contains(rule.regen) && !rule.choosesItems && !rule.isDocker ? .rebuildsItself : nil
        case .trash:
            if rule.id == CleanupRule.downloadsID { return isOldDownload(candidate, now: now) ? .oldDownload : nil }
            // Only a bundle ID or installer receipt ties a leftover to its app; a name-only match is possibly related.
            if rule.id == RemovedAppLeftovers.ruleID, let tie = candidate.leftover, !tie.isNameOnly { return .leftover(tie) }
            return nil
        case .evict, .guidance:
            return nil
        }
    }

    /// A download nothing has opened or changed in `downloadUnusedDays`; one with no date is not known to be old.
    static func isOldDownload(_ candidate: Candidate, now: Date) -> Bool {
        guard let used = candidate.lastUsed else { return false }
        return now.timeIntervalSince(used) >= TimeInterval(downloadUnusedDays) * .secondsPerDay
    }
}

extension CleanupRule {
    /// The Downloads rule (Decision 83): every file in Downloads, which Smart clean takes only when old (#342).
    public static let downloadsID = "downloads"
    /// A Docker prune rule (#112).
    var isDocker: Bool { if case .docker = items { true } else { false } }
    /// Whether its rows show the folder (location, path, Reveal in Finder). Docker's `.docker` only anchors its rules: the
    /// prunes work inside Docker's VM (#420).
    public var showsFolder: Bool { !isDocker }
}
