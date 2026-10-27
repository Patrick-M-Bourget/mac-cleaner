import Foundation

/// Everything CacheDrop says that depends on the action, in one place: the plan, the review, Results, History and Recovery.
public struct ActionWording: Sendable {
    /// What the action is, e.g. "Move to Trash".
    public let title: String
    /// With the dry run on, e.g. "Would move to Trash".
    public let previewOutcome: String
    public let succeeded: String
    public let partlyFailed: String
    public let unresolved: String
    public let partlyFailedRecovery: String
    /// In a History run's title, e.g. "moved to Trash"; nil for an action that never changes anything.
    public let historyPhrase: String?

    static let unknown = ActionWording(title: "", previewOutcome: "Would run", succeeded: "Done",
                                       partlyFailed: "Partly removed", unresolved: "Unresolved · Outcome unknown",
                                       partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: nil)
    /// Putting an item back from the Trash (#159): a rename, never a delete.
    static let putBack = ActionWording(title: "Put back from Trash", previewOutcome: "Would put back", succeeded: "Put back",
                                       partlyFailed: "Failed", unresolved: "Unresolved · It is either back in its folder or still in the Trash",
                                       partlyFailedRecovery: "Recorded failure · Not changed", historyPhrase: nil)
}

extension CleanupAction {
    public var wording: ActionWording {
        switch self {
        case .delete:
            ActionWording(title: "Delete permanently", previewOutcome: "Would delete", succeeded: "Deleted",
                          partlyFailed: "Partly removed", unresolved: "Unresolved · It may be partly deleted",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: "deleted")
        case .tool:
            ActionWording(title: "Run its cleanup command", previewOutcome: "Would run", succeeded: "Cleaned",
                          partlyFailed: "Partly removed", unresolved: "Unresolved · It may be partly deleted",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: "deleted")
        case .trash:
            ActionWording(title: "Move to Trash", previewOutcome: "Would move to Trash",
                          succeeded: "Moved to Trash", partlyFailed: "Partly removed", unresolved: "Unresolved · It may or may not be in the Trash",
                          partlyFailedRecovery: "Recorded failure · It may be partly deleted", historyPhrase: "moved to Trash")
        case .evict:
            ActionWording(title: "Remove local copy", previewOutcome: "Would remove local copy", succeeded: "Removed local copy", partlyFailed: "Partly removed local copies",
                          unresolved: "Unresolved · Local copies may be removed · The original stays in iCloud",
                          partlyFailedRecovery: "Recorded failure · Some local copies were removed · The originals stay in iCloud", historyPhrase: "removed local iCloud copies")
        case .guidance:
            ActionWording(title: "Guidance only", previewOutcome: "Would run", succeeded: "Done",
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
    private var wording: ActionWording { cleanupAction?.wording ?? (isPutBack ? .putBack : .unknown) }
    /// Checked with the dry run on: every check passed and nothing changed.
    public var wasPreviewed: Bool {
        previewOnly == true && state == .skipped && (message.hasPrefix(Self.previewPrefix) || message.hasPrefix(Self.legacyPreviewPrefix))
    }
    public var actionTitle: String { cleanupAction?.wording.title ?? (isPutBack ? ActionWording.putBack.title : action) }
    public var outcomeTitle: String {
        if wasPreviewed { return wording.previewOutcome }
        switch state {
        case .succeeded: return finishedAfterStop ? "Removed" : wording.succeeded
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
    /// A put back from the Trash (#159), recorded as its own run.
    public var isPutBack: Bool { !records.isEmpty && records.allSatisfy(\.isPutBack) }
    /// "A", "A and B", "A, B and C".
    private static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
    public var title: String {
        if isPreview { return "Dry run · Nothing changed" }
        if isPutBack {
            return records.contains { $0.state == .succeeded } ? "Put back from Trash" : "Put back · Nothing changed"
        }
        let done = records.filter { $0.state == .succeeded }
        // An uninstall (#177, Decision 51): "Uninstalled <App> · N items".
        // An app's own uninstaller goes with it (#285) and isn't named.
        // A plug-in product (#176) is named once for all its formats.
        let apps = done.filter { $0.ruleID.map(AppRuleFamily.namingRuleIDs.contains) == true }.map { $0.originalURL.deletingPathExtension().lastPathComponent }
            .filter { !ApplicationsInventory.isUninstallerName($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if !apps.isEmpty {
            return "Uninstalled \(Self.list(apps)) · " + (done.count == 1 ? "1 item" : "\(done.count) items")
        }
        var parts: [String] = []
        for action in [CleanupAction.delete, .tool, .trash, .evict] where done.contains(where: { $0.cleanupAction == action }) {
            if let phrase = action.wording.historyPhrase, !parts.contains(phrase) { parts.append(phrase) }
        }
        guard !parts.isEmpty else {
            let partly = records.filter { $0.partlyRemoved == true }
            if partly.isEmpty { return "Cleanup · Nothing changed" }
            return partly.allSatisfy { $0.cleanupAction == .evict } ? "Cleanup · Partly removed local iCloud copies" : "Cleanup · Partly deleted"
        }
        let phrase = Self.list(parts)
        return "Cleanup · " + phrase.prefix(1).uppercased() + phrase.dropFirst()
    }
}

extension CleanupRecoverySnapshot {
    /// What a missing original can and can't mean, for the actions the unresolved items were taking.
    public var unresolvedNotice: String {
        let unresolved = interruptedBatches.flatMap(\.records).filter { $0.state == .intent || $0.state == .unknown }
        let actions = Set(unresolved.compactMap(\.cleanupAction))
        let deletes = actions.contains(.delete) || actions.contains(.tool), trashes = actions.contains(.trash)
        let tail = (actions.contains(.evict) ? " Removing a local copy never deletes the original; it stays in iCloud and downloads again when opened." : "")
            + " Current file locations have not been inspected."
        if deletes && trashes { return "A missing original may have reached the Trash or been permanently deleted, possibly only in part." + tail }
        if deletes { return "A missing original may have been permanently deleted, possibly only in part. Deleted items can’t be restored from the Trash." + tail }
        if trashes { return "A missing original does not prove it reached the Trash." + tail }
        if unresolved.contains(where: \.isPutBack) { return "An item being put back is either back in its folder or still in the Trash. Nothing was deleted." + tail }
        if actions.contains(.evict) { return "A missing local copy means only that it was removed from this Mac." + tail }
        return "Nothing was started for the unfinished items." + tail
    }
}
