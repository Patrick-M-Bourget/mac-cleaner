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

    fileprivate static let partlyDeletedRecovery = "Failed · It may be partly deleted"

    static let unknown = ActionWording(title: "", previewOutcome: "Would run", succeeded: "Done",
                                       partlyFailed: "Partly deleted", unresolved: "Unfinished · Outcome unknown",
                                       partlyFailedRecovery: partlyDeletedRecovery, historyPhrase: nil)
    /// Putting an item back from the Trash (#159): a rename, never a delete.
    static let putBack = ActionWording(title: "Put back from the Trash", previewOutcome: "Would put back", succeeded: "Put back",
                                       partlyFailed: "Failed", unresolved: "Unfinished · It is either back in its folder or still in the Trash",
                                       partlyFailedRecovery: "Failed · Not changed", historyPhrase: nil)
    /// Deleting an item CacheDrop moved to the Trash from the Trash (#359).
    static let emptyFromTrash = ActionWording(title: "Delete from the Trash", previewOutcome: "Would delete from the Trash", succeeded: "Deleted from the Trash",
                                              partlyFailed: "Partly deleted", unresolved: "Unfinished · It may be partly deleted",
                                              partlyFailedRecovery: partlyDeletedRecovery, historyPhrase: nil)
}

extension CleanupAction {
    public var wording: ActionWording {
        switch self {
        case .delete:
            ActionWording(title: "Delete permanently", previewOutcome: "Would delete", succeeded: "Deleted",
                          partlyFailed: "Partly deleted", unresolved: "Unfinished · It may be partly deleted",
                          partlyFailedRecovery: ActionWording.partlyDeletedRecovery, historyPhrase: "deleted")
        case .tool:
            ActionWording(title: "Run its cleanup command", previewOutcome: "Would run", succeeded: "Deleted",
                          partlyFailed: "Partly deleted", unresolved: "Unfinished · It may be partly deleted",
                          partlyFailedRecovery: ActionWording.partlyDeletedRecovery, historyPhrase: "deleted")
        case .trash:
            ActionWording(title: "Move to Trash", previewOutcome: "Would move to Trash",
                          succeeded: "Moved to Trash", partlyFailed: "Partly moved to Trash", unresolved: "Unfinished · It may or may not be in the Trash",
                          partlyFailedRecovery: ActionWording.partlyDeletedRecovery, historyPhrase: "moved to Trash")
        case .evict:
            ActionWording(title: "Remove local copy", previewOutcome: "Would remove local copy", succeeded: "Removed local copy", partlyFailed: "Partly removed local copies",
                          unresolved: "Unfinished · Local copies may be removed · The original stays in iCloud",
                          partlyFailedRecovery: "Failed · Some local copies were removed · The originals stay in iCloud", historyPhrase: "removed local iCloud copies")
        case .guidance:
            ActionWording(title: "Guidance only", previewOutcome: "Would run", succeeded: "Done",
                          partlyFailed: "Partly deleted", unresolved: "Unfinished · Outcome unknown",
                          partlyFailedRecovery: ActionWording.partlyDeletedRecovery, historyPhrase: nil)
        }
    }
}

/// How Results, History and Recovery describe a record, per action (`ActionWording`). Records from the
/// Downloads-only flow carry the "moveToTrash" action, so they read as Trash moves.
extension CleanupRecord {
    static let previewPrefix = "Dry run:"
    /// What dry-run records journaled before the switch moved to Settings start with.
    static let legacyPreviewPrefix = "Preview only:"
    private var wording: ActionWording { cleanupAction?.wording ?? (isPutBack ? .putBack : isEmptyFromTrash ? .emptyFromTrash : .unknown) }
    /// Checked with the dry run on: every check passed and nothing changed.
    public var wasDryRun: Bool {
        dryRun == true && state == .skipped && (message.hasPrefix(Self.previewPrefix) || message.hasPrefix(Self.legacyPreviewPrefix))
    }
    /// The app or plug-in product an uninstall removed, by name (e.g. "Synth"); nil for its files and for any other record.
    public var uninstalledName: String? {
        ruleID.map(AppRuleFamily.namingRuleIDs.contains) == true ? originalURL.deletingPathExtension().lastPathComponent : nil
    }
    public var actionTitle: String { cleanupAction?.wording.title ?? (isPutBack || isEmptyFromTrash ? wording.title : action) }
    public var outcomeTitle: String {
        if wasDryRun { return wording.previewOutcome }
        if let recoveryFinding { return recoveryFinding.title(putBack: isPutBack, emptying: isEmptyFromTrash) }
        switch state {
        case .succeeded: return finishedAfterStop ? "Removed" : wording.succeeded
        case .skipped: return "Skipped"
        case .failed: return partlyRemoved == true ? wording.partlyFailed : "Failed"
        case .cancelled, .pending: return "Not started"
        case .intent, .unknown: return "Unresolved"
        }
    }
    /// Success messages that only restate the outcome, which History leaves out (#312).
    private static let restatesOutcome: Set<String> = ["Deleted", "Permanently removed", "Moved to Trash", "Put back from the Trash", "Deleted from the Trash"]
    /// Progress messages journaled in words kept off screen ("approval", "records"), and how they read (#571). The journal
    /// keeps what it stored; only what's drawn changes.
    static let plainProgress = ["Approved; not started": "Not started", "Started; outcome not yet recorded": "Started · Outcome unknown"]
    /// The record's message as every page draws it.
    public var shownMessage: String { Self.plainProgress[message] ?? message }
    /// History's line for a record: its outcome, then its message when that adds something (#312).
    public var outcomeLine: String {
        let shown = shownMessage
        let restates = shown == outcomeTitle || (state == .succeeded && Self.restatesOutcome.contains(shown))
        return restates ? outcomeTitle : outcomeTitle + " · " + shown
    }
    public var recoveryStateText: String {
        switch state {
        case .pending: return "Not started · Nothing was changed"
        case .intent, .unknown: return wording.unresolved
        case .succeeded: return "Finished · " + outcomeTitle
        case .failed: return partlyRemoved == true ? wording.partlyFailedRecovery : "Failed · Not changed"
        case .skipped: return wasDryRun ? "Dry run · " + outcomeTitle : "Skipped · Not changed"
        case .cancelled: return "Canceled · Not started"
        }
    }
}

extension CleanupHistoryRun {
    /// Every record was checked with the dry run on; nothing changed on disk.
    public var isPreview: Bool { !records.isEmpty && records.allSatisfy { $0.dryRun == true } }
    /// A put back from the Trash (#159), recorded as its own run.
    public var isPutBack: Bool { !records.isEmpty && records.allSatisfy(\.isPutBack) }
    /// A deletion of CacheDrop's own items from the Trash (#359), recorded as its own run.
    public var isEmptyFromTrash: Bool { !records.isEmpty && records.allSatisfy(\.isEmptyFromTrash) }
    /// The figure a History row leads with (#569, Decision 127). A cleanup leads with the measured freed space Results leads
    /// with (Decision 93), "Unknown" when a reading is missing, and so does Empty from Trash, which frees space too; a run
    /// that only moved items to the Trash, with what went there; a Put back, with what it returned; a dry run, with what it
    /// would affect.
    public struct Headline: Sendable, Equatable {
        public let bytes: Int64?
        public let note: String
    }
    public var headline: Headline {
        if isPreview { return Headline(bytes: plannedBytes, note: "Dry run") }
        if isPutBack { return Headline(bytes: plannedBytes, note: "From Trash") }
        if records.movedOnlyToTrash { return Headline(bytes: plannedBytes, note: "In Trash") }
        return Headline(bytes: MeasuredFreedSpace.shown(measuredFreedBytes), note: "Freed")
    }
    /// "A", "A and B", "A, B and C".
    private static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
    public var title: String {
        if isPreview { return "Dry run · Nothing changed" }
        if isEmptyFromTrash {
            let deleted = records.filter { $0.state == .succeeded }.count
            return deleted == 0 ? "Empty from the Trash · Nothing changed" : "Emptied from the Trash · " + (deleted == 1 ? "1 item" : "\(deleted) items")
        }
        if isPutBack {
            return records.contains { $0.state == .succeeded } ? "Put back from the Trash" : "Put back · Nothing changed"
        }
        let done = records.filter { $0.state == .succeeded }
        // An uninstall (#177, Decision 51): "Uninstalled <App> · N items".
        // An app's own uninstaller goes with it (#285) and isn't named.
        // A plug-in product (#176) is named once for all its formats.
        let apps = done.compactMap(\.uninstalledName)
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
