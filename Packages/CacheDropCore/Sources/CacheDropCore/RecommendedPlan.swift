import Foundation

/// The plan Still recommends from the latest scan: only data that rebuilds itself, deleted, that passes the checks now.
/// Nothing is preselected unless the user asks for it (RESET Decision 28, SPEC section 1).
public struct RecommendedPlan: Sendable {
    /// The scan's candidates the plan takes, in scan order.
    public let candidates: [Candidate]

    /// `check` is the check run just before acting (SPEC section 4); anything it would refuse is left out.
    public init(catalog: Catalog, candidates: [Candidate], check: (Candidate) -> CheckRefusal?) {
        self.candidates = candidates.filter { candidate in
            // Unknown is never 0, and never recommended (SPEC section 1).
            guard SizeEstimate(candidate) != .unknown, let rule = catalog.rule(candidate.ruleID), Self.recommends(rule, action: candidate.action) else { return false }
            return check(candidate) == nil
        }
    }

    /// Kinds of data that come back on their own when deleted (Decision 3).
    static let rebuildsItself: Set<RegenClass> = [.cache, .build, .updaterDownload, .log, .leakedCopy]

    /// Whether a rule's data, acted on with `action`, is ever recommended. The rule itself must delete: a leftover of a
    /// tool rule (Homebrew) is offered as a plain delete, but its rule runs a command, so it is left to the user.
    /// Items the user chooses one by one (an Android system image, #134; a JetBrains version or temporary file, #144) are left to the user too.
    static func recommends(_ rule: CleanupRule, action: CleanupAction) -> Bool {
        action == .delete && rule.action == .delete && rebuildsItself.contains(rule.regen) && !rule.choosesItems
    }
}
