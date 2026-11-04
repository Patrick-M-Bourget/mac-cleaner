import Foundation
import Darwin

/// One item at the top of the Trash, as read when the Empty Trash sheet opened (#605): only these are deleted, each
/// only while it is still the same item, so anything trashed after the sheet opened stays.
public struct TrashItem: Sendable, Identifiable, Equatable {
    public let url: URL
    public let resourceID: String
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    public let volumeID: String?
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var bytes: Int64 { allocatedBytes ?? logicalBytes }
}

/// Everything in the Trash, item by item: what Empty Trash… offers and its sheet lists (#605, Decision 142).
public struct WholeTrashReview: Sendable {
    public let items: [TrashItem]
    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

extension TrashEmptying {
    /// The Trash's items with their sizes, read-only; nil when the Trash can't be read in full (Full Disk Access), so its
    /// size is never guessed, and when it is empty. Finder's own bookkeeping files are left out.
    public static func reviewWholeTrash(home: URL, sizer: KnownLocationSizer = KnownLocationSizer(timeBudget: 30)) -> WholeTrashReview? {
        let folder = TrashSpace.folder(home: home)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        var items: [TrashItem] = []
        for name in names.sorted() where name != ".DS_Store" && name != ".localized" {
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return nil }
            let size = sizer.size(url)
            guard size.complete else { return nil }
            let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            items.append(TrashItem(url: url, resourceID: info.resourceID, modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
                                   modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec), logicalBytes: size.logicalBytes,
                                   allocatedBytes: size.allocatedBytes, volumeID: volume))
        }
        return items.isEmpty ? nil : WholeTrashReview(items: items)
    }

    /// Deletes `items` from the Trash, each checked again first (the same item, unchanged, still in the Trash); one that
    /// fails is skipped and left alone, with its reason. Journaled and measured like emptying CacheDrop's own items, as
    /// one History run; CacheDrop's own items among them are recorded as emptied, so they lose Put back. With `dryRun`
    /// nothing changes.
    public func emptyWholeTrash(_ items: [TrashItem], dryRun: Bool) -> TrashEmptyingResult {
        guard let records = try? journal.records() else {
            return TrashEmptyingResult(records: [], dryRun: dryRun, journalFailure: "CacheDrop couldn’t read its history, so nothing was changed.")
        }
        guard !items.isEmpty else { return TrashEmptyingResult(records: [], dryRun: dryRun) }
        let moves = Dictionary(TrashLedger(records).moves.compactMap { move in move.trashURL.map { ($0.standardizedFileURL.path, move) } },
                               uniquingKeysWith: { first, _ in first })
        let date = clock(), batchID = UUID()
        let pending = items.map { item -> CleanupRecord in
            let own = moves[item.url.standardizedFileURL.path].flatMap { $0.resourceID == item.resourceID ? $0 : nil }
            return CleanupRecord(emptyingTrashItem: item, own: own, batchID: batchID, at: date, dryRun: dryRun)
        }
        return journaled(pending, batchID: batchID, dryRun: dryRun) { _, record in
            if dryRun {
                record.state = .skipped
                record.message = CleanupRecord.previewPrefix + " would delete from the Trash (\(SizeFormatter.text(record.recordedBytes))). Checks passed; nothing changed."
                return
            }
            // The pending record carries the item's identity and dates, so it is the item to check against.
            let item = record
            measured(&record) { record in
                var info = stat()
                if lstat(record.originalURL.path, &info) == 0, info.st_mode & S_IFMT == S_IFLNK {
                    // A link the user trashed: removed itself, never followed. The shared check refuses links (Put back).
                    guard info.resourceID == item.resourceID else { record.state = .skipped; record.message = EmptyRefusal.changed.reason; return }
                    if unlink(record.originalURL.path) == 0 { record.state = .succeeded; record.message = "Deleted from the Trash" }
                    else { record.state = .failed; record.message = EmptyRefusal.failed.reason }
                    return
                }
                Self.delete(item, at: record.originalURL, into: &record)
            }
        }
    }
}

extension CleanupRecord {
    /// A pending deletion of one Trash item (#605), shaped like deleting one of CacheDrop's own items so History and the
    /// review of an interrupted run treat both alike. `own` is CacheDrop's move of that item, when it is one.
    init(emptyingTrashItem item: TrashItem, own: CleanupRecord?, batchID: UUID, at date: Date, dryRun: Bool) {
        self.init(id: batchID.uuidString + "|emptyFromTrash|" + (own?.id ?? item.url.path), batchID: batchID, originalURL: item.url,
                  resourceID: item.resourceID, logicalBytes: item.logicalBytes, allocatedBytes: item.allocatedBytes, state: .pending,
                  trashURL: nil, message: "Not started", observedAt: date, scopeURL: item.url.deletingLastPathComponent(),
                  scopeResourceID: "", volumeID: item.volumeID, downloadsURL: nil, downloadsResourceID: nil,
                  modifiedSeconds: item.modifiedSeconds, modifiedNanoseconds: item.modifiedNanoseconds,
                  action: Self.emptyFromTrashAction, policyVersion: 2, outcomeRecordedAt: nil, approvedAt: date,
                  ruleID: own?.ruleID, dryRun: dryRun, itemName: own?.itemName ?? item.name)
        emptyOf = own?.id
    }
}
