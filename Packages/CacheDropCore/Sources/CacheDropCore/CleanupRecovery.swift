import Foundation

/// Historical evidence only. This type cannot construct an approval or invoke an operation.
public struct CleanupRecoverySnapshot: Sendable {
    public let interruptedBatches: [CleanupRecoveryBatch]
    public init(journal: any CleanupJournaling) throws {
        let records = try journal.records()
        let groups = Dictionary(grouping: records, by: \.batchID)
        interruptedBatches = groups.compactMap { id, records in
            guard records.contains(where: { $0.state == .pending || $0.state == .intent || $0.state == .unknown }) else { return nil }
            return CleanupRecoveryBatch(id: id, records: records)
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
