import Foundation

/// The plan CacheDrop recommends from the latest scan, Smart clean's (#319, amending Decisions 28 and 31): data that comes
/// back on its own, a tool's own cleanup of its cache, old installers in Downloads and leftovers tied to a removed app, that
/// pass the checks now. Everything else is left to the user. Its items start ticked on every page (#349, `CleanupSelections`).
public struct RecommendedPlan: Sendable {
    /// The scan's candidates the plan takes, in scan order.
    public let candidates: [Candidate]
    /// What the plan would take but something holds now (#374): the scan found it in use, or `check` says its owner is running
    /// or using it. Smart clean lists them unticked with their `hold`; never taken unless ticked.
    public let held: [Candidate]

    /// `check` is the check run just before acting (SPEC section 4); anything it would refuse is left out, or held while in use.
    /// `now` dates the installers: one is taken only when nothing opened or changed it in `installerUnusedDays`.
    public init(catalog: Catalog, candidates: [Candidate], now: Date = Date(), check: (Candidate) -> CheckRefusal?) {
        var taken: [Candidate] = [], held: [Candidate] = []
        for candidate in candidates {
            // Unknown is never 0, and never recommended (SPEC section 1); nor is an item that measures 0 bytes, which frees nothing (#319).
            let size = SizeEstimate(candidate)
            guard size != .unknown, size != .measured(0), let rule = catalog.rule(candidate.ruleID), Self.recommends(candidate, rule: rule, now: now) else { continue }
            if candidate.hold != nil { held.append(candidate); continue }
            switch check(candidate) {
            case nil: taken.append(candidate)
            case .ownerRunning(let name)?:
                var found = candidate
                found.hold = CandidateHold(.ownerRunning(name), app: catalog.owner(for: candidate))
                held.append(found)
            case .inUse(let name)?:
                var found = candidate
                found.hold = CandidateHold(.inUse(name), app: rule.copies?.owner)
                held.append(found)
            default: continue
            }
        }
        self.candidates = taken; self.held = held
    }

    /// Kinds of data that come back on their own when deleted, or cleaned by their tool (Decision 3).
    static let rebuildsItself: Set<RegenClass> = [.cache, .build, .updaterDownload, .log, .leakedCopy]
    /// Downloads installers are taken once they haven't been opened or changed in this many days (#319). The Cleanup plan
    /// still offers them at any age (Decision 18).
    public static let installerUnusedDays = 90
    /// Only disk images and packages: an archive may hold anything.
    static let installerExtensions: Set<String> = ["dmg", "pkg"]

    /// Whether the plan takes `candidate`, found by `rule`. The candidate must be acted on as its rule acts: a leftover of a
    /// tool rule (Homebrew) is offered as a plain delete, so it is left to the user.
    static func recommends(_ candidate: Candidate, rule: CleanupRule, now: Date) -> Bool { basis(candidate, rule: rule, now: now) != nil }

    /// Why the plan takes `candidate`, found by `rule`; nil when it doesn't. The Smart clean report words its reason from it.
    enum Basis { case rebuildsItself, oldInstaller, leftover(LeftoverTie) }
    static func basis(_ candidate: Candidate, rule: CleanupRule, now: Date) -> Basis? {
        guard candidate.action == rule.action else { return nil }
        switch rule.action {
        case .delete, .tool:
            // Items the user chooses one by one (an Android system image, #134; a JetBrains version, #144; each simulator) are left
            // to the user, and so is Docker, whose prune reaches past what CacheDrop sees.
            return rebuildsItself.contains(rule.regen) && !rule.choosesItems && !rule.isDocker ? .rebuildsItself : nil
        case .trash:
            if rule.id == CleanupRule.downloadsInstallersID { return isOldInstaller(candidate, now: now) ? .oldInstaller : nil }
            // Only a bundle ID or installer receipt ties a leftover to its app; a name-only match is possibly related.
            if rule.id == RemovedAppLeftovers.ruleID, let tie = candidate.leftover, !tie.isNameOnly { return .leftover(tie) }
            return nil
        case .evict, .guidance:
            return nil
        }
    }

    /// A `.dmg` or `.pkg` nothing has opened or changed in `installerUnusedDays`; one with no date is not known to be old.
    static func isOldInstaller(_ candidate: Candidate, now: Date) -> Bool {
        guard installerExtensions.contains(candidate.url.pathExtension.lowercased()), let used = candidate.lastUsed else { return false }
        return now.timeIntervalSince(used) >= TimeInterval(installerUnusedDays) * .secondsPerDay
    }
}

extension CleanupRule {
    /// The Downloads installers rule (Decision 18), which Smart clean takes only when old (#319).
    public static let downloadsInstallersID = "downloads-installers"
    /// A Docker prune rule (#112).
    var isDocker: Bool { if case .docker = items { true } else { false } }
}
