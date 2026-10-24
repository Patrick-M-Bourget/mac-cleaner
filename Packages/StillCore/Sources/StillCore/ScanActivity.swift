import Foundation

public enum ScanActivityOutcome: String, Codable, Sendable { case complete, partial, stopped, failed }
public struct ScanActivityLocation: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let observedAt: Date?
    public let outcome: ScanActivityOutcome?
    public let entryCount: Int?
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?
    public let knownLogicalBytes: Int64?
    public let reasons: [String: Int]
    public let baselineID: UUID?
    public init(path: String, observedAt: Date? = nil, outcome: ScanActivityOutcome? = nil, entryCount: Int? = nil, logicalBytes: Int64? = nil, allocatedBytes: Int64? = nil, knownLogicalBytes: Int64? = nil, reasons: [String: Int] = [:], baselineID: UUID? = nil) {
        self.path = path; self.observedAt = observedAt; self.outcome = outcome; self.entryCount = entryCount
        self.logicalBytes = logicalBytes; self.allocatedBytes = allocatedBytes; self.knownLogicalBytes = knownLogicalBytes; self.reasons = reasons; self.baselineID = baselineID
    }
    public init(scan: ScanResult, baselineID: UUID? = nil) {
        self.init(path: scan.scope.standardizedFileURL.path, observedAt: scan.observedAt, outcome: scan.isComplete ? .complete : .partial,
                  entryCount: scan.observations.count, logicalBytes: scan.totalLogicalBytes, allocatedBytes: scan.totalAllocatedBytes,
                  knownLogicalBytes: scan.logicalBytes, reasons: Dictionary(scan.issues.map { ($0.reason.rawValue, 1) }, uniquingKeysWith: +), baselineID: baselineID)
    }
}
public struct ScanActivity: Codable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt, completedAt: Date
    public let outcome: ScanActivityOutcome
    public let locations: [ScanActivityLocation]
    public init(id: UUID = UUID(), startedAt: Date, completedAt: Date, outcome: ScanActivityOutcome, locations: [ScanActivityLocation]) {
        self.id = id; self.startedAt = startedAt; self.completedAt = completedAt; self.outcome = outcome; self.locations = locations
    }
    var valid: Bool {
        startedAt <= completedAt && !locations.isEmpty && locations.count <= 128 && Set(locations.map(\.path)).count == locations.count && locations.allSatisfy {
            $0.path.hasPrefix("/") && $0.path.utf8.count <= 4096 && !$0.path.contains("\0") && ($0.observedAt.map { $0 >= startedAt && $0 <= completedAt } ?? true)
            && [$0.entryCount].compactMap { $0 }.allSatisfy { $0 >= 0 }
            && [$0.logicalBytes, $0.allocatedBytes, $0.knownLogicalBytes].compactMap { $0 }.allSatisfy { $0 >= 0 }
            && $0.reasons.count <= 32 && $0.reasons.allSatisfy { $0.key.utf8.count <= 64 && $0.value > 0 }
        }
    }
}
