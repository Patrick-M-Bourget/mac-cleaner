import Foundation

/// The review sheet's rows a running app holds (#377, Decision 79). A row refused because its owner is running
/// (`.ownerRunning`), or because a known app is using it (`.inUse`), offers "Quit X" when that owner is an app that is
/// open now; a command-line tool, a holder that isn't a known app, or one that couldn't be checked offers nothing.
/// Once the app quits, by the sheet's link or any other way (#560), its rows are checked again: one that passes leaves, one
/// that doesn't shows its new reason. An app that doesn't quit leaves its rows as they were. Nothing here changes the review's
/// choices.
public struct ReviewHeldItems: Sendable {
    /// Each refused row's reason, by candidate id.
    public private(set) var refusals: [String: CheckRefusal]
    /// The known app holding each row, open or not, by candidate id.
    private var holders: [String: RuleOwner] = [:]
    /// The holders open as apps at the last look, which the rows offer to quit.
    private var open: Set<RuleOwner> = []
    private let candidates: [Candidate]
    private let catalog: Catalog

    /// `isOpen` says whether an app with one of these bundle identifiers is open (`AppQuitting.isOpen`).
    public init(candidates: [Candidate], refusals: [String: CheckRefusal], catalog: Catalog, isOpen: ([String]) -> Bool) {
        self.candidates = candidates; self.refusals = refusals; self.catalog = catalog
        for candidate in candidates { findHolder(of: candidate, isOpen: isOpen) }
    }

    /// The row's link title, "Quit X", or nil when it has none.
    public func quitTitle(for candidate: Candidate) -> String? { holder(of: candidate).map { "Quit \($0.name)" } }
    /// The open app the row offers to quit.
    public func holder(of candidate: Candidate) -> RuleOwner? { holders[candidate.id].flatMap { open.contains($0) ? $0 : nil } }
    /// The rows `owner` holds, in review order. Owners are told apart by what they are, never by their display
    /// name alone: two apps may both be called "Synth" (#384).
    public func candidates(heldBy owner: RuleOwner) -> [Candidate] { candidates.filter { holders[$0.id] == owner } }

    /// One skipped line of the review sheet (#560, Decision 125): every row one holder holds, or one row skipped for a reason
    /// of its own. Its size is what it leaves behind, shown once on the line and counted in no total.
    public struct Line: Sendable, Identifiable {
        /// Its first row's id.
        public var id: String { items[0].id }
        public let items: [Candidate]
        /// "Google Chrome is open, so its caches will be skipped"; nil for a row skipped for its own reason, which the
        /// sheet names with its refusal's reason.
        public let text: String?
        /// The first row's reason.
        public let refusal: CheckRefusal
        public let size: SizeEstimate
        /// Part of it is copies that share disk blocks, as on the review's other lines.
        public let isUpperBound: Bool
        /// The open app the line offers to quit, normally (Decision 79); nil when there is none.
        public let quitOwner: RuleOwner?
        public var quitTitle: String? { quitOwner.map { "Quit \($0.name)" } }
    }

    /// The skipped lines among `candidates`, in their order: one per holder, told apart by the holding app itself when it is
    /// a known one, else by its reason; any other refused row on a line of its own. Rows that pass have none.
    public func lines(in candidates: [Candidate]) -> [Line] {
        enum Key: Hashable { case app(RuleOwner), hold(CheckRefusal), item(String) }
        var order: [Key] = [], rows: [Key: [Candidate]] = [:]
        for candidate in candidates {
            guard let refusal = refusals[candidate.id] else { continue }
            let hold = CandidateHold(refusal, of: candidate, catalog: catalog)
            let key: Key = hold?.app.map(Key.app) ?? (hold != nil ? .hold(refusal) : .item(candidate.id))
            if rows[key] == nil { order.append(key) }
            rows[key, default: []].append(candidate)
        }
        return order.map { key in
            let items = rows[key] ?? []
            let refusal = items.lazy.compactMap { refusals[$0.id] }.first { if case .ownerRunning = $0 { true } else { false } } ?? refusals[items[0].id]!
            let text: String? = if case .item = key { nil } else { Self.text(refusal, items: items, catalog: catalog) }
            return Line(items: items, text: text, refusal: refusal, size: SizeEstimate(sum: items.map(SizeEstimate.init)),
                        isUpperBound: items.contains { catalog.rule($0.ruleID)?.estimateIsUpperBound == true }, quitOwner: holder(of: items[0]))
        }
    }
    private static func text(_ refusal: CheckRefusal, items: [Candidate], catalog: Catalog) -> String {
        switch refusal {
        case .ownerRunning(let name):
            let caches = items.allSatisfy { catalog.rule($0.ruleID)?.regen == .cache }
            return "\(name) is open, so its \(caches ? "caches" : "items") will be skipped"
        case .inUse(let name):
            return items.count == 1 ? "\(name) is using 1 item, so it will be skipped" : "\(name) is using \(items.count) items, so they will be skipped"
        default: return refusal.reason
        }
    }

    /// The known apps holding rows that aren't open as apps now: the ones whose rows to check again after an app quit by any
    /// means (#560), and again while a row stays held, as when a quit app's helpers are still closing.
    public func ownersToCheckAgain(isOpen: ([String]) -> Bool) -> [RuleOwner] {
        var owners: [RuleOwner] = []
        for candidate in candidates {
            guard let owner = holders[candidate.id], !owners.contains(owner), !isOpen(owner.bundleIDs) else { continue }
            owners.append(owner)
        }
        return owners
    }

    /// After asking `owner` to quit: when it quit, its rows are checked again with `check`; otherwise nothing changes.
    public mutating func quitEnded(_ owner: RuleOwner, outcome: AppQuitOutcome, isOpen: ([String]) -> Bool, check: (Candidate) -> CheckRefusal?) {
        guard outcome == .quit else { return }
        for candidate in candidates(heldBy: owner) {
            refusals[candidate.id] = check(candidate)
            findHolder(of: candidate, isOpen: isOpen)
        }
    }

    private mutating func findHolder(of candidate: Candidate, isOpen: ([String]) -> Bool) {
        let owner = refusals[candidate.id].flatMap { CandidateHold($0, of: candidate, catalog: catalog)?.app }
        holders[candidate.id] = owner.flatMap { $0.bundleIDs.isEmpty ? nil : $0 }
        guard let owner = holders[candidate.id] else { return }
        if isOpen(owner.bundleIDs) { open.insert(owner) } else { open.remove(owner) }
    }
}

extension CandidateHold {
    /// The hold a refusal says something has on `candidate` (#374, #377, Decision 79), the one rule Smart clean's held lines
    /// and the review's Quit links read: its owner, or a plug-in host, is running (`.ownerRunning`), or something is using it
    /// (`.inUse`). Its `app` is the owner the refusal names among those the catalog knows for the item: its own owner or a
    /// plug-in host, or the app whose leaked copy it is; nil for any other holder ("An Android virtual device", any app).
    /// Nil for any other refusal.
    public init?(_ refusal: CheckRefusal, of candidate: Candidate, catalog: Catalog) {
        let rule = catalog.rule(candidate.ruleID)
        switch refusal {
        case .ownerRunning(let name):
            let owners = (catalog.owner(for: candidate).map { [$0] } ?? []) + (candidate.uninstall?.plugIn?.hosts ?? [])
            self.init(refusal, app: owners.first { $0.name == name })
        case .inUse(let name):
            guard let rule, case .mustNotUse(let owner) = Catalog.ownership(of: candidate, under: rule), owner.name == name, owner != .anyApp else {
                self.init(refusal); return
            }
            self.init(refusal, app: owner)
        default: return nil
        }
    }

    /// Items with the same hold, together (#374, #384).
    public struct Group: Sendable {
        /// What holds them; nil for free items.
        public let hold: CandidateHold?
        public let items: [Candidate]
    }
    /// `candidates` grouped by their hold, told apart by what holds them, never by the line's wording: free items first,
    /// then each hold in the order it first appears. Smart clean gives each group a line of its own.
    public static func grouped(_ candidates: [Candidate]) -> [Group] {
        var holds: [CandidateHold?] = [], items: [CandidateHold?: [Candidate]] = [:]
        for candidate in candidates {
            if items[candidate.hold] == nil { holds.append(candidate.hold) }
            items[candidate.hold, default: []].append(candidate)
        }
        return (holds.filter { $0 == nil } + holds.filter { $0 != nil }).map { Group(hold: $0, items: items[$0] ?? []) }
    }
}
