import Foundation

/// Everything Still says that depends on the action, in one place: the plan, the review, Results, History and Recovery.
public struct ActionWording: Sendable {
    /// What the action is, e.g. "Move to Trash".
    public let title: String
    /// Overview's phrase for the titles of the rules it applies to; rules whose phrases share `overviewGroup` are listed together.
    public let overviewGroup: Int
    public let overview: @Sendable (String) -> String
    /// With the dry run on, e.g. "Would move to Trash".
    public let previewOutcome: String
    public let succeeded: String
    public let partlyFailed: String
    public let unresolved: String
    public let partlyFailedRecovery: String
    /// In a History run's title, e.g. "moved to Trash"; nil for an action that never changes anything.
    public let historyPhrase: String?

    static let unknown = ActionWording(title: "", overviewGroup: 0, overview: { "Clear " + $0 }, previewOutcome: "Would run", succeeded: "Done",
                                       partlyFailed: "Partly removed", unresolved: "Unresolved · Outcome unknown",
                                       partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: nil)
}

extension CleanupAction {
    public var wording: ActionWording {
        switch self {
        case .delete:
            ActionWording(title: "Delete permanently", overviewGroup: 0, overview: { "Clear " + $0 }, previewOutcome: "Would delete", succeeded: "Deleted",
                          partlyFailed: "Partly removed", unresolved: "Unresolved · It may be partly deleted",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: "deleted")
        case .tool:
            ActionWording(title: "Run its cleanup command", overviewGroup: 0, overview: { "Clear " + $0 }, previewOutcome: "Would run", succeeded: "Cleaned",
                          partlyFailed: "Partly removed", unresolved: "Unresolved · It may be partly deleted",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: "deleted")
        case .trash:
            ActionWording(title: "Move to Trash", overviewGroup: 1, overview: { "Move " + $0 + " to Trash" }, previewOutcome: "Would move to Trash",
                          succeeded: "Moved to Trash", partlyFailed: "Partly removed", unresolved: "Unresolved · It may or may not be in the Trash",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: "moved to Trash")
        case .evict:
            ActionWording(title: "Remove local copy", overviewGroup: 2, overview: { _ in "Remove local copies · Originals stay in iCloud" },
                          previewOutcome: "Would remove local copy", succeeded: "Removed local copy", partlyFailed: "Partly removed local copies",
                          unresolved: "Unresolved · Local copies may be removed · The original stays in iCloud",
                          partlyFailedRecovery: "Recorded failure · Some local copies were removed · The originals stay in iCloud", historyPhrase: "removed local iCloud copies")
        case .guidance:
            ActionWording(title: "Guidance only", overviewGroup: 0, overview: { "Clear " + $0 }, previewOutcome: "Would run", succeeded: "Done",
                          partlyFailed: "Partly removed", unresolved: "Unresolved · Outcome unknown",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: nil)
        }
    }
}

/// How Results, History and Recovery describe a record, per action (`ActionWording`). Records from the
/// Downloads-only flow carry the "moveToTrash" action, so they read as Trash moves.
extension CleanupRecord {
    static let previewPrefix = "Dry run:"
    /// What dry-run records journaled before the switch moved to Settings start with.
    static let legacyPreviewPrefix = "Preview only:"
    private var wording: ActionWording { cleanupAction?.wording ?? .unknown }
    /// Checked with the dry run on: every check passed and nothing changed.
    public var wasPreviewed: Bool {
        previewOnly == true && state == .skipped && (message.hasPrefix(Self.previewPrefix) || message.hasPrefix(Self.legacyPreviewPrefix))
    }
    public var actionTitle: String { cleanupAction?.wording.title ?? action }
    public var outcomeTitle: String {
        if wasPreviewed { return wording.previewOutcome }
        switch state {
        case .succeeded: return wording.succeeded
        case .skipped: return "Skipped"
        case .failed: return partlyRemoved == true ? wording.partlyFailed : "Failed"
        case .cancelled, .pending: return "Not started"
        case .intent, .unknown: return "Unresolved"
        }
    }
    public var recoveryStateText: String {
        switch state {
        case .pending: return "Not started · Nothing was changed"
        case .intent, .unknown: return wording.unresolved
        case .succeeded: return "Recorded success · " + outcomeTitle
        case .failed: return partlyRemoved == true ? wording.partlyFailedRecovery : "Recorded failure · Not changed"
        case .skipped: return wasPreviewed ? "Dry run · " + outcomeTitle : "Recorded skip · Not changed"
        case .cancelled: return "Recorded cancellation · Not started"
        }
    }
}

extension CleanupHistoryRun {
    /// Every record was checked with the dry run on; nothing changed on disk.
    public var isPreview: Bool { !records.isEmpty && records.allSatisfy { $0.previewOnly == true } }
    public var title: String {
        if isPreview { return "Dry run · Nothing changed" }
        let done = records.filter { $0.state == .succeeded }
        var parts: [String] = []
        for action in [CleanupAction.delete, .tool, .trash, .evict] where done.contains(where: { $0.cleanupAction == action }) {
            if let phrase = action.wording.historyPhrase, !parts.contains(phrase) { parts.append(phrase) }
        }
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
