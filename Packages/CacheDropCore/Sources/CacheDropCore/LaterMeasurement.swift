import Foundation

/// A stopped daemon-backed tool's item, measured again a little after the run (#190, Decision 45). The daemon may have
/// finished the work after CacheDrop stopped waiting, so the record keeps "may still be finishing" and gains what the
/// item measured then. It is an observation, never a change of the recorded outcome.
public struct LaterMeasurement: Codable, Sendable, Equatable {
    public enum Finding: Codable, Sendable, Equatable {
        /// The rule no longer offers the item: all of it went.
        case gone
        /// The item is still offered, at this size (measured as the scan measures it).
        case remaining(bytes: Int64)
        /// It couldn't be measured again: its tool or daemon didn't answer, or its size was never known.
        case unmeasured
    }
    public let measuredAt: Date
    public let finding: Finding
    public init(measuredAt: Date, finding: Finding) { self.measuredAt = measuredAt; self.finding = finding }
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
    /// One line for Results and History once the item was measured again; nil before then.
    public var laterMeasurementText: String? {
        guard let finding = laterMeasurement?.finding else { return nil }
        let scanned = allocatedBytes ?? logicalBytes
        func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
        switch finding {
        case .gone: return "Measured again a minute later: it’s gone (\(size(scanned)) at the scan)."
        case .remaining(let bytes) where bytes < scanned:
            return "Measured again a minute later: \(size(scanned - bytes)) of \(size(scanned)) went; \(size(bytes)) is left."
        case .remaining: return "Measured again a minute later: nothing went yet."
        case .unmeasured: return "Couldn’t measure it again a minute later."
        }
    }
}
