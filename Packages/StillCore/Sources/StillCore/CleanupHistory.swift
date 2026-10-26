import Foundation

public struct CleanupHistoryRun: Sendable, Identifiable {
    public let id: UUID
    public let records: [CleanupRecord]
    public var capacity: CleanupCapacityObservation? { records.compactMap(\.capacityObservation).first }
    public var plannedLogicalBytes: Int64 {
        var seen = Set<String>()
        return records.filter { seen.insert($0.resourceID).inserted }.reduce(0) { $0 + $1.logicalBytes }
    }
    public var trashHeldAllocatedBytes: Int64? {
        var seen = Set<String>()
        let successes = records.filter { $0.state == .succeeded && $0.action == "moveToTrash" && seen.insert($0.resourceID).inserted }
        guard successes.allSatisfy({ $0.allocatedBytes != nil }) else { return nil }
        return successes.reduce(0) { $0 + ($1.allocatedBytes ?? 0) }
    }
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

public struct CleanupCapacityObservation: Codable, Sendable {
    public let beforeAvailable: Int64?, afterAvailable: Int64?, beforeTotal: Int64?, afterTotal: Int64?
    public let beforeVolumeID: String?, afterVolumeID: String?
    public let beforeMetric: String, afterMetric: String
    public let beforeDate: Date, afterDate: Date
    public init(beforeAvailable: Int64?, afterAvailable: Int64?, beforeTotal: Int64?, afterTotal: Int64?, beforeVolumeID: String?, afterVolumeID: String?, beforeMetric: String, afterMetric: String, beforeDate: Date, afterDate: Date) {
        self.beforeAvailable = beforeAvailable; self.afterAvailable = afterAvailable
        self.beforeTotal = beforeTotal; self.afterTotal = afterTotal
        self.beforeVolumeID = beforeVolumeID; self.afterVolumeID = afterVolumeID
        self.beforeMetric = beforeMetric; self.afterMetric = afterMetric
        self.beforeDate = beforeDate; self.afterDate = afterDate
    }
    public var observedChange: Int64? {
        guard let id = beforeVolumeID, id == afterVolumeID, beforeMetric == afterMetric,
              let total = beforeTotal, total > 0, total == afterTotal,
              let before = beforeAvailable, let after = afterAvailable,
              before >= 0, after >= 0, before <= total, after <= total, afterDate >= beforeDate else { return nil }
        return after - before
    }
}
