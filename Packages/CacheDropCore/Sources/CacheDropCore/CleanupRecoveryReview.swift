import Foundation
import Darwin

/// Where an interrupted cleanup's item was found when checked against disk (#309).
public enum RecoveryFinding: String, Codable, Sendable {
    /// Pending: the journal shows it never started, so nothing is checked.
    case notStarted
    /// At its original path, with the identity it had at approval.
    case atOriginalLocation
    /// In the Trash, with the identity it had at approval.
    case inTrash
    /// Neither at its original path nor in the Trash.
    case gone
    /// CacheDrop can't tell: something else is at its path, it was found elsewhere, or a place couldn't be read.
    /// The user confirms it.
    case unknown
}

/// One unresolved record of an interrupted batch, with what a read-only check found.
public struct CleanupRecoveryItem: Sendable, Identifiable {
    public let record: CleanupRecord
    public let finding: RecoveryFinding
    /// Where the item was found, when not at its original path (the Trash item, or a delete's renamed-aside copy).
    public let foundURL: URL?
    /// Why the finding is what it is, in a sentence.
    public let detail: String
    public var id: String { record.id }
    /// Stays unknown, so the user confirms it before it is marked reviewed.
    public var needsConfirmation: Bool { finding == .unknown }
    public var title: String { finding.title(putBack: record.isPutBack, emptying: record.isEmptyFromTrash) }
}

extension RecoveryFinding {
    /// How results and History name it. A put back's original location is where it was going, not where it came from; an
    /// emptying's is its place in the Trash (#359).
    public func title(putBack: Bool, emptying: Bool = false) -> String {
        switch self {
        case .notStarted: "Not started"
        case .atOriginalLocation: putBack ? "Put back" : "Not removed"
        case .inTrash: putBack ? "Not put back" : emptying ? "Not removed" : "Moved to Trash"
        case .gone: "Removed"
        case .unknown: "Unknown"
        }
    }
}

extension CleanupRecord {
    /// The reviewed record for `item` (#309): the original's facts with what the check found, under a new id, so the
    /// original record stays as it was.
    init(reviewing item: CleanupRecoveryItem, at date: Date) {
        self = item.record
        id = item.record.id + "|reviewed"
        reviewOf = item.record.id; recoveryFinding = item.finding
        outcomeRecordedAt = date
        message = "Checked after an interrupted cleanup. " + item.detail
        let putBack = item.record.isPutBack
        switch item.finding {
        case .notStarted: state = .cancelled
        case .atOriginalLocation: state = putBack ? .succeeded : .skipped
        case .inTrash:
            // An emptying found its item still in the Trash: it wasn't deleted.
            state = putBack || item.record.isEmptyFromTrash ? .skipped : .succeeded
            if !item.record.isEmptyFromTrash { trashURL = item.foundURL }
        case .gone: state = putBack ? .skipped : .succeeded
            if !putBack { trashURL = nil }
        case .unknown: state = .unknown
        }
    }
}

/// Checks an interrupted cleanup against disk (#309): for each unresolved record, it looks where the item was and in the
/// Trash. Read-only: it never moves, deletes or opens anything for writing.
public struct CleanupRecoveryReview: Sendable {
    /// The Trash folder an item at a URL would go to; nil when there is none or it can't be known.
    private let trashFolder: @Sendable (URL) -> URL?
    public init(trashFolder: @escaping @Sendable (URL) -> URL? = CleanupRecoveryReview.finderTrashFolder) { self.trashFolder = trashFolder }

    /// The user's Trash for the item's volume, as Finder would use it.
    public static let finderTrashFolder: @Sendable (URL) -> URL? = { url in
        try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
    }

    /// Records what `items` found as reviewed records, in one transaction (#309). Nothing on disk changes, and no original
    /// record is rewritten. Throws, recording nothing, when an item was already reviewed or the journal can't record it.
    public func markReviewed(_ items: [CleanupRecoveryItem], in journal: any CleanupJournaling, at date: Date = Date()) throws {
        try journal.append(items.map { CleanupRecord(reviewing: $0, at: date) })
    }

    /// What each record of `batch` that has no recorded outcome (pending, intent, unknown) is found to be, in journal order.
    public func check(_ batch: CleanupRecoveryBatch) -> [CleanupRecoveryItem] {
        batch.records.filter { [.pending, .intent, .unknown].contains($0.state) }.map(check)
    }

    private func check(_ record: CleanupRecord) -> CleanupRecoveryItem {
        func item(_ finding: RecoveryFinding, _ detail: String, at url: URL? = nil) -> CleanupRecoveryItem {
            CleanupRecoveryItem(record: record, finding: finding, foundURL: url, detail: detail)
        }
        if record.state == .pending { return item(.notStarted, "It never started. Nothing was changed.") }
        let original = record.originalURL
        var info = stat()
        if lstat(original.path, &info) == 0 {
            guard info.resourceID == record.resourceID else { return item(.unknown, "Something else is at its original location now.") }
            switch record.cleanupAction {
            case .evict: return item(.unknown, "It is at its original location; its local copy may or may not have been removed. The original stays in iCloud.")
            case .tool: return item(.unknown, "It is at its original location; its tool may have cleaned part of it.")
            default:
                let detail = record.isPutBack ? "It is back at its original location." : record.isEmptyFromTrash ? "It is still in the Trash, unchanged." : "It is at its original location, unchanged."
                return item(.atOriginalLocation, detail)
            }
        }
        guard errno == ENOENT else { return item(.unknown, "Its original location couldn’t be checked.") }
        if let aside = renamedAside(record) { return item(.unknown, "It was found under a temporary name at \(aside.path).", at: aside) }
        switch inTrash(record) {
        case .found(let url): return item(.inTrash, "It is in the Trash.", at: url)
        case .unreadable: return item(.unknown, "It isn’t at its original location, and the Trash couldn’t be checked.")
        case .absent: return item(.gone, "It is neither at its original location nor in the Trash.")
        }
    }

    /// A delete, and an emptying of the Trash (#359), renames its item aside before removing it (`Catalog.leftoverName`);
    /// the same item may still be there.
    private func renamedAside(_ record: CleanupRecord) -> URL? {
        let ruleID = record.isEmptyFromTrash ? record.ruleID ?? CleanupRecord.emptyAsideRuleID : record.ruleID
        guard [.delete, .tool].contains(record.cleanupAction) || record.isEmptyFromTrash, let ruleID else { return nil }
        let folder = record.originalURL.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { Catalog.isLeftover($0, of: ruleID) }.map { folder.appendingPathComponent($0) }.first { matches($0, record) }
    }

    private enum TrashLookup { case found(URL), absent, unreadable }
    /// The recorded Trash location first, then the item's own name in its Trash, then (when the Trash can be listed) any
    /// item there with its identity, since Finder renames an item whose name is taken.
    private func inTrash(_ record: CleanupRecord) -> TrashLookup {
        if let recorded = record.trashURL, matches(recorded, record) { return .found(recorded) }
        guard let folder = trashFolder(record.originalURL) else { return .unreadable }
        var info = stat()
        guard lstat(folder.path, &info) == 0 else { return errno == ENOENT ? .absent : .unreadable }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .unreadable }
        let named = folder.appendingPathComponent(record.originalURL.lastPathComponent)
        if matches(named, record) { return .found(named) }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return .unreadable }
        return names.map { folder.appendingPathComponent($0) }.first { matches($0, record) }.map(TrashLookup.found) ?? .absent
    }

    private func matches(_ url: URL, _ record: CleanupRecord) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT != S_IFLNK && info.resourceID == record.resourceID
    }
}
