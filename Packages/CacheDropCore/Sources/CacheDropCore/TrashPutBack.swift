import Foundation
import Darwin
import os

/// Why an item can't be put back. Each refusal changes nothing, on disk or in the Trash.
public enum PutBackRefusal: Equatable, Sendable {
    /// Not an item CacheDrop moved to the Trash: a dry run, another action, or a Trash location outside a Trash.
    case notPutBackable
    case alreadyPutBack
    case notInTrash
    case originalTaken
    case originalFolderMissing
    case changed
    case couldNotRecord
    case failed

    public var reason: String {
        switch self {
        case .notPutBackable: "Only items CacheDrop moved to the Trash can be put back."
        case .alreadyPutBack: "It was already put back."
        case .notInTrash: "It’s no longer in the Trash. Nothing was changed."
        case .originalTaken: "Something is already at its original location. Nothing was changed."
        case .originalFolderMissing: "Its original folder is gone. Nothing was changed."
        case .changed: "It changed in the Trash since CacheDrop moved it. Nothing was changed."
        case .couldNotRecord: "Couldn’t record the put back. Nothing was changed."
        case .failed: "Couldn’t put it back. Nothing was changed."
        }
    }
}

public enum PutBackOutcome: Equatable, Sendable {
    case restored(URL)
    case refused(PutBackRefusal)
}

extension CleanupRecord {
    /// The action string of a put-back record. Not a `CleanupAction`: nothing in a plan puts back.
    static let putBackAction = "putBack"
    /// A record of putting an item back from the Trash (#159).
    public var isPutBack: Bool { action == Self.putBackAction }
    /// Moved to the Trash by a real run, with where it landed recorded inside a Trash folder.
    public var canPutBack: Bool {
        guard state == .succeeded, cleanupAction == .trash, previewOnly != true, let trashURL else { return false }
        return trashURL.standardizedFileURL.pathComponents.dropLast().contains(where: Protection.trashNames.contains)
    }

    /// A pending put-back of `original`: from its `trashURL` back to its `originalURL`.
    init(putBackOf original: CleanupRecord, batchID: UUID, at date: Date) {
        self.init(id: batchID.uuidString + "|putBack|" + original.id, batchID: batchID, originalURL: original.originalURL, resourceID: original.resourceID,
                  logicalBytes: original.logicalBytes, allocatedBytes: original.allocatedBytes, state: .pending, trashURL: original.trashURL,
                  message: "Approved; not started", observedAt: date, scopeURL: original.scopeURL, scopeResourceID: original.scopeResourceID,
                  volumeID: original.volumeID, downloadsURL: nil, downloadsResourceID: nil, modifiedSeconds: original.modifiedSeconds,
                  modifiedNanoseconds: original.modifiedNanoseconds, action: Self.putBackAction, policyVersion: 2, capacityObservation: nil,
                  outcomeRecordedAt: nil, approvedAt: date, ruleID: original.ruleID, itemName: original.itemName)
        putBackOf = original.id
    }
}

/// Puts an item CacheDrop moved to the Trash back where it was (#159), the way the Trash move was made: verified before
/// and after, and journaled (pending, intent, outcome) as its own History run.
///
/// It only ever renames the one recorded item out of the Trash, with a no-overwrite rename; it never deletes anything,
/// in the Trash or at the original location (SPEC section 2).
public struct TrashPutBack: Sendable {
    private static let log = Logger(subsystem: "CacheDrop", category: "putBack")
    private let journal: any CleanupJournaling
    private let clock: @Sendable () -> Date
    public init(journal: any CleanupJournaling, clock: @escaping @Sendable () -> Date = Date.init) {
        self.journal = journal; self.clock = clock
    }

    public func putBack(_ original: CleanupRecord) -> PutBackOutcome {
        guard original.canPutBack, let trashURL = original.trashURL,
              !original.originalURL.standardizedFileURL.pathComponents.contains(where: Protection.trashNames.contains) else { return .refused(.notPutBackable) }
        guard let records = try? journal.records() else { return .refused(.couldNotRecord) }
        // A put back that succeeded, or may have, is never repeated; a refused or failed one can be tried again.
        if records.contains(where: { $0.putBackOf == original.id && $0.state != .skipped && $0.state != .failed && $0.state != .cancelled }) {
            return .refused(.alreadyPutBack)
        }
        if let refusal = Self.check(original, trashURL: trashURL) { return .refused(refusal) }

        let date = clock()
        var record = CleanupRecord(putBackOf: original, batchID: UUID(), at: date)
        do {
            guard try journal.claim(batchID: record.batchID, records: [record]) else { return .refused(.couldNotRecord) }
            record.state = .intent; record.message = "Started; outcome not yet recorded"
            try journal.intent(record)
        } catch { return .refused(.couldNotRecord) }

        let refusal = Self.move(original, from: trashURL, into: &record)
        do { try journal.outcome(record) }
        catch {
            record.state = .unknown
            Self.log.error("Put back of \(original.originalURL.path, privacy: .public) ran, but its outcome could not be recorded")
        }
        Self.log.info("\(record.state.rawValue, privacy: .public) put back \(original.originalURL.path, privacy: .public)")
        if let refusal { return .refused(refusal) }
        return record.state == .succeeded ? .restored(original.originalURL) : .refused(.failed)
    }

    /// Before acting: the item is still in the Trash and unchanged, and its original location is free inside an existing folder.
    private static func check(_ original: CleanupRecord, trashURL: URL) -> PutBackRefusal? {
        var info = stat()
        guard lstat(trashURL.path, &info) == 0 else { return errno == ENOENT ? .notInTrash : .failed }
        if let changed = changed(info, original) { return changed }
        if lstat(original.originalURL.path, &info) == 0 || errno != ENOENT { return .originalTaken }
        let folder = original.originalURL.deletingLastPathComponent()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, sameFolder(info, original) else { return .originalFolderMissing }
        return nil
    }

    /// The original folder is the one the item was moved from, when the record says which that was: a folder put in its
    /// place, or a symlink to somewhere else, is not where the item came from.
    private static func sameFolder(_ info: stat, _ original: CleanupRecord) -> Bool {
        guard original.scopeURL.standardizedFileURL == original.originalURL.deletingLastPathComponent().standardizedFileURL, !original.scopeResourceID.isEmpty else { return true }
        return info.resourceID == original.scopeResourceID
    }

    /// The Trash item is the one moved there: same identity, not a symlink, and a file not written to since.
    private static func changed(_ info: stat, _ original: CleanupRecord) -> PutBackRefusal? {
        let type = info.st_mode & S_IFMT
        guard type != S_IFLNK, info.resourceID == original.resourceID else { return .changed }
        if type == S_IFREG, Int64(info.st_mtimespec.tv_sec) != original.modifiedSeconds || Int64(info.st_mtimespec.tv_nsec) != original.modifiedNanoseconds {
            return .changed
        }
        return nil
    }

    /// Renames the item from the Trash to its original location without replacing anything there, then confirms the
    /// item at the original location is the one that was in the Trash.
    private static func move(_ original: CleanupRecord, from trashURL: URL, into record: inout CleanupRecord) -> PutBackRefusal? {
        func skip(_ refusal: PutBackRefusal) -> PutBackRefusal { record.state = .skipped; record.message = refusal.reason; return refusal }
        // Search only: without Full Disk Access the Trash can't be read (listed), only searched.
        let flags = O_SEARCH | O_NOFOLLOW | O_CLOEXEC
        let source = open(trashURL.deletingLastPathComponent().path, flags)
        guard source >= 0 else {
            if errno == ENOENT { return skip(.notInTrash) }
            record.state = .failed; record.message = PutBackRefusal.failed.reason; return .failed
        }
        defer { close(source) }
        let destination = open(original.originalURL.deletingLastPathComponent().path, flags)
        guard destination >= 0 else { return skip(.originalFolderMissing) }
        defer { close(destination) }
        var folder = stat()
        guard fstat(destination, &folder) == 0, sameFolder(folder, original) else { return skip(.originalFolderMissing) }
        let name = trashURL.lastPathComponent, target = original.originalURL.lastPathComponent
        var info = stat()
        guard fstatat(source, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return skip(.notInTrash) }
        if let changed = changed(info, original) { return skip(changed) }
        guard renameatx_np(source, name, destination, target, UInt32(RENAME_EXCL)) == 0 else {
            switch errno {
            case EEXIST: return skip(.originalTaken)
            case ENOENT: return skip(.notInTrash)
            default: record.state = .failed; record.message = PutBackRefusal.failed.reason; return .failed
            }
        }
        guard fstatat(destination, target, &info, AT_SYMLINK_NOFOLLOW) == 0, info.resourceID == original.resourceID else {
            record.state = .unknown
            record.message = "The item put back isn’t the one CacheDrop moved to the Trash. Review \(original.originalURL.path) before using it."
            return nil
        }
        record.state = .succeeded; record.message = "Put back from the Trash"
        return nil
    }
}
