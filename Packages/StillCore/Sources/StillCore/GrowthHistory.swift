import Foundation
import Darwin

public struct GrowthFingerprint: Codable, Sendable, Equatable {
    public let scopeID, rootID, volumeID, access, rules, exclusions, classification: String
    public init(scopeID: String, rootID: String, volumeID: String, access: String, rules: String, exclusions: String, classification: String) {
        self.scopeID = scopeID; self.rootID = rootID; self.volumeID = volumeID; self.access = access
        self.rules = rules; self.exclusions = exclusions; self.classification = classification
    }
}
public enum GrowthDimension: String, Codable, Sendable { case folder, category }
public struct GrowthAggregate: Codable, Sendable, Identifiable {
    public let id, label: String
    public let logicalBytes: Int64
    public let dimension: GrowthDimension
    public init(id: String, label: String, logicalBytes: Int64, dimension: GrowthDimension = .folder) { self.id = id; self.label = label; self.logicalBytes = logicalBytes; self.dimension = dimension }
}
public enum GrowthCoverage: String, Codable, Sendable { case complete, partial, cancelled, unmeasured }
public struct GrowthSnapshot: Codable, Sendable, Identifiable {
    public let id: UUID
    public let fingerprint: GrowthFingerprint
    public let scopeLabel: String
    public let observedAt: Date
    public let groups: [GrowthAggregate]
    public let coverage: GrowthCoverage
    public init(fingerprint: GrowthFingerprint, scopeLabel: String, observedAt: Date, groups: [GrowthAggregate], coverage: GrowthCoverage = .complete) {
        id = UUID(); self.fingerprint = fingerprint; self.scopeLabel = scopeLabel
        self.observedAt = observedAt; self.groups = groups; self.coverage = coverage
    }
    public var logicalBytes: Int64 { groups.filter { $0.dimension == .folder }.reduce(0) { $0 + $1.logicalBytes } }
}
public enum GrowthComparisonState: String, Codable, Sendable { case firstBaseline, clearedBaseline, missingBaseline, coverageChanged, unknown, compared }
public struct GrowthChange: Sendable, Identifiable {
    public let id, label: String
    public let logicalDelta: Int64
    public let dimension: GrowthDimension
}
public struct GrowthComparison: Sendable {
    public let state: GrowthComparisonState
    public static var unknown: GrowthComparison { GrowthComparison(state: .unknown, current: nil, from: nil, groups: []) }
    public let current: GrowthSnapshot?
    public let from: Date?
    public var to: Date? { current?.observedAt }
    public let groups: [GrowthChange]
    public var logicalDelta: Int64? { state == .compared ? groups.filter { $0.dimension == .folder }.reduce(0) { $0 + $1.logicalDelta } : nil }
}
public struct GrowthRetention: Sendable {
    public let days, baselines, bytes: Int
    public init(days: Int = 90, baselines: Int = 30, bytes: Int = 250_000_000) {
        self.days = min(90, max(1, days)); self.baselines = min(30, max(1, baselines)); self.bytes = min(250_000_000, max(256, bytes))
    }
}
/// Owns aggregate and opaque epoch/lock files. It never opens, enumerates or evicts operation journals.
public actor GrowthHistoryStore {
    private struct Entry: Codable { let snapshot: GrowthSnapshot; let origin: GrowthComparisonState }
    private struct Archive: Codable { var version = 1; var entries: [Entry] = []; var hadHistory = false; var cleared = false }
    private let directory: URL
    private let policy: GrowthRetention
    public init(directory: URL, policy: GrowthRetention = GrowthRetention()) { self.directory = directory; self.policy = policy }
    public func snapshots(now: Date = Date()) throws -> [GrowthSnapshot] { try withStoreLock { try retained(now).entries.map(\.snapshot) } }
    public func latest(now: Date = Date()) throws -> GrowthComparison { try withStoreLock { let value = try retained(now); return comparison(in: value, id: value.entries.last?.snapshot.id) } }
    public func comparison(id: UUID, now: Date = Date()) throws -> GrowthComparison { try withStoreLock { comparison(in: try retained(now), id: id) } }
    /// Capture before observation; retain across awaits. Never refresh an old capture at commit.
    public func recordingEpoch() throws -> UUID { try withStoreLock { try currentEpoch() } }
    public func record(_ snapshot: GrowthSnapshot, now: Date = Date(), expectedEpoch: UUID) throws -> GrowthComparison {
        try withStoreLock {
            try Task.checkCancellation()
            if try currentEpoch() != expectedEpoch { return .unknown }
            var value = try load()
            guard snapshot.coverage == .complete, !snapshot.groups.isEmpty, snapshot.groups.count <= 512,
                  Set(snapshot.groups.map(\.id)).count == snapshot.groups.count,
                  snapshot.groups.allSatisfy({ $0.logicalBytes >= 0 && $0.logicalBytes <= Int64.max / 512 && $0.id.utf8.count <= 512 && $0.label.utf8.count <= 512 }),
                  snapshot.observedAt <= now, value.entries.last.map({ $0.snapshot.observedAt < snapshot.observedAt }) ?? true else {
                return GrowthComparison(state: .unknown, current: snapshot, from: nil, groups: [])
            }
            value.entries.removeAll { now.timeIntervalSince($0.snapshot.observedAt) > Double(policy.days) * 86400 }
            let origin: GrowthComparisonState = value.cleared ? .clearedBaseline : value.hadHistory ? .missingBaseline : .firstBaseline
            value.entries.append(Entry(snapshot: snapshot, origin: origin)); value.hadHistory = true; value.cleared = false
            if value.entries.count > policy.baselines { value.entries.removeFirst(value.entries.count - policy.baselines) }
            while try JSONEncoder().encode(value).count > policy.bytes && !value.entries.isEmpty { value.entries.removeFirst() }
            try save(value)
            return value.entries.contains(where: { $0.snapshot.id == snapshot.id }) ? comparison(in: value, id: snapshot.id) : GrowthComparison(state: .unknown, current: snapshot, from: nil, groups: [])
        }
    }
    /// Reject observations started under previous settings while retaining compatible historical aggregates.
    public func invalidateCoverage() throws { try withStoreLock { try writeEpoch(UUID()) } }
    public func clearCompletedHistory() throws {
        try withStoreLock {
            try writeEpoch(UUID())
            var value = try load(); value.entries = []; value.cleared = true
            try save(value)
        }
    }
    public func resetHistory() throws {
        try withStoreLock {
            try writeEpoch(UUID())
            try verifyDirectory(create: false)
            let file = directory.appendingPathComponent("aggregates-v1.json")
            var info = stat()
            if lstat(file.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: file)
            } else if errno != ENOENT { throw CocoaError(.fileWriteNoPermission) }
        }
    }
    private func comparison(in value: Archive, id: UUID?) -> GrowthComparison {
        guard let index = value.entries.firstIndex(where: { $0.snapshot.id == id }) else {
            return GrowthComparison(state: value.cleared ? .clearedBaseline : value.hadHistory ? .missingBaseline : .firstBaseline, current: nil, from: nil, groups: [])
        }
        let current = value.entries[index].snapshot
        guard index > 0 else { return GrowthComparison(state: value.entries[index].origin, current: current, from: nil, groups: []) }
        let previous = value.entries[..<index].last(where: { $0.snapshot.fingerprint.scopeID == current.fingerprint.scopeID })?.snapshot ?? value.entries[index - 1].snapshot
        guard current.fingerprint == previous.fingerprint else { return GrowthComparison(state: .coverageChanged, current: current, from: previous.observedAt, groups: []) }
        let older = Dictionary(uniqueKeysWithValues: previous.groups.map { ($0.id, $0) })
        let newer = Dictionary(uniqueKeysWithValues: current.groups.map { ($0.id, $0) })
        let changes = Set(older.keys).union(newer.keys).map { key in GrowthChange(id: key, label: newer[key]?.label ?? older[key]!.label, logicalDelta: (newer[key]?.logicalBytes ?? 0) - (older[key]?.logicalBytes ?? 0), dimension: newer[key]?.dimension ?? older[key]!.dimension) }.sorted { $0.id < $1.id }
        return GrowthComparison(state: .compared, current: current, from: previous.observedAt, groups: changes)
    }
    private func retained(_ now: Date) throws -> Archive {
        var value = try load()
        let count = value.entries.count
        value.entries.removeAll { now.timeIntervalSince($0.snapshot.observedAt) > Double(policy.days) * 86400 }
        if value.entries.count != count { try save(value) }
        return value
    }
    private func load() throws -> Archive {
        try verifyDirectory(create: false)
        let file = directory.appendingPathComponent("aggregates-v1.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return Archive() }
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { throw CocoaError(.fileReadNoPermission) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= policy.bytes else { throw CocoaError(.fileReadTooLarge) }
        let decoded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
        guard decoded.version == 1, decoded.entries.count <= policy.baselines, decoded.entries.allSatisfy({ entry in
            let groups = entry.snapshot.groups
            return entry.snapshot.coverage == .complete && !groups.isEmpty && groups.count <= 512 && Set(groups.map(\.id)).count == groups.count
                && groups.allSatisfy { $0.logicalBytes >= 0 && $0.logicalBytes <= Int64.max / 512 && $0.id.utf8.count <= 512 && $0.label.utf8.count <= 512 }
        }) else { throw CocoaError(.fileReadCorruptFile) }
        return decoded
    }
    // This advisory lock serializes all cooperating instances on the same owned store.
    // No MainActor work or awaits occur while held. The OS releases it on process exit.
    private func withStoreLock<T>(_ operation: () throws -> T) throws -> T {
        try verifyDirectory(create: true)
        let file = directory.appendingPathComponent(".growth-lock")
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
    private func currentEpoch() throws -> UUID {
        let file = directory.appendingPathComponent(".growth-epoch")
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw CocoaError(.fileReadNoPermission) }
            let epoch = UUID(); try writeEpoch(epoch); return epoch
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(), info.st_size <= 128,
              let epoch = UUID(uuidString: try String(contentsOf: file, encoding: .utf8)) else { throw CocoaError(.fileReadCorruptFile) }
        return epoch
    }
    private func writeEpoch(_ epoch: UUID) throws {
        let file = directory.appendingPathComponent(".growth-epoch")
        var info = stat()
        if lstat(file.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { throw CocoaError(.fileWriteNoPermission) }
        } else if errno != ENOENT { throw CocoaError(.fileWriteNoPermission) }
        try Data(epoch.uuidString.utf8).write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw CocoaError(.fileWriteNoPermission) }
    }
    private func verifyDirectory(create: Bool) throws {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            guard errno == ENOENT else { throw CocoaError(.fileReadNoPermission) }
            if !create { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else { throw CocoaError(.fileReadNoPermission) }
    }
    private func save(_ value: Archive) throws {
        try verifyDirectory(create: true)
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent("aggregates-v1.json"), options: .atomic)
    }
}
