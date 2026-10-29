import Foundation

public struct CleanupHistoryRun: Sendable, Identifiable {
    public let id: UUID
    public let records: [CleanupRecord]
    /// Ids of this run's Trash moves that were put back since (#159).
    public var putBackIDs: Set<String> = []
    /// Ids of this run's Trash moves that were deleted from the Trash since (#359): they have no Put back.
    public var emptiedIDs: Set<String> = []
    /// The reviewed records appended after this run was interrupted (#309); `records` already shows their findings.
    public var reviewRecords: [CleanupRecord] = []
    public var capacity: CleanupCapacityObservation? { records.compactMap(\.capacityObservation).first }
    /// What the run planned, in the size Results shows (allocated where known), so both read the same (#312).
    public var plannedBytes: Int64 { distinctSpaces.reduce(0) { $0 + $1.recordedBytes } }
    private var distinctSpaces: [CleanupRecord] {
        var seen = Set<String>()
        // Docker's prunes share the folder that anchors them, but each is its own space (`SpaceKey`).
        return records.filter { seen.insert(SpaceKey.of(resourceID: $0.resourceID, ruleID: $0.ruleID, action: $0.cleanupAction, item: $0.toolItem)).inserted }
    }
    public var trashHeldAllocatedBytes: Int64? {
        var seen = Set<String>()
        let successes = records.filter { $0.state == .succeeded && $0.cleanupAction == .trash && $0.recoveryFinding != .gone && !putBackIDs.contains($0.id) && !emptiedIDs.contains($0.id) && seen.insert($0.resourceID).inserted }
        guard successes.allSatisfy({ $0.allocatedBytes != nil }) else { return nil }
        return successes.reduce(0) { $0 + ($1.allocatedBytes ?? 0) }
    }
    /// The available-space change read around each item the run removed, as Results measures it; nil when any reading is
    /// missing. Shown for an emptying of the Trash (#359).
    public var measuredFreedBytes: Int64? { isPreview ? nil : records.measuredFreedBytes }
    public var date: Date { records.compactMap(\.outcomeRecordedAt).max() ?? records.map(\.approvedAt).max() ?? .distantPast }
    public var usesApprovalDate: Bool { records.contains { $0.outcomeRecordedAt == nil } }
}
public struct CleanupHistorySnapshot: Sendable {
    public let completedRuns: [CleanupHistoryRun]
    public let protectedRecordCount: Int
    /// Ids of Trash moves that were put back (#159), from the put-back records that succeeded.
    public let putBackIDs: Set<String>
    /// Ids of Trash moves whose items were deleted from the Trash (#359), or may have been.
    public let emptiedIDs: Set<String>
    public init(records: [CleanupRecord]) {
        let putBack = Set(records.filter { $0.isPutBack && $0.state == .succeeded }.compactMap(\.putBackOf))
        putBackIDs = putBack
        let emptied = TrashLedger(records).emptiedIDs
        emptiedIDs = emptied
        let groups = Dictionary(grouping: records, by: \.batchID)
        var completed: [CleanupHistoryRun] = []
        var protected = 0
        for (id, records) in groups {
            let batch = ReviewedBatch(records)
            if batch.isInterrupted { protected += records.count }
            else {
                completed.append(CleanupHistoryRun(id: id, records: batch.shown, putBackIDs: putBack.intersection(batch.items.map(\.id)),
                                                   emptiedIDs: emptied.intersection(batch.items.map(\.id)), reviewRecords: batch.reviews))
            }
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
    /// The change between two readings, so no field lands in the wrong half (#416).
    public init(from before: CapacitySample, to after: CapacitySample) {
        self.init(beforeAvailable: before.available, afterAvailable: after.available, beforeTotal: before.total, afterTotal: after.total,
                  beforeVolumeID: before.volumeID, afterVolumeID: after.volumeID, beforeMetric: before.metric.rawValue,
                  afterMetric: after.metric.rawValue, beforeDate: before.date, afterDate: after.date)
    }
    /// The change from this observation's after reading to `now` (#416). Not through `init(from:to:)`: the stored metric is a
    /// string, and reading it back as a `CapacityMetric` could fail.
    public func continued(to now: CapacitySample) -> CleanupCapacityObservation {
        CleanupCapacityObservation(beforeAvailable: afterAvailable, afterAvailable: now.available, beforeTotal: afterTotal, afterTotal: now.total,
                                   beforeVolumeID: afterVolumeID, afterVolumeID: now.volumeID, beforeMetric: afterMetric,
                                   afterMetric: now.metric.rawValue, beforeDate: afterDate, afterDate: now.date)
    }
    public var observedChange: Int64? {
        guard let id = beforeVolumeID, id == afterVolumeID, beforeMetric == afterMetric,
              let total = beforeTotal, total > 0, total == afterTotal,
              let before = beforeAvailable, let after = afterAvailable,
              before >= 0, after >= 0, before <= total, after <= total, afterDate >= beforeDate else { return nil }
        return after - before
    }
}
