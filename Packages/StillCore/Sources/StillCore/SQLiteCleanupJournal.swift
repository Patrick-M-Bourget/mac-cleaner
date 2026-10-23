import Foundation
import SQLite3
import Darwin

public enum CleanupJournalError: Error { case unavailable, recoveryRequired, operationInProgress }
/// One locked connection; durable JSON records are an implementation detail behind records().
public final class SQLiteCleanupJournal: CleanupJournaling, @unchecked Sendable {
    private let lock = NSLock()
    private var database: OpaquePointer?
    private let isReadOnly: Bool
    private let location: URL
    public init(url: URL, readOnly: Bool = false) throws {
        isReadOnly = readOnly
        location = url
        guard url.isFileURL, url.path != ":memory:" else { throw CleanupJournalError.unavailable }
        let url = try DownloadsRoot(url: url.deletingLastPathComponent()).url.appendingPathComponent(url.lastPathComponent)
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFREG { throw CleanupJournalError.unavailable }
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database); database = nil; throw CleanupJournalError.unavailable
        }
        do {
            if readOnly {
                guard try scalar("PRAGMA user_version") == "1" else { throw CleanupJournalError.unavailable }
                return
            }
            guard chmod(url.path, 0o600) == 0 else { throw CleanupJournalError.unavailable }
            try run("PRAGMA journal_mode=WAL")
            try run("PRAGMA synchronous=FULL")
            try run("PRAGMA fullfsync=ON")
            guard try scalar("PRAGMA journal_mode") == "wal", try scalar("PRAGMA synchronous") == "2", try scalar("PRAGMA fullfsync") == "1" else { throw CleanupJournalError.unavailable }
            let version = try scalar("PRAGMA user_version")
            guard version == "0" || version == "1" else { throw CleanupJournalError.unavailable }
            try run("CREATE TABLE IF NOT EXISTS batches(id TEXT PRIMARY KEY NOT NULL)")
            try run("CREATE TABLE IF NOT EXISTS records(id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL)")
            try run("PRAGMA user_version=1")
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { sqlite3_close(database) }
    public func claim(_ batch: CleanupApproval) throws -> Bool {
        guard !isReadOnly else { throw CleanupJournalError.unavailable }
        lock.lock(); defer { lock.unlock() }
        try run("BEGIN IMMEDIATE")
        do {
            try run("INSERT OR IGNORE INTO batches VALUES(?)", values: [Data(batch.id.uuidString.utf8)])
            let claimed = sqlite3_changes(database) == 1
            if claimed {
                for target in batch.targets {
                    let record = CleanupRecord(batch: batch, target: target)
                    try run("INSERT INTO records(payload,id) VALUES(?,?)", values: [try JSONEncoder().encode(record), Data(record.id.utf8)])
                }
            }
            try run("COMMIT")
            return claimed
        } catch { try? run("ROLLBACK"); throw error }
    }
    public func intent(_ record: CleanupRecord) throws { try write(record, replace: true) }
    public func outcome(_ record: CleanupRecord) throws {
        var recorded = record
        if recorded.outcomeRecordedAt == nil { recorded.outcomeRecordedAt = Date() }
        try write(recorded, replace: true)
    }
    private func write(_ record: CleanupRecord, replace: Bool) throws {
        guard !isReadOnly else { throw CleanupJournalError.unavailable }
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(record)
        try run(replace ? "UPDATE records SET payload=? WHERE id=?" : "INSERT INTO records(payload,id) VALUES(?,?)", values: [data, Data(record.id.utf8)])
        guard sqlite3_changes(database) == 1 else { throw CleanupJournalError.unavailable }
    }
    public func records() throws -> [CleanupRecord] {
        lock.lock(); defer { lock.unlock() }
        return try readRecords()
    }
    private func readRecords() throws -> [CleanupRecord] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM records ORDER BY rowid", -1, &statement, nil) == SQLITE_OK else { throw CleanupJournalError.unavailable }
        defer { sqlite3_finalize(statement) }
        var results: [CleanupRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return results }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw CleanupJournalError.unavailable }
            results.append(try JSONDecoder().decode(CleanupRecord.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))))
        }
    }
    public func recordCapacity(_ observation: CleanupCapacityObservation, batchID: UUID) throws {
        guard !isReadOnly else { throw CleanupJournalError.unavailable }
        lock.lock(); defer { lock.unlock() }
        try run("BEGIN IMMEDIATE")
        do {
            for var record in try readRecords() where record.batchID == batchID {
                record.capacityObservation = observation
                try run("UPDATE records SET payload=? WHERE id=?", values: [try JSONEncoder().encode(record), Data(record.id.utf8)])
            }
            try run("COMMIT")
        } catch { try? run("ROLLBACK"); throw error }
    }
    public func completedHistory() throws -> CleanupHistorySnapshot {
        CleanupHistorySnapshot(records: try records())
    }
    /// Reads under the same write transaction as deletion. Interrupted batches are never split.
    public func clearCompletedRuns(requireNoRecovery: Bool = false, operationInProgress: Bool = false) throws -> CleanupHistoryMaintenance {
        guard !operationInProgress else { throw CleanupJournalError.operationInProgress }
        return try maintain(requireNoRecovery: requireNoRecovery) { _ in true }
    }
    public func retainCompletedRuns(now: Date = Date(), days: Int = 90, maximumBytes: Int = 250_000_000) throws -> CleanupHistoryMaintenance {
        var retainedBytes = 0
        let cutoff = now.addingTimeInterval(-Double(max(0, days)) * 86400)
        return try maintain(requireNoRecovery: false) { run in
            let bytes = run.records.reduce(0) { $0 + ((try? JSONEncoder().encode($1).count) ?? 0) }
            if run.date < cutoff || retainedBytes + bytes > max(0, maximumBytes) { return true }
            retainedBytes += bytes
            return false
        }
    }
    private func maintain(requireNoRecovery: Bool, remove: (CleanupHistoryRun) -> Bool) throws -> CleanupHistoryMaintenance {
        guard !isReadOnly else { throw CleanupJournalError.unavailable }
        lock.lock(); defer { lock.unlock() }
        try run("BEGIN IMMEDIATE")
        do {
            let snapshot = CleanupHistorySnapshot(records: try readRecords())
            if requireNoRecovery && snapshot.protectedRecordCount > 0 { throw CleanupJournalError.recoveryRequired }
            let removed = snapshot.completedRuns.filter(remove)
            for batch in removed { for record in batch.records {
                try run("DELETE FROM records WHERE id=?", values: [Data(record.id.utf8)])
            } }
            // batches intentionally survives: a cleared approval must never execute again.
            try run("COMMIT")
            return CleanupHistoryMaintenance(removedRuns: removed.count, removedRecords: removed.reduce(0) { $0 + $1.records.count }, protectedRecords: snapshot.protectedRecordCount)
        } catch { try? run("ROLLBACK"); throw error }
    }
    public func storageBytes() throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return try measuredStorageBytes()
    }
    private func measuredStorageBytes() throws -> Int64 {
        try [location, URL(fileURLWithPath: location.path + "-wal")].reduce(0) { total, url in
            var info = stat()
            if lstat(url.path, &info) != 0 {
                if errno == ENOENT { return total }
                throw CleanupJournalError.unavailable
            }
            guard info.st_mode & S_IFMT == S_IFREG else { throw CleanupJournalError.unavailable }
            return total + Int64(info.st_size)
        }
    }
    /// Explicit, bounded SQLite maintenance; never rewrites records through application code.
    public func compact(timeout: TimeInterval = 2) throws -> CleanupHistoryCompaction {
        guard !isReadOnly else { throw CleanupJournalError.unavailable }
        lock.lock(); defer { lock.unlock() }
        let before = try measuredStorageBytes()
        let available = try location.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        guard timeout > 0, before <= 250_000_000, Int64(available) > before * 2 + 64_000_000 else {
            return CleanupHistoryCompaction(beforeBytes: before, afterBytes: before, completed: false)
        }
        let deadline = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        deadline.initialize(to: ProcessInfo.processInfo.systemUptime + max(0, min(timeout, 5)))
        defer { sqlite3_progress_handler(database, 0, nil, nil); deadline.deinitialize(count: 1); deadline.deallocate() }
        sqlite3_progress_handler(database, 1000, { context in
            guard let context else { return 1 }
            return ProcessInfo.processInfo.systemUptime >= context.assumingMemoryBound(to: Double.self).pointee ? 1 : 0
        }, deadline)
        sqlite3_busy_timeout(database, 100)
        do {
            guard try scalar("PRAGMA wal_checkpoint(TRUNCATE)") == "0" else { throw CleanupJournalError.unavailable }
            try run("VACUUM")
            guard try scalar("PRAGMA wal_checkpoint(TRUNCATE)") == "0" else { throw CleanupJournalError.unavailable }
            return CleanupHistoryCompaction(beforeBytes: before, afterBytes: try measuredStorageBytes(), completed: true)
        } catch {
            return CleanupHistoryCompaction(beforeBytes: before, afterBytes: (try? measuredStorageBytes()) ?? before, completed: false)
        }
    }
    private func run(_ sql: String, values: [Data] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw CleanupJournalError.unavailable }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let result = value.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(index + 1), $0.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw CleanupJournalError.unavailable }
        }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw CleanupJournalError.unavailable }
    }
    private func scalar(_ sql: String) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw CleanupJournalError.unavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw CleanupJournalError.unavailable }
        return String(cString: text)
    }
}
