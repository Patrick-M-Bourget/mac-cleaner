import Foundation

/// Historical evidence only. This type cannot construct an approval or invoke an operation.
public struct CleanupRecoverySnapshot: Sendable {
    public let interruptedBatches: [CleanupRecoveryBatch]
    public init(journal: any CleanupJournaling) throws {
        let records = try journal.records()
        let groups = Dictionary(grouping: records, by: \.batchID)
        interruptedBatches = groups.compactMap { id, records in
            let batch = ReviewedBatch(records)
            guard batch.isInterrupted else { return nil }
            return CleanupRecoveryBatch(id: id, records: batch.items)
        }.sorted { ($0.records.first?.approvedAt ?? .distantPast) > ($1.records.first?.approvedAt ?? .distantPast) }
    }
    public var unresolvedCount: Int { interruptedBatches.reduce(0) { $0 + $1.unresolvedCount } }
    public var pendingCount: Int { interruptedBatches.reduce(0) { $0 + $1.pendingCount } }
    public var knownResultCount: Int { interruptedBatches.reduce(0) { $0 + $1.records.count - $1.unresolvedCount - $1.pendingCount } }
}
public struct CleanupRecoveryBatch: Sendable, Identifiable {
    public let id: UUID
    public let records: [CleanupRecord]
    public var unresolvedCount: Int { records.filter { $0.state == .intent || $0.state == .unknown }.count }
    public var pendingCount: Int { records.filter { $0.state == .pending }.count }
}

/// One batch's records, split into the items it was approved for and the reviewed records appended after it was
/// interrupted (#309). Original records are never rewritten; a review only adds records.
struct ReviewedBatch {
    let items: [CleanupRecord]
    let reviews: [CleanupRecord]
    private let reviewed: [String: CleanupRecord]
    init(_ records: [CleanupRecord]) {
        items = records.filter { $0.reviewOf == nil }
        reviews = records.filter { $0.reviewOf != nil }
        reviewed = Dictionary(reviews.map { ($0.reviewOf ?? "", $0) }, uniquingKeysWith: { first, _ in first })
    }
    /// An item without a recorded outcome that no review resolves.
    var isInterrupted: Bool { items.contains { [.pending, .intent, .unknown].contains($0.state) && reviewed[$0.id] == nil } }
    /// The items as History shows them: a reviewed item with its finding, under its own id.
    var shown: [CleanupRecord] {
        items.map { item in
            guard var review = reviewed[item.id] else { return item }
            review.id = item.id
            return review
        }
    }
}
