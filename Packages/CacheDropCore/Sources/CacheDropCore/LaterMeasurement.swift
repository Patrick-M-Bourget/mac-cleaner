import Foundation

/// A stopped daemon-backed tool's item, measured again a little after the run (#190, Decision 45). The daemon may have
/// finished the work after CacheDrop stopped waiting, so the record gains what the item measured then. Found gone, the
/// outcome becomes removed, finished after the stop (#209); otherwise it keeps "may still be finishing".
public struct LaterMeasurement: Codable, Sendable, Equatable {
    public enum Finding: Codable, Sendable, Equatable {
        /// The rule no longer offers the item: all of it went.
        case gone
        /// The item is still offered, at this size (measured as the scan measures it).
        case remaining(bytes: Int64)
        /// It couldn't be measured again: its tool or daemon didn't answer, or its size was never known.
        case unmeasured
        /// Stored in the journal (#448): a renamed case keeps its key here.
        private enum CodingKeys: String, CodingKey { case gone = "gone", remaining = "remaining", unmeasured = "unmeasured" }
        private enum GoneCodingKeys: CodingKey {}
        private enum RemainingCodingKeys: String, CodingKey { case bytes = "bytes" }
        private enum UnmeasuredCodingKeys: CodingKey {}
    }
    public let measuredAt: Date
    public let finding: Finding
    /// How long after the run it was measured (#209); nil in journals written before, which measured once at 60 s.
    public let afterSeconds: Int?
    private enum CodingKeys: String, CodingKey { case measuredAt = "measuredAt", finding = "finding", afterSeconds = "afterSeconds" }
    public init(measuredAt: Date, finding: Finding, afterSeconds: Int) {
        self.measuredAt = measuredAt; self.finding = finding; self.afterSeconds = afterSeconds
    }
}

extension Catalog {
    /// Only the rules `candidates` came from, so measuring them again runs nothing else.
    public func only(_ candidates: [Candidate]) -> Catalog {
        let ids = Set(candidates.map(\.ruleID))
        return Catalog(rules: rules.filter { ids.contains($0.id) })
    }

    /// What each candidate measures in a fresh `discovery` of its rule, by candidate id. An item is matched by rule,
    /// path and tool item, not by identity, since a daemon's work can change the folder it is anchored on.
    public func measuredAgain(_ candidates: [Candidate], in discovery: CatalogDiscovery) -> [String: LaterMeasurement.Finding] {
        let scanned = Set(discovery.scannedRuleIDs)
        let troubled = Set(discovery.notes.map(\.ruleID)).union(discovery.notMeasured.keys)
        return Dictionary(uniqueKeysWithValues: candidates.map { candidate in
            guard candidate.sizeComplete, scanned.contains(candidate.ruleID), !troubled.contains(candidate.ruleID) else { return (candidate.id, .unmeasured) }
            let now = discovery.candidates.first { $0.ruleID == candidate.ruleID && $0.url.path == candidate.url.path && $0.toolItem == candidate.toolItem }
            guard let now else { return (candidate.id, .gone) }
            return (candidate.id, now.sizeComplete ? .remaining(bytes: now.estimatedBytes) : .unmeasured)
        })
    }
}

extension CleanupRecord {
    static let finishedAfterStopMessage = "Finished after you stopped it."
    /// A stopped daemon-backed tool's item that a later measurement found gone (#209): its outcome reads "Removed".
    public var finishedAfterStop: Bool { state == .succeeded && mayStillBeFinishing == true && laterMeasurement?.finding == .gone }
    /// A stopped daemon-backed tool's item not yet measured again (#190).
    var awaitsLaterMeasurement: Bool { mayStillBeFinishing == true && laterMeasurement == nil }

    /// History's line on the run's last Docker record once the disk was read again a minute after the run (#411); nil
    /// before then and on every other record. Other apps change free space too, so it never says Docker freed it.
    public var settledText: String? {
        guard let change = settledCapacity?.observedChange else { return nil }
        return change > 0 ? "A minute later, the disk had \(ByteCountFormatter.string(fromByteCount: change, countStyle: .decimal)) more free."
            : "A minute later, the disk had no more free space."
    }

    /// One line for Results and History once the item was measured again; nil before then.
    public var laterMeasurementText: String? {
        guard let finding = laterMeasurement?.finding else { return nil }
        let scanned = allocatedBytes ?? logicalBytes
        func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
        let later = Self.laterMeasurementWhen(laterMeasurement?.afterSeconds ?? 60)
        switch finding {
        case .gone: return "Measured again \(later): it’s gone (\(size(scanned)) at the scan)."
        case .remaining(let bytes) where bytes < scanned:
            return "Measured again \(later): \(size(scanned - bytes)) of \(size(scanned)) went; \(size(bytes)) is left."
        case .remaining: return "Measured again \(later): nothing went yet."
        case .unmeasured: return "Couldn’t measure it again \(later)."
        }
    }

    /// When the item was measured again: "a minute later", "5 minutes later".
    static func laterMeasurementWhen(_ seconds: Int) -> String {
        if seconds == 60 { return "a minute later" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full; formatter.allowedUnits = [.minute, .second]
        return (formatter.string(from: TimeInterval(seconds)) ?? "") + " later"
    }
}
