import Foundation
import Darwin

/// What a completed catalog scan records for What grew: one group per scanned rule location, with its category,
/// its size and whether it could be read. Every scanned location is recorded, found or not, so a location that
/// appears later is growth, while one the scan starts or stops covering is a coverage change.
public enum CatalogGrowth {
    public static func groups(_ discovery: CatalogDiscovery, catalog: Catalog, fullDiskAccess: FullDiskAccessStatus) -> [GrowthAggregate] {
        struct Group { let rule: CleanupRule; let location: String; var bytes: Int64 = 0; var measured: Bool }
        var groups: [String: Group] = [:], order: [String] = []
        for id in discovery.scannedRuleIDs {
            guard let rule = catalog.rule(id) else { continue }
            let readable = rule.access(given: fullDiskAccess) == .available
            for location in rule.locations where groups[key(rule, location)] == nil {
                groups[key(rule, location)] = Group(rule: rule, location: location, measured: readable)
                order.append(key(rule, location))
            }
        }
        for candidate in discovery.candidates {
            guard let rule = catalog.rule(candidate.ruleID), let location = location(of: candidate, under: rule), groups[key(rule, location)] != nil else { continue }
            groups[key(rule, location)]!.bytes += candidate.estimatedBytes
            if !candidate.sizeComplete { groups[key(rule, location)]!.measured = false }
        }
        return order.map { id in
            let group = groups[id]!
            return GrowthAggregate(id: id, label: label(group.location, base: group.rule.base), logicalBytes: group.bytes, dimension: .location,
                                   category: group.rule.category.rawValue, ruleID: group.rule.id, measured: group.measured)
        }
    }

    static func key(_ rule: CleanupRule, _ location: String) -> String { "location:" + rule.id + "|" + location }

    /// The rule location a candidate was found in: the one whose pattern its path starts with, or for a leftover
    /// of an earlier delete, the one it sits beside. The rule's first location when neither matches.
    static func location(of candidate: Candidate, under rule: CleanupRule) -> String? {
        let parts = candidate.scopeRoot.map { Array(candidate.url.pathComponents.dropFirst($0.pathComponents.count)) } ?? []
        func matches(_ pattern: [String], _ path: [String]) -> Bool {
            path.count >= pattern.count && zip(pattern, path).allSatisfy { fnmatch($0, $1, 0) == 0 }
        }
        let patterns = rule.locations.map { ($0, $0.split(separator: "/").map(String.init)) }
        return patterns.first { matches($0.1, parts) }?.0
            ?? patterns.first { matches(Array($0.1.dropLast()), Array(parts.dropLast())) && parts.count == $0.1.count }?.0
            ?? rule.locations.first
    }

    /// A location as the user reads it, e.g. `~/Library/Caches`. Wildcard parts read as "…", and a trailing one is dropped.
    static func label(_ location: String, base: LocationBase) -> String {
        var parts = location.split(separator: "/").map(String.init)
        while parts.last?.contains("*") == true { parts.removeLast() }
        let path = parts.map { $0.contains("*") ? "…" : $0 }.joined(separator: "/")
        switch base {
        case .home: return path.isEmpty ? "~" : "~/" + path
        case .userFolder: return path.isEmpty ? "Your temporary folder" : "Your temporary folder/" + path
        }
    }
}
