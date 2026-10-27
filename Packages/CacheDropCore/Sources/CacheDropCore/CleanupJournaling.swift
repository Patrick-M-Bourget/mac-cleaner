import Foundation
import Darwin

public enum CleanupTargetState: String, Codable, Sendable { case pending, intent, succeeded, failed, skipped, cancelled, unknown }
public struct CleanupRecord: Codable, Sendable, Identifiable {
    public let id: String
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
    public var capacityObservation: CleanupCapacityObservation?
    public var outcomeRecordedAt: Date?
    public let approvedAt: Date
    /// Catalog records only. Optional so journals written before the catalog still decode.
    public var ruleID: String? = nil
    /// True when the dry run was on: the item was checked and nothing changed on disk.
    public var previewOnly: Bool? = nil
    /// Available space read right before and right after this item.
    public var itemCapacity: CleanupCapacityObservation? = nil
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
    /// True when a daemon-backed tool was stopped: only the wait stopped, and the work may still be finishing (#185, #190).
    public var mayStillBeFinishing: Bool? = nil
    /// What such an item measured a little after the run (#190); nil until then, and in older journals.
    public var laterMeasurement: LaterMeasurement? = nil
}
public protocol CleanupJournaling: Sendable {
    /// Writes every record as pending in one transaction; false when the batch was already claimed.
    func claim(batchID: UUID, records: [CleanupRecord]) throws -> Bool
    func intent(_ record: CleanupRecord) throws
    func outcome(_ record: CleanupRecord) throws
    func records() throws -> [CleanupRecord]
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
