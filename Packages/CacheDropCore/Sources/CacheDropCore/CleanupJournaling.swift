import Foundation
import Darwin

/// Raw values are stored in the journal (#448): a renamed case keeps its string.
public enum CleanupTargetState: String, Codable, Sendable {
    case pending = "pending", intent = "intent", succeeded = "succeeded", failed = "failed", skipped = "skipped", cancelled = "cancelled", unknown = "unknown"
}
/// One approved item's persisted identity, action and latest outcome, retained for History and recovery.
public struct CleanupRecord: Codable, Sendable, Identifiable {
    public internal(set) var id: String
    public let batchID: UUID
    public let originalURL: URL
    public let resourceID: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    public var state: CleanupTargetState
    public var trashURL: URL?
    public var message: String
    public let observedAt: Date
    public let scopeURL: URL
    public let scopeResourceID: String
    public let volumeID: String?
    /// Records written by the Downloads-only flow (policy 1) only; catalog records leave these empty.
    public let downloadsURL: URL?
    public let downloadsResourceID: String?
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let action: String
    public let policyVersion: Int
    public var outcomeRecordedAt: Date?
    public let approvedAt: Date
    /// Catalog records only. Optional so journals written before the catalog still decode.
    public var ruleID: String? = nil
    /// True when the dry run was on: the item was checked and nothing changed on disk.
    public var previewOnly: Bool? = nil
    /// Available space read right before and right after this item.
    public var itemCapacity: CleanupCapacityObservation? = nil
    /// On a run's last completed Docker prune (#411): available space right after it, then once more a minute after the run,
    /// since Docker hands freed space back to macOS later. Nil on every other record and in older journals.
    public var settledCapacity: CleanupCapacityObservation? = nil
    /// The end of a tool action's output, shown in results.
    public var toolOutput: String? = nil
    /// `action` as a type; nil for an action this version doesn't know.
    public var cleanupAction: CleanupAction? { CleanupAction(rawValue: action) }
    /// True when a delete or tool action failed after it may have removed part of the item.
    public var partlyRemoved: Bool? = nil
    /// The item's name when it isn't its file name (a model, a simulator); nil in older journals.
    public var itemName: String? = nil
    /// What a per-item tool command took for it, such as a simulator's UDID; nil in older journals.
    public var toolItem: String? = nil
    /// On a put-back record (#159), the id of the Trash move it undoes; nil on every other record and in older journals.
    public var putBackOf: String? = nil
    /// On a record of deleting an item from the Trash (#359), the id of the Trash move whose item it deletes; nil on every
    /// other record and in older journals.
    public var emptyOf: String? = nil
    /// True when a daemon-backed tool was stopped: only the wait stopped, and the work may still be finishing (#185, #190).
    public var mayStillBeFinishing: Bool? = nil
    /// What such an item measured a little after the run (#190); nil until then, and in older journals.
    public var laterMeasurement: LaterMeasurement? = nil
    /// On a reviewed record (#309), the id of the interrupted record it resolves; nil on every other record and in older journals.
    public var reviewOf: String? = nil
    /// On a reviewed record, and on the record History shows for it, what checking against disk found (#309).
    public var recoveryFinding: RecoveryFinding? = nil
    /// The journal's stored keys (#448): a renamed property keeps its key here, so older journals still read. A new field
    /// needs its key here, or it is never saved, and in the StoredKeys fixture.
    private enum CodingKeys: String, CodingKey {
        case id = "id", batchID = "batchID", originalURL = "originalURL", resourceID = "resourceID", logicalBytes = "logicalBytes",
            allocatedBytes = "allocatedBytes", state = "state", trashURL = "trashURL", message = "message", observedAt = "observedAt",
            scopeURL = "scopeURL", scopeResourceID = "scopeResourceID", volumeID = "volumeID", downloadsURL = "downloadsURL",
            downloadsResourceID = "downloadsResourceID", modifiedSeconds = "modifiedSeconds", modifiedNanoseconds = "modifiedNanoseconds",
            action = "action", policyVersion = "policyVersion", outcomeRecordedAt = "outcomeRecordedAt", approvedAt = "approvedAt",
            ruleID = "ruleID", previewOnly = "previewOnly", itemCapacity = "itemCapacity", settledCapacity = "settledCapacity",
            toolOutput = "toolOutput", partlyRemoved = "partlyRemoved", itemName = "itemName", toolItem = "toolItem",
            putBackOf = "putBackOf", emptyOf = "emptyOf", mayStillBeFinishing = "mayStillBeFinishing",
            laterMeasurement = "laterMeasurement", reviewOf = "reviewOf", recoveryFinding = "recoveryFinding"
    }
}
/// Durable batch claims, item intents and outcomes used by cleanup, History and recovery.
public protocol CleanupJournaling: Sendable {
    /// Writes every record as pending in one transaction; false when the batch was already claimed.
    func claim(batchID: UUID, records: [CleanupRecord]) throws -> Bool
    func intent(_ record: CleanupRecord) throws
    func outcome(_ record: CleanupRecord) throws
    func records() throws -> [CleanupRecord]
    /// Adds new records in one transaction, never replacing one (#309); throws, adding none, when any id is taken.
    func append(_ records: [CleanupRecord]) throws
}
public final class CleanupCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
public struct CleanupExecutionProgress: Sendable {
    public let resolved: Int
    public let total: Int
    public let last: CleanupRecord?
}
