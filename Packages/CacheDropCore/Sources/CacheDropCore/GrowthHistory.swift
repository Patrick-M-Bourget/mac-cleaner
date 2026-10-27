import Foundation
import Darwin

public struct GrowthFingerprint: Codable, Sendable, Equatable {
    public let scopeID, rootID, volumeID, access, rules, exclusions, classification: String
    public init(scopeID: String, rootID: String, volumeID: String, access: String, rules: String, exclusions: String, classification: String) {
        self.scopeID = scopeID; self.rootID = rootID; self.volumeID = volumeID; self.access = access
        self.rules = rules; self.exclusions = exclusions; self.classification = classification
    }
    /// Whether this records a catalog scan of the known locations rather than a chosen folder.
    public var isCatalog: Bool { scopeID.hasPrefix("catalog:") }
}
/// `location` groups come from catalog scans: one per rule location, with its catalog category and whether it could be read.
public enum GrowthDimension: String, Codable, Sendable { case folder, category, location }
public struct GrowthAggregate: Codable, Sendable, Identifiable {
    public let id, label: String
    public let logicalBytes: Int64
    public let dimension: GrowthDimension
    /// A location group's catalog category and rule.
    public let category: CatalogCategory?
    public let ruleID: String?
    /// False when the location couldn't be fully read (no Full Disk Access, unreadable folders): its size is not a measurement.
    /// Nil in records made before catalog scans, which were always measured.
    public let measured: Bool?
    public init(id: String, label: String, logicalBytes: Int64, dimension: GrowthDimension = .folder, category: CatalogCategory? = nil, ruleID: String? = nil, measured: Bool? = nil) {
        self.id = id; self.label = label; self.logicalBytes = logicalBytes; self.dimension = dimension
        self.category = category; self.ruleID = ruleID; self.measured = measured
    }
    var isMeasured: Bool { measured != false }
}
public enum GrowthCoverage: String, Codable, Sendable { case complete, partial, cancelled, unmeasured }
public struct GrowthSnapshot: Codable, Sendable, Identifiable {
    public let id: UUID
    public let fingerprint: GrowthFingerprint
    public let scopeLabel: String
    public let observedAt: Date
    public let groups: [GrowthAggregate]
    public let coverage: GrowthCoverage
    /// A rescan right after a cleanup (#126). It can be the latest scan, but never the baseline a later scan compares with.
    /// Nil in records made before this was tracked.
    private let cleanup: Bool?
    public var afterCleanup: Bool { cleanup == true }
    public init(fingerprint: GrowthFingerprint, scopeLabel: String, observedAt: Date, groups: [GrowthAggregate], coverage: GrowthCoverage = .complete, afterCleanup: Bool = false) {
        id = UUID(); self.fingerprint = fingerprint; self.scopeLabel = scopeLabel
        self.observedAt = observedAt; self.groups = groups; self.coverage = coverage; cleanup = afterCleanup
    }
    public var logicalBytes: Int64 { groups.filter { $0.dimension != .category && $0.isMeasured }.reduce(0) { $0 + $1.logicalBytes } }
}
public enum GrowthComparisonState: String, Codable, Sendable { case firstBaseline, clearedBaseline, missingBaseline, coverageChanged, unknown, compared
    /// Earlier scans exist, but none is old enough (or each is a rescan right after a cleanup): check back tomorrow.
    case waitingForBaseline
}
public struct GrowthChange: Sendable, Identifiable {
    public let id, label: String
    public let logicalDelta: Int64
    public let dimension: GrowthDimension
    public var category: CatalogCategory? = nil
    public var ruleID: String? = nil
}
/// A location whose coverage differs between the two scans. Its size change is never counted as growth.
public struct GrowthCoverageChange: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable { case newlyReadable, newlyUnreadable, newlyScanned, noLongerScanned }
    public let id, label: String
    public let kind: Kind
    public let category: CatalogCategory?
    public let ruleID: String?
}
public struct GrowthComparison: Sendable {
    public let state: GrowthComparisonState
    public static var unknown: GrowthComparison { GrowthComparison(state: .unknown, current: nil, from: nil, groups: []) }
    public let current: GrowthSnapshot?
    public let from: Date?
    public var to: Date? { current?.observedAt }
    public let groups: [GrowthChange]
    /// Catalog locations whose coverage changed; left out of `groups` and `logicalDelta`.
    public var coverageChanges: [GrowthCoverageChange] = []
    public var logicalDelta: Int64? { state == .compared ? groups.filter { $0.dimension != .category }.reduce(0) { $0 + $1.logicalDelta } : nil }
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
    private struct Archive: Codable { var version = 1; var entries: [Entry] = []; var hadHistory = false; var cleared = false; var activities: [ScanActivity]? = nil }
    /// How much older a scan must be to serve as the baseline: about a day, a little under 24 h so a check at about
    /// the same time each day compares with the day before (#126).
    public static let minimumBaselineAge: TimeInterval = 20 * 3_600
    private let directory: URL
    private let policy: GrowthRetention
    private let baselineAge: TimeInterval
    /// `minimumBaselineAge` is a test seam; the app always uses the default.
    public init(directory: URL, policy: GrowthRetention = GrowthRetention(), minimumBaselineAge: TimeInterval = GrowthHistoryStore.minimumBaselineAge) {
        self.directory = directory; self.policy = policy; baselineAge = max(0, minimumBaselineAge)
    }
    public func activities(now: Date = Date(), maintain: Bool = true) throws -> [ScanActivity] {
        try withStoreLock {
            var value = try load()
            let count = value.entries.count + (value.activities?.count ?? 0)
            try trim(&value, now: now)
            if maintain && value.entries.count + (value.activities?.count ?? 0) != count { try save(value) }
            return (value.activities ?? []).sorted { $0.completedAt > $1.completedAt }
        }
    }
    @discardableResult public func recordActivity(_ activity: ScanActivity, now: Date = Date(), expectedEpoch: UUID) throws -> Bool {
        try withStoreLock {
            guard try currentEpoch() == expectedEpoch else { return false }
            guard activity.valid, activity.completedAt <= now else { throw CocoaError(.fileWriteInvalidFileName) }
            var value = try load()
            value.activities = (value.activities ?? []).filter { $0.id != activity.id } + [activity]
            try trim(&value, now: now)
            guard value.activities?.contains(where: { $0.id == activity.id }) == true else { throw CocoaError(.fileWriteOutOfSpace) }
            try save(value); return true
        }
    }
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
            let hasLocationHistory = value.entries.contains { $0.snapshot.fingerprint.scopeID == snapshot.fingerprint.scopeID }
            let origin: GrowthComparisonState = value.cleared ? .clearedBaseline
                : hasLocationHistory ? .missingBaseline : .firstBaseline
            value.entries.append(Entry(snapshot: snapshot, origin: origin)); value.hadHistory = true; value.cleared = false
            value.entries = thinned(value.entries)
            try trim(&value, now: now)
            try save(value)
            return value.entries.contains(where: { $0.snapshot.id == snapshot.id }) ? comparison(in: value, id: snapshot.id) : GrowthComparison(state: .unknown, current: snapshot, from: nil, groups: [])
        }
    }
    /// Reject observations started under previous settings while retaining compatible historical aggregates.
    public func invalidateCoverage() throws { try withStoreLock { try writeEpoch(UUID()) } }
    public func clearCompletedHistory() throws {
        try withStoreLock {
            try writeEpoch(UUID())
            var value = try load(); value.entries = []; value.activities = []; value.cleared = true
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
        guard let previous = baselineIndex(in: value.entries, for: index).map({ value.entries[$0].snapshot }) else {
            let earlier = value.entries[..<index].contains { $0.snapshot.fingerprint.scopeID == current.fingerprint.scopeID }
            return GrowthComparison(state: earlier ? .waitingForBaseline : value.entries[index].origin, current: current, from: nil, groups: [])
        }
        guard current.fingerprint == previous.fingerprint else { return GrowthComparison(state: .coverageChanged, current: current, from: previous.observedAt, groups: []) }
        if (current.groups + previous.groups).contains(where: { $0.dimension == .location }) { return Self.catalogComparison(previous, current) }
        let older = Dictionary(uniqueKeysWithValues: previous.groups.map { ($0.id, $0) })
        let newer = Dictionary(uniqueKeysWithValues: current.groups.map { ($0.id, $0) })
        let changes = Set(older.keys).union(newer.keys).map { key in GrowthChange(id: key, label: newer[key]?.label ?? older[key]!.label, logicalDelta: (newer[key]?.logicalBytes ?? 0) - (older[key]?.logicalBytes ?? 0), dimension: newer[key]?.dimension ?? older[key]!.dimension) }.sorted { $0.id < $1.id }
        return GrowthComparison(state: .compared, current: current, from: previous.observedAt, groups: changes)
    }
    /// The scan the one at `index` compares with: the newest earlier scan of the same location at least about a day
    /// older that isn't a rescan right after a cleanup, unless the settings changed since: then that scan starts a new
    /// baseline.
    private func baselineIndex(in entries: [Entry], for index: Int) -> Int? {
        let current = entries[index].snapshot
        return entries[..<index].lastIndex { entry in
            let earlier = entry.snapshot
            return earlier.fingerprint.scopeID == current.fingerprint.scopeID && (earlier.fingerprint != current.fingerprint
                || (!earlier.afterCleanup && current.observedAt.timeIntervalSince(earlier.observedAt) >= baselineAge))
        }
    }
    /// How many of the newest scans are always kept, however close together.
    static let recentScansKept = 5
    /// At most `policy.baselines` scans, kept in this order (#146): the newest scan and the baseline it compares with;
    /// the few newest scans and the baseline of each location's newest scan; one scan per day and location, the
    /// newest that can be a baseline; then the newest of the rest. Frequent rescans can't push out every baseline.
    private func thinned(_ entries: [Entry]) -> [Entry] {
        guard entries.count > policy.baselines else { return entries }
        var rank = [Int](repeating: 3, count: entries.count)
        func keep(_ index: Int?, _ tier: Int) { if let index { rank[index] = min(rank[index], tier) } }
        let last = entries.count - 1
        keep(last, 0); keep(baselineIndex(in: entries, for: last), 0)
        for index in entries.indices.suffix(Self.recentScansKept) { keep(index, 1) }
        let newestPerLocation = Dictionary(entries.indices.map { (entries[$0].snapshot.fingerprint.scopeID, $0) }, uniquingKeysWith: max)
        for index in newestPerLocation.values { keep(baselineIndex(in: entries, for: index), 1) }
        let calendar = Calendar.current
        let days = Dictionary(grouping: entries.indices) { DayKey(scope: entries[$0].snapshot.fingerprint.scopeID, day: calendar.startOfDay(for: entries[$0].snapshot.observedAt)) }
        for indices in days.values { keep(indices.last { !entries[$0].snapshot.afterCleanup } ?? indices.last, 2) }
        let kept = Set(entries.indices.sorted { (rank[$0], -$0) < (rank[$1], -$1) }.prefix(policy.baselines))
        return entries.indices.filter(kept.contains).map { entries[$0] }
    }
    private struct DayKey: Hashable { let scope: String; let day: Date }
    /// Compares catalog scans location by location. Only a location measured in both scans counts toward growth,
    /// per location and in its category; any other difference is a coverage change.
    static func catalogComparison(_ previous: GrowthSnapshot, _ current: GrowthSnapshot) -> GrowthComparison {
        let older = Dictionary(uniqueKeysWithValues: previous.groups.filter { $0.dimension == .location }.map { ($0.id, $0) })
        let newer = Dictionary(uniqueKeysWithValues: current.groups.filter { $0.dimension == .location }.map { ($0.id, $0) })
        var changes: [GrowthChange] = [], coverage: [GrowthCoverageChange] = [], categories: [CatalogCategory?: Int64] = [:]
        for key in Set(older.keys).union(newer.keys).sorted() {
            let group = (newer[key] ?? older[key])!
            func covered(_ kind: GrowthCoverageChange.Kind) { coverage.append(GrowthCoverageChange(id: key, label: group.label, kind: kind, category: group.category, ruleID: group.ruleID)) }
            switch (older[key], newer[key]) {
            case let (old?, new?) where old.isMeasured && new.isMeasured:
                let delta = new.logicalBytes - old.logicalBytes
                changes.append(GrowthChange(id: key, label: group.label, logicalDelta: delta, dimension: .location, category: group.category, ruleID: group.ruleID))
                categories[group.category, default: 0] += delta
            case let (old?, new?) where old.isMeasured != new.isMeasured: covered(new.isMeasured ? .newlyReadable : .newlyUnreadable)
            case (nil, _?): covered(.newlyScanned)
            case (_?, nil): covered(.noLongerScanned)
            default: break // Unreadable in both scans: nothing to compare.
            }
        }
        changes += categories.map { GrowthChange(id: "category:" + ($0.key?.rawValue ?? ""), label: $0.key?.rawValue ?? "", logicalDelta: $0.value, dimension: .category, category: $0.key) }
        var result = GrowthComparison(state: .compared, current: current, from: previous.observedAt, groups: changes.sorted { $0.id < $1.id })
        result.coverageChanges = coverage
        return result
    }
    private func trim(_ value: inout Archive, now: Date) throws {
        value.entries.removeAll { now.timeIntervalSince($0.snapshot.observedAt) > Double(policy.days) * 86400 }
        value.activities = (value.activities ?? []).filter { now.timeIntervalSince($0.completedAt) <= Double(policy.days) * 86400 }.sorted { $0.completedAt < $1.completedAt }
        while try JSONEncoder().encode(value).count > policy.bytes {
            let scanDate = value.activities?.first?.completedAt
            let baselineDate = value.entries.first?.snapshot.observedAt
            if let scanDate, baselineDate == nil || scanDate <= baselineDate! { value.activities?.removeFirst() }
            else if !value.entries.isEmpty { value.entries.removeFirst() }
            else { throw CocoaError(.fileWriteOutOfSpace) }
        }
    }
    private func retained(_ now: Date) throws -> Archive {
        var value = try load()
        let count = value.entries.count + (value.activities?.count ?? 0)
        try trim(&value, now: now)
        if value.entries.count + (value.activities?.count ?? 0) != count { try save(value) }
        return value
    }
    private func load() throws -> Archive {
        try verifyDirectory(create: false)
        let file = directory.appendingPathComponent("aggregates-v1.json")
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw CocoaError(.fileReadNoPermission) }
            return Archive()
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid() else { throw CocoaError(.fileReadNoPermission) }
        guard info.st_size <= policy.bytes else { throw CocoaError(.fileReadTooLarge) }
        let decoded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
        guard decoded.version == 1, (decoded.activities ?? []).allSatisfy(\.valid), Set((decoded.activities ?? []).map(\.id)).count == (decoded.activities?.count ?? 0), decoded.entries.count <= policy.baselines, decoded.entries.allSatisfy({ entry in
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
