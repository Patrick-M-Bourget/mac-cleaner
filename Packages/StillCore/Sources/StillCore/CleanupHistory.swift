import Foundation

public struct CleanupHistoryRun: Sendable, Identifiable {
    public let id: UUID
    public let records: [CleanupRecord]
    public var date: Date { records.compactMap(\.outcomeRecordedAt).max() ?? records.map(\.approvedAt).max() ?? .distantPast }
    public var usesApprovalDate: Bool { records.contains { $0.outcomeRecordedAt == nil } }
}
public struct CleanupHistorySnapshot: Sendable {
    public let completedRuns: [CleanupHistoryRun]
    public let protectedRecordCount: Int
    public init(records: [CleanupRecord]) {
        let groups = Dictionary(grouping: records, by: \.batchID)
        var completed: [CleanupHistoryRun] = []
        var protected = 0
        for (id, records) in groups {
            if records.contains(where: { [.pending, .intent, .unknown].contains($0.state) }) { protected += records.count }
            else { completed.append(CleanupHistoryRun(id: id, records: records)) }
        }
        completedRuns = completed.sorted { $0.date > $1.date }
        protectedRecordCount = protected
    }
}
public struct CleanupHistoryMaintenance: Sendable {
    public let removedRuns: Int
    public let removedRecords: Int
    public let protectedRecords: Int
}
public struct CleanupHistoryCompaction: Sendable {
    public let beforeBytes: Int64
    public let afterBytes: Int64
    public let completed: Bool
}
