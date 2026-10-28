import Foundation

/// The Cleaning up screen's view of a running cleanup (#355, variant A): each category ticking off, what was released so
/// far, and the storage bar shaving down at its tip. Built from the approval and the records the run has written; the bar
/// steps once per finished item, since nothing within an item is measured.
public struct CleanupRunProgress: Sendable {
    public enum State: Sendable, Equatable { case waiting, cleaning, done }
    public struct Category: Sendable, Equatable {
        public let category: CatalogCategory
        public let total: Int
        public let finished: Int
        /// Finished without being cleaned: refused or failed (a dry run's "would" counts as cleaned).
        public let skipped: Int
        /// Left untouched because the run was stopped first.
        public let notStarted: Int
        public let state: State
    }
    /// The run's categories, in the order it reaches them.
    public let categories: [Category]
    /// What the finished items released (or would, in a dry run), from the scan's estimates.
    public let releasedBytes: Int64
    /// What the finished items moved to the Trash, still used until it is emptied (SPEC section 6).
    public let movedToTrashBytes: Int64
    public let finished: Int
    public let total: Int
    /// What is still to go, for the bar: by category; and the Trash-bound items already moved, by category.
    private let remaining: [(category: CatalogCategory, bytes: Int64)]
    private let moved: [CatalogCategory: Int64]

    public init(approval: CatalogApproval, catalog: Catalog, records: [CleanupRecord]) {
        let byCandidate = Dictionary(records.map { ($0.candidateID, $0) }, uniquingKeysWith: { _, last in last })
        let category = { (candidate: Candidate) in catalog.rule(candidate.ruleID)?.category ?? .files }
        let resolved = { (record: CleanupRecord?) in record.map { $0.state != .pending && $0.state != .intent } ?? false }
        let cleaned = { (record: CleanupRecord) in record.state == .succeeded || record.wasPreviewed }
        var order: [CatalogCategory] = []
        for candidate in approval.candidates where !order.contains(category(candidate)) { order.append(category(candidate)) }
        let current = approval.candidates.first { !resolved(byCandidate[$0.id]) }.map(category)
        categories = order.map { name in
            let items = approval.candidates.filter { category($0) == name }
            let done = items.filter { resolved(byCandidate[$0.id]) }
            let notCleaned = done.compactMap { byCandidate[$0.id] }.filter { !cleaned($0) }
            let notStarted = notCleaned.filter { $0.state == .cancelled }.count
            let state: State = done.count == items.count ? .done : name == current ? .cleaning : .waiting
            return Category(category: name, total: items.count, finished: done.count, skipped: notCleaned.count - notStarted, notStarted: notStarted, state: state)
        }
        let finishedItems = approval.candidates.filter { resolved(byCandidate[$0.id]) }
        let cleanedItems = finishedItems.filter { cleaned(byCandidate[$0.id]!) }
        releasedBytes = cleanedItems.filter(\.releasesSpace).reduce(0) { $0 + $1.estimatedBytes }
        movedToTrashBytes = cleanedItems.filter { !$0.releasesSpace }.reduce(0) { $0 + $1.estimatedBytes }
        finished = finishedItems.count
        total = approval.candidates.count
        remaining = order.map { name in
            (name, approval.candidates.filter { category($0) == name && !resolved(byCandidate[$0.id]) }.reduce(0) { $0 + $1.estimatedBytes })
        }
        moved = Dictionary(cleanedItems.filter { !$0.releasesSpace }.map { (category($0), $0.estimatedBytes) }, uniquingKeysWith: +)
    }

    /// The storage bar while the run goes: the disk's used space at the start, less what was released, with what is still
    /// to go at the tip and what went to the Trash in the Trash's grey beside it (#343). A dry run (`releasing` false)
    /// releases nothing, so its bar stays still. Nil for an inconsistent reading.
    public func breakdown(usedAtStart: Int64, total: Int64, trash: TrashContents, releasing: Bool = true) -> StorageBreakdown? {
        let used = releasing ? max(0, usedAtStart - releasedBytes) : usedAtStart
        guard total > 0, used <= total else { return nil }
        // Moved items stay in their category's bytes so the bar can draw them as "Goes to the Trash" instead.
        let categories = remaining.map { entry in (entry.category, SizeEstimate.measured(entry.bytes + (moved[entry.category] ?? 0))) }
        return StorageBreakdown(used: used, total: total, categories: categories, trash: trash, highlighted: nil, toTrash: moved)
    }
}
