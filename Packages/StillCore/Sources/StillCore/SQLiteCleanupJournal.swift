import Foundation
import SQLite3
import Darwin

public enum CleanupJournalError: Error { case unavailable }
/// One locked connection; durable JSON records are an implementation detail behind records().
public final class SQLiteCleanupJournal: CleanupJournaling, @unchecked Sendable {
    private let lock = NSLock()
    private var database: OpaquePointer?
    public init(url: URL) throws {
        guard url.isFileURL, url.path != ":memory:" else { throw CleanupJournalError.unavailable }
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFREG { throw CleanupJournalError.unavailable }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw CleanupJournalError.unavailable }
        do {
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
    public func outcome(_ record: CleanupRecord) throws { try write(record, replace: true) }
    private func write(_ record: CleanupRecord, replace: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(record)
        try run(replace ? "UPDATE records SET payload=? WHERE id=?" : "INSERT INTO records(payload,id) VALUES(?,?)", values: [data, Data(record.id.utf8)])
        guard sqlite3_changes(database) == 1 else { throw CleanupJournalError.unavailable }
    }
    public func records() throws -> [CleanupRecord] {
        lock.lock(); defer { lock.unlock() }
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
