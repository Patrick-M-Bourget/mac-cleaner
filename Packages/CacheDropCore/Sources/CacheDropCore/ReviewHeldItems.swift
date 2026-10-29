import Foundation

/// The review sheet's rows a running app holds (#377, Decision 79). A row refused because its owner is running
/// (`.ownerRunning`), or because a known app is using it (`.inUse`), offers "Quit X" when that owner is an app that is
/// open now; a command-line tool, a holder that isn't a known app, or one that couldn't be checked offers nothing.
/// Once the app quits, its rows are checked again: one that passes leaves, one that doesn't shows its new reason.
/// An app that doesn't quit leaves its rows as they were. Nothing here changes the review's choices.
public struct ReviewHeldItems: Sendable {
    /// Each refused row's reason, by candidate id.
    public private(set) var refusals: [String: CheckRefusal]
    /// The open app holding each row that offers to quit it, by candidate id.
    private var holders: [String: RuleOwner] = [:]
    private let candidates: [Candidate]
    private let catalog: Catalog

    /// `isOpen` says whether an app with one of these bundle identifiers is open (`AppQuitting.isOpen`).
    public init(candidates: [Candidate], refusals: [String: CheckRefusal], catalog: Catalog, isOpen: ([String]) -> Bool) {
        self.candidates = candidates; self.refusals = refusals; self.catalog = catalog
        for candidate in candidates { findHolder(of: candidate, isOpen: isOpen) }
    }

    /// The row's link title, "Quit X", or nil when it has none.
    public func quitTitle(for candidate: Candidate) -> String? { holders[candidate.id].map { "Quit \($0.name)" } }
    /// The open app the row offers to quit.
    public func holder(of candidate: Candidate) -> RuleOwner? { holders[candidate.id] }
    /// The rows that offer to quit `owner`, in review order.
    public func candidates(heldBy owner: RuleOwner) -> [Candidate] { candidates.filter { holders[$0.id]?.name == owner.name } }

    /// After asking `owner` to quit: when it quit, its rows are checked again with `check`; otherwise nothing changes.
    public mutating func quitEnded(_ owner: RuleOwner, outcome: AppQuitOutcome, isOpen: ([String]) -> Bool, check: (Candidate) -> CheckRefusal?) {
        guard outcome == .quit else { return }
        for candidate in candidates(heldBy: owner) {
            refusals[candidate.id] = check(candidate)
            findHolder(of: candidate, isOpen: isOpen)
        }
    }

    private mutating func findHolder(of candidate: Candidate, isOpen: ([String]) -> Bool) {
        let owner = refusals[candidate.id].flatMap { Self.knownHolder(of: candidate, refusal: $0, catalog: catalog) }
        holders[candidate.id] = owner.flatMap { !$0.bundleIDs.isEmpty && isOpen($0.bundleIDs) ? $0 : nil }
    }

    /// The owner a refusal names, among those the catalog knows for the item: its own owner or a plug-in host while it
    /// runs, the app whose leaked copy it is while that app uses it. Nil for any other reason or holder.
    static func knownHolder(of candidate: Candidate, refusal: CheckRefusal, catalog: Catalog) -> RuleOwner? {
        guard let rule = catalog.rule(candidate.ruleID) else { return nil }
        switch refusal {
        case .ownerRunning(let name):
            let owners = catalog.owner(for: candidate).map { [$0] } ?? []
            return (owners + (candidate.uninstall?.plugIn?.hosts ?? [])).first { $0.name == name }
        case .inUse(let name):
            guard case .mustNotUse(let owner) = Catalog.ownership(of: candidate, under: rule), owner.name == name else { return nil }
            return owner
        default: return nil
        }
    }
}
