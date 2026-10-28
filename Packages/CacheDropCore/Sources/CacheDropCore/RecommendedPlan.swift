import Foundation

/// The plan CacheDrop recommends from the latest scan, Smart clean's (#319, amending Decisions 28 and 31): data that comes
/// back on its own, a tool's own cleanup of its cache, old installers in Downloads and leftovers tied to a removed app, that
/// pass the checks now. Everything else is left to the user, and nothing is preselected on the Cleanup plan.
public struct RecommendedPlan: Sendable {
    /// The scan's candidates the plan takes, in scan order.
    public let candidates: [Candidate]

    /// `check` is the check run just before acting (SPEC section 4); anything it would refuse is left out.
    /// `now` dates the installers: one is taken only when nothing opened or changed it in `installerUnusedDays`.
    public init(catalog: Catalog, candidates: [Candidate], now: Date = Date(), check: (Candidate) -> CheckRefusal?) {
        self.candidates = candidates.filter { candidate in
            // Unknown is never 0, and never recommended (SPEC section 1).
            guard SizeEstimate(candidate) != .unknown, let rule = catalog.rule(candidate.ruleID), Self.recommends(candidate, rule: rule, now: now) else { return false }
            return check(candidate) == nil
        }
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
    static func recommends(_ candidate: Candidate, rule: CleanupRule, now: Date) -> Bool {
        guard candidate.action == rule.action else { return false }
        switch rule.action {
        case .delete, .tool:
            // Items the user chooses one by one (an Android system image, #134; a JetBrains version, #144; each simulator) are left
            // to the user, and so is Docker, whose prune reaches past what CacheDrop sees.
            return rebuildsItself.contains(rule.regen) && !rule.choosesItems && !rule.isDocker
        case .trash:
            if rule.id == "downloads-installers" { return isOldInstaller(candidate, now: now) }
            // Only a bundle ID or installer receipt ties a leftover to its app; a name-only match is possibly related.
            if rule.id == RemovedAppLeftovers.ruleID, let tie = candidate.leftover { return !tie.isNameOnly }
            return false
        case .evict, .guidance:
            return false
        }
    }

    /// A `.dmg` or `.pkg` nothing has opened or changed in `installerUnusedDays`; one with no date is not known to be old.
    static func isOldInstaller(_ candidate: Candidate, now: Date) -> Bool {
        guard installerExtensions.contains(candidate.url.pathExtension.lowercased()), let used = candidate.lastUsed else { return false }
        return now.timeIntervalSince(used) >= TimeInterval(installerUnusedDays) * 86_400
    }
}

extension CleanupRule {
    /// A Docker prune rule (#112).
    var isDocker: Bool { if case .docker = items { true } else { false } }
}
