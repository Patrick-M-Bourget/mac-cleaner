import Foundation
import Darwin
import os

/// Why an item isn't deleted from the Trash. Each refusal leaves it, and everything else in the Trash, as it was.
public enum EmptyRefusal: Equatable, Sendable {
    /// Not an item a real run moved to the Trash: a dry run, another action, or a Trash location outside a Trash.
    case notEmptyable
    case alreadyPutBack
    case alreadyEmptied
    case notInTrash
    case changed
    case failed

    public var reason: String {
        switch self {
        case .notEmptyable: "Only items CacheDrop moved to the Trash can be deleted from it."
        case .alreadyPutBack: "It was put back. Nothing was changed."
        case .alreadyEmptied: "It was already deleted from the Trash."
        case .notInTrash: "It’s no longer in the Trash. Nothing was changed."
        case .changed: "It changed in the Trash since CacheDrop moved it. Nothing was changed."
        case .failed: "Couldn’t delete it. Nothing was changed."
        }
    }
}

extension CleanupRecord {
    /// The action string of a record of deleting an item from the Trash (#359). Not a `CleanupAction`: nothing in a plan
    /// empties the Trash.
    static let emptyFromTrashAction = "emptyFromTrash"
    /// The rule an item is renamed aside under when its Trash move has none.
    static let emptyAsideRuleID = "trash"
    /// A record of deleting an item CacheDrop moved to the Trash from the Trash (#359).
    public var isEmptyFromTrash: Bool { action == Self.emptyFromTrashAction }

    /// A pending deletion of `original` from its `trashURL`: that location is the record's own, so a review of an
    /// interrupted emptying checks the Trash (#309).
    init(emptying original: CleanupRecord, trashURL: URL, batchID: UUID, at date: Date, previewOnly: Bool) {
        self.init(id: batchID.uuidString + "|emptyFromTrash|" + original.id, batchID: batchID, originalURL: trashURL, resourceID: original.resourceID,
                  logicalBytes: original.logicalBytes, allocatedBytes: original.allocatedBytes, state: .pending, trashURL: nil,
                  message: "Approved; not started", observedAt: date, scopeURL: trashURL.deletingLastPathComponent(), scopeResourceID: "",
                  volumeID: original.volumeID, downloadsURL: nil, downloadsResourceID: nil, modifiedSeconds: original.modifiedSeconds,
                  modifiedNanoseconds: original.modifiedNanoseconds, action: Self.emptyFromTrashAction, policyVersion: 2,
                  outcomeRecordedAt: nil, approvedAt: date, ruleID: original.ruleID, previewOnly: previewOnly, itemName: original.itemName)
        emptyOf = original.id
    }
}

/// What the journal says about CacheDrop's Trash moves: which were put back and which deleted from the Trash, each
/// after any review of an interrupted run (#309).
struct TrashLedger {
    /// Every Trash move a real run made, by the id History shows it under, the latest per item.
    let moves: [CleanupRecord]
    let putBackIDs: Set<String>
    /// Deleted from the Trash, or possibly: an emptying that succeeded or has no recorded outcome yet.
    let emptiedIDs: Set<String>
    init(_ records: [CleanupRecord]) {
        let reviews = Dictionary(records.filter { $0.reviewOf != nil }.map { ($0.reviewOf ?? "", $0) }, uniquingKeysWith: { first, _ in first })
        func settled(_ record: CleanupRecord) -> Bool {
            [.skipped, .failed, .cancelled].contains(reviews[record.id]?.state ?? record.state)
        }
        putBackIDs = Set(records.filter { $0.isPutBack && $0.reviewOf == nil && !settled($0) }.compactMap(\.putBackOf))
        emptiedIDs = Set(records.filter { $0.isEmptyFromTrash && $0.reviewOf == nil && $0.previewOnly != true && !settled($0) }.compactMap(\.emptyOf))
        var latest: [String: CleanupRecord] = [:], order: [String] = []
        for var record in records where record.canPutBack {
            if let reviewed = record.reviewOf { record.id = reviewed }
            if latest[record.resourceID] == nil { order.append(record.resourceID) }
            latest[record.resourceID] = record
        }
        moves = order.compactMap { latest[$0] }
    }

    /// Why `original` can't be deleted from the Trash now; nil when it can. Reads the Trash by search only.
    func refusal(_ original: CleanupRecord) -> EmptyRefusal? {
        guard original.canPutBack, let trashURL = original.trashURL else { return .notEmptyable }
        if emptiedIDs.contains(original.id) { return .alreadyEmptied }
        if putBackIDs.contains(original.id) { return .alreadyPutBack }
        var info = stat()
        guard lstat(trashURL.path, &info) == 0 else { return errno == ENOENT ? .notInTrash : .failed }
        return TrashPutBack.changed(info, original) == nil ? nil : .changed
    }
}

/// CacheDrop's own items still in the Trash: what Results and Overview offer to empty, and the sheet lists (#359).
public struct TrashEmptyingReview: Sendable {
    public let items: [CleanupRecord]
    public init(items: [CleanupRecord]) { self.items = items }
    /// Their recorded sizes, from the journal: the whole Trash's size is never offered.
    public var bytes: Int64 { items.reduce(0) { $0 + $1.recordedBytes } }
}

/// What one emptying did, item by item.
public struct TrashEmptyingResult: Sendable {
    public let records: [CleanupRecord]
    public let previewOnly: Bool
    /// Set when the journal couldn't record the emptying, or what happened.
    public let journalFailure: String?
    public init(records: [CleanupRecord], previewOnly: Bool, journalFailure: String? = nil) {
        self.records = records; self.previewOnly = previewOnly; self.journalFailure = journalFailure
    }
    public var deletedCount: Int { records.filter { $0.state == .succeeded }.count }
    /// The available-space change read around each deleted item, as a cleanup measures it; nil when any reading is missing.
    public var measuredFreedBytes: Int64? {
        guard !previewOnly else { return nil }
        return records.measuredFreedBytes
    }
}

extension Array where Element == CleanupRecord {
    /// True when the run moved something to the Trash and removed nothing else: nothing is freed until the Trash is emptied,
    /// so Results and History show no measured freed space (Decision 66).
    public var movedOnlyToTrash: Bool {
        let succeeded = filter { $0.state == .succeeded }
        return succeeded.contains { $0.cleanupAction == .trash } && succeeded.allSatisfy { $0.cleanupAction == .trash }
    }
    /// The sum of the available-space change read around each removed item; nil when any reading is missing. A Trash move
    /// frees nothing yet, and an item that finished after the stop (#209) freed its space where nothing measured it. Results,
    /// History and Empty from Trash all read it (#433).
    var measuredFreedBytes: Int64? {
        var total: Int64 = 0
        for record in self where record.state == .succeeded && record.cleanupAction != .trash && !record.finishedAfterStop {
            guard let change = record.itemCapacity?.observedChange else { return nil }
            total += change
        }
        return total
    }
}

/// Deletes from the Trash only items CacheDrop moved there itself, and only when you ask (Decision 68, SPEC section 2).
/// It never empties the Trash: each item is the one recorded `trashURL`, found by search (no Full Disk Access needed),
/// with the identity and dates it had when it was moved, and checked again just before it goes. Journaled like a cleanup
/// (pending, intent, outcome), as its own History run.
public struct TrashEmptying: Sendable {
    private static let log = Logger(subsystem: "CacheDrop", category: "emptyFromTrash")
    private let journal: any CleanupJournaling
    private let measure: @Sendable (URL) -> CapacitySample?
    private let clock: @Sendable () -> Date
    public init(journal: any CleanupJournaling, measure: @escaping @Sendable (URL) -> CapacitySample? = CapacitySample.read,
                clock: @escaping @Sendable () -> Date = Date.init) {
        self.journal = journal; self.measure = measure; self.clock = clock
    }

    /// Every item a real run moved to the Trash, from any run, that is still there, unchanged and not put back. Read-only.
    public func review() throws -> TrashEmptyingReview {
        let ledger = TrashLedger(try journal.records())
        return TrashEmptyingReview(items: ledger.moves.filter { ledger.refusal($0) == nil })
    }

    /// Deletes `items` from the Trash, each checked again first; one that fails a check is skipped and left alone, with its
    /// reason. With `previewOnly` (the Settings dry run) each is checked and nothing changes. Items that were never Trash
    /// moves are left out, and with none left nothing is recorded.
    public func empty(_ items: [CleanupRecord], previewOnly: Bool) -> TrashEmptyingResult {
        func result(_ records: [CleanupRecord], _ failure: String? = nil) -> TrashEmptyingResult {
            TrashEmptyingResult(records: records, previewOnly: previewOnly, journalFailure: failure)
        }
        guard let records = try? journal.records() else { return result([], "CacheDrop couldn’t read its history, so nothing was changed.") }
        let ledger = TrashLedger(records)
        let originals = items.filter { ledger.refusal($0) != .notEmptyable }
        guard !originals.isEmpty else { return result([]) }
        let date = clock(), batchID = UUID()
        let pending = originals.map { CleanupRecord(emptying: $0, trashURL: $0.trashURL!, batchID: batchID, at: date, previewOnly: previewOnly) }
        do { guard try journal.claim(batchID: batchID, records: pending) else { return result([]) } }
        catch { return result([], "CacheDrop couldn’t save the emptying before starting, so nothing was changed.") }

        var done: [CleanupRecord] = [], failure: String?
        for (original, initial) in zip(originals, pending) {
            var record = initial
            if failure != nil {
                record.state = .cancelled; record.message = "Not started"; done.append(record); continue
            }
            record.state = .intent; record.message = "Started; outcome not yet recorded"
            do { try journal.intent(record) }
            catch { record.state = .cancelled; record.message = "CacheDrop couldn’t save its progress, so it stopped. This item wasn’t changed."; failure = record.message; done.append(record); continue }
            perform(original, previewOnly: previewOnly, ledger: ledger, into: &record)
            do { try journal.outcome(record) }
            catch { record.state = .unknown; record.message = "CacheDrop couldn’t save what happened. Review the interrupted cleanup before cleaning again."; failure = record.message }
            Self.log.info("\(record.state.rawValue, privacy: .public) delete from the Trash \(record.originalURL.path, privacy: .public)")
            done.append(record)
        }
        return result(done, failure)
    }

    private func perform(_ original: CleanupRecord, previewOnly: Bool, ledger: TrashLedger, into record: inout CleanupRecord) {
        if let refusal = ledger.refusal(original) { record.state = .skipped; record.message = refusal.reason; return }
        if previewOnly {
            let size = ByteCountFormatter.string(fromByteCount: original.recordedBytes, countStyle: .decimal)
            record.state = .skipped; record.message = CleanupRecord.previewPrefix + " would delete from the Trash (\(size)). Checks passed; nothing changed."
            return
        }
        let folder = record.originalURL.deletingLastPathComponent()
        let before = measure(folder)
        Self.delete(original, at: record.originalURL, into: &record)
        if record.state == .succeeded, let before, let after = measure(folder) {
            record.itemCapacity = CleanupCapacityObservation(from: before, to: after)
        }
    }

    /// Renames the item aside inside its Trash folder, confirms it is the one CacheDrop moved there, then removes it. The
    /// folder is opened for search only: without Full Disk Access the Trash can be searched but not listed.
    private static func delete(_ original: CleanupRecord, at trashURL: URL, into record: inout CleanupRecord) {
        func skip(_ refusal: EmptyRefusal) { record.state = refusal == .failed ? .failed : .skipped; record.message = refusal.reason }
        let folderURL = trashURL.deletingLastPathComponent()
        let folder = open(folderURL.path, O_SEARCH | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { return skip(errno == ENOENT ? .notInTrash : .failed) }
        defer { close(folder) }
        let name = trashURL.lastPathComponent
        var info = stat()
        guard fstatat(folder, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return skip(errno == ENOENT ? .notInTrash : .failed) }
        if TrashPutBack.changed(info, original) != nil { return skip(.changed) }
        let aside = Catalog.leftoverName(for: original.ruleID ?? CleanupRecord.emptyAsideRuleID)
        guard renameatx_np(folder, name, folder, aside, UInt32(RENAME_EXCL)) == 0 else { return skip(errno == ENOENT ? .notInTrash : .failed) }
        func putAsideBack() -> Bool { renameatx_np(folder, aside, folder, name, UInt32(RENAME_EXCL)) == 0 }
        guard fstatat(folder, aside, &info, AT_SYMLINK_NOFOLLOW) == 0, info.resourceID == original.resourceID else {
            if putAsideBack() { return skip(.changed) }
            record.state = .unknown; record.message = "Changed while starting; left in the Trash as \(aside). Review it before cleaning again."
            return
        }
        let isFolder = info.st_mode & S_IFMT == S_IFDIR
        let removed = isFolder ? (try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(aside))) != nil : unlinkat(folder, aside, 0) == 0
        if removed { record.state = .succeeded; record.message = "Deleted from the Trash"; return }
        let back = putAsideBack()
        guard isFolder else {
            if back { return skip(.failed) }
            record.state = .unknown; record.message = "Couldn’t delete it; left in the Trash as \(aside). Review it before cleaning again."
            return
        }
        // Never "not changed": part of the folder may be gone.
        record.state = .failed; record.partlyRemoved = true
        record.message = back ? "Partly deleted. The rest is still in the Trash." : "Partly deleted. The rest is in the Trash as \(aside)."
    }
}
