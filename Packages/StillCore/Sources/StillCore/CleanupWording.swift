import Foundation

/// How Results, History and Recovery describe a record, per action. Records from the
/// Downloads-only flow carry the "moveToTrash" action, so they read as Trash moves.
extension CleanupRecord {
    static let previewPrefix = "Preview only:"
    private var isTrash: Bool { cleanupAction == .trash }
    private var isDelete: Bool { cleanupAction == .delete }
    private var isTool: Bool { cleanupAction == .tool }
    private var isEvict: Bool { cleanupAction == .evict }
    /// Checked with Preview only on: every check passed and nothing changed.
    public var wasPreviewed: Bool { previewOnly == true && state == .skipped && message.hasPrefix(Self.previewPrefix) }
    public var actionTitle: String { isDelete ? "Delete permanently" : isTrash ? "Move to Trash" : isTool ? "Run its cleanup command" : isEvict ? "Remove local copy" : action }
    public var outcomeTitle: String {
        if wasPreviewed { return isDelete ? "Would delete" : isTrash ? "Would move to Trash" : isEvict ? "Would remove local copy" : "Would run" }
        switch state {
        case .succeeded: return isDelete ? "Deleted" : isTrash ? "Moved to Trash" : isTool ? "Cleaned" : isEvict ? "Removed local copy" : "Done"
        case .skipped: return "Skipped"
        case .failed: return partlyRemoved == true ? (isEvict ? "Partly removed local copies" : "Partly removed") : "Failed"
        case .cancelled, .pending: return "Not started"
        case .intent, .unknown: return "Unresolved"
        }
    }
    public var recoveryStateText: String {
        switch state {
        case .pending: return "Not started · Nothing was changed"
        case .intent, .unknown: return isDelete || isTool ? "Unresolved · It may be partly deleted" : isTrash ? "Unresolved · It may or may not be in the Trash"
            : isEvict ? "Unresolved · Local copies may be removed · The original stays in iCloud" : "Unresolved · Outcome unknown"
        case .succeeded: return "Recorded success · " + outcomeTitle
        case .failed:
            guard partlyRemoved == true else { return "Recorded failure · Not changed" }
            return isEvict ? "Recorded failure · Some local copies were removed · The originals stay in iCloud" : "Recorded failure · It may be partly deleted"
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
        let deleted = done.contains { $0.cleanupAction == .delete || $0.cleanupAction == .tool }
        let trashed = done.contains { $0.cleanupAction == .trash }
        let evicted = done.contains { $0.cleanupAction == .evict }
        let parts = [deleted ? "deleted" : nil, trashed ? "moved to Trash" : nil, evicted ? "removed local iCloud copies" : nil].compactMap { $0 }
        guard let first = parts.first else {
            let partly = records.filter { $0.partlyRemoved == true }
            if partly.isEmpty { return "Cleanup · Nothing changed" }
            return partly.allSatisfy { $0.cleanupAction == .evict } ? "Cleanup · Partly removed local iCloud copies" : "Cleanup · Partly deleted"
        }
        let phrase = parts.count == 1 ? first : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        return "Cleanup · " + phrase.prefix(1).uppercased() + phrase.dropFirst()
    }
}

extension CleanupRecoverySnapshot {
    /// What a missing original can and can't mean, for the actions the unresolved items were taking.
    public var unresolvedNotice: String {
        let actions = Set(interruptedBatches.flatMap(\.records).filter { $0.state == .intent || $0.state == .unknown }.compactMap(\.cleanupAction))
        let deletes = actions.contains(.delete) || actions.contains(.tool), trashes = actions.contains(.trash)
        let tail = (actions.contains(.evict) ? " Removing a local copy never deletes the original; it stays in iCloud and downloads again when opened." : "")
            + " Current file locations have not been inspected."
        if deletes && trashes { return "A missing original may have reached the Trash or been permanently deleted, possibly only in part." + tail }
        if deletes { return "A missing original may have been permanently deleted, possibly only in part. Deleted items can’t be restored from the Trash." + tail }
        if trashes { return "A missing original does not prove it reached the Trash." + tail }
        if actions.contains(.evict) { return "A missing local copy means only that it was removed from this Mac." + tail }
        return "Nothing was started for the unfinished items." + tail
    }
}
