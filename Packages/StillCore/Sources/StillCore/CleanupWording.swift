import Foundation

/// How Results, History and Recovery describe a record, per action. Records from the
/// Downloads-only flow carry the "moveToTrash" action, so they read as Trash moves.
extension CleanupRecord {
    static let previewPrefix = "Preview only:"
    private var isTrash: Bool { action == CleanupAction.trash.rawValue }
    private var isDelete: Bool { action == CleanupAction.delete.rawValue }
    /// Checked with Preview only on: every check passed and nothing changed.
    public var wasPreviewed: Bool { previewOnly == true && state == .skipped && message.hasPrefix(Self.previewPrefix) }
    public var actionTitle: String { isDelete ? "Delete permanently" : isTrash ? "Move to Trash" : action }
    public var outcomeTitle: String {
        if wasPreviewed { return isDelete ? "Would delete" : isTrash ? "Would move to Trash" : "Would run" }
        switch state {
        case .succeeded: return isDelete ? "Deleted" : isTrash ? "Moved to Trash" : "Done"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        case .cancelled, .pending: return "Not started"
        case .intent, .unknown: return "Unresolved"
        }
    }
    public var recoveryStateText: String {
        switch state {
        case .pending: return "Not started · Nothing was changed"
        case .intent, .unknown: return isDelete ? "Unresolved · It may be partly deleted" : isTrash ? "Unresolved · It may or may not be in the Trash" : "Unresolved · Outcome unknown"
        case .succeeded: return "Recorded success · " + outcomeTitle
        case .failed: return "Recorded failure · Not changed"
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
        let deleted = done.contains { $0.action == CleanupAction.delete.rawValue }
        let trashed = done.contains { $0.action == CleanupAction.trash.rawValue }
        switch (deleted, trashed) {
        case (true, true): return "Cleanup · Deleted and moved to Trash"
        case (true, false): return "Cleanup · Deleted"
        case (false, true): return "Cleanup · Moved to Trash"
        case (false, false): return "Cleanup · Nothing changed"
        }
    }
}
