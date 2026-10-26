import Foundation

/// How Results, History and Recovery describe a record, per action. Records from the
/// Downloads-only flow carry the "moveToTrash" action, so they read as Trash moves.
extension CleanupRecord {
    static let previewPrefix = "Preview only:"
    private var isTrash: Bool { action == CleanupAction.trash.rawValue }
    private var isDelete: Bool { action == CleanupAction.delete.rawValue }
    private var isTool: Bool { action == CleanupAction.tool.rawValue }
    /// Checked with Preview only on: every check passed and nothing changed.
    public var wasPreviewed: Bool { previewOnly == true && state == .skipped && message.hasPrefix(Self.previewPrefix) }
    public var actionTitle: String { isDelete ? "Delete permanently" : isTrash ? "Move to Trash" : isTool ? "Run its cleanup command" : action }
    public var outcomeTitle: String {
        if wasPreviewed { return isDelete ? "Would delete" : isTrash ? "Would move to Trash" : "Would run" }
        switch state {
        case .succeeded: return isDelete ? "Deleted" : isTrash ? "Moved to Trash" : isTool ? "Cleaned" : "Done"
        case .skipped: return "Skipped"
        case .failed: return partlyRemoved == true ? "Partly removed" : "Failed"
        case .cancelled, .pending: return "Not started"
        case .intent, .unknown: return "Unresolved"
        }
    }
    public var recoveryStateText: String {
        switch state {
        case .pending: return "Not started · Nothing was changed"
        case .intent, .unknown: return isDelete || isTool ? "Unresolved · It may be partly deleted" : isTrash ? "Unresolved · It may or may not be in the Trash" : "Unresolved · Outcome unknown"
        case .succeeded: return "Recorded success · " + outcomeTitle
        case .failed: return partlyRemoved == true ? "Recorded failure · It may be partly deleted" : "Recorded failure · Not changed"
        case .skipped: return wasPreviewed ? "Preview · " + outcomeTitle : "Recorded skip · Not changed"
        case .cancelled: return "Recorded cancellation · Not started"
        }
    }
}

extension CleanupHistoryRun {
    /// Every record was checked with Preview only on; nothing changed on disk.
    public var isPreview: Bool { !records.isEmpty && records.allSatisfy { $0.previewOnly == true } }
    public var title: String {
        if isPreview { return "Preview · Nothing changed" }
        let done = records.filter { $0.state == .succeeded }
        let deleted = done.contains { $0.action == CleanupAction.delete.rawValue || $0.action == CleanupAction.tool.rawValue }
        let trashed = done.contains { $0.action == CleanupAction.trash.rawValue }
        switch (deleted, trashed) {
        case (true, true): return "Cleanup · Deleted and moved to Trash"
        case (true, false): return "Cleanup · Deleted"
        case (false, true): return "Cleanup · Moved to Trash"
        case (false, false): return records.contains { $0.partlyRemoved == true } ? "Cleanup · Partly deleted" : "Cleanup · Nothing changed"
        }
    }
}

extension CleanupRecoverySnapshot {
    /// What a missing original can and can't mean, for the actions the unresolved items were taking.
    public var unresolvedNotice: String {
        let actions = Set(interruptedBatches.flatMap(\.records).filter { $0.state == .intent || $0.state == .unknown }.map(\.action))
        let deletes = actions.contains(CleanupAction.delete.rawValue) || actions.contains(CleanupAction.tool.rawValue), trashes = actions.contains(CleanupAction.trash.rawValue)
        let tail = " Current file locations have not been inspected."
        if deletes && trashes { return "A missing original may have reached the Trash or been permanently deleted, possibly only in part." + tail }
        if deletes { return "A missing original may have been permanently deleted, possibly only in part. Deleted items can’t be restored from the Trash." + tail }
        if trashes { return "A missing original does not prove it reached the Trash." + tail }
        return "Nothing was started for the unfinished items." + tail
    }
}
