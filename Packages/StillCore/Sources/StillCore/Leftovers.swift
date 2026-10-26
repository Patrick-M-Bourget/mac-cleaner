import Foundation
import Darwin

/// A delete first renames its item aside to `.still-deleting-<rule id>-<uuid>`, in the same folder, then removes it.
/// When removal stops partway, the rest stays there; discovery offers it again under the same rule.
extension Catalog {
    static let leftoverMarker = ".still-deleting-"
    static func leftoverName(for ruleID: String) -> String { leftoverMarker + ruleID + "-" + UUID().uuidString }
    /// Whether `name` is what a delete under `ruleID` renamed its item to.
    static func isLeftover(_ name: String, of ruleID: String) -> Bool {
        let prefix = leftoverMarker + ruleID + "-"
        return name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
    }

    /// Leftovers of `rule`'s earlier deletes: siblings of its locations, or entries of a leaked-copies location.
    /// Each is offered as a plain delete, whatever the rule's own action.
    func leftovers(of rule: CleanupRule, in base: URL, sizer: KnownLocationSizer) -> [Candidate] {
        guard rule.deletesItems else { return [] }
        let folders = Set(rule.locations.flatMap { location in
            Self.expand(base, rule.copies != nil ? location : (location as NSString).deletingLastPathComponent).map(\.0)
        })
        return folders.sorted { $0.path < $1.path }.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().filter { Self.isLeftover($0, of: rule.id) }.compactMap { name -> Candidate? in
                let url = folder.appendingPathComponent(name)
                var info = stat()
                guard Protection(rule).protectedComponent(of: url, below: base) == nil, ScopeContainment.contains(url, in: base), lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return nil }
                if info.st_mode & S_IFMT == S_IFDIR, CandidateCheck.protectedEntry(in: url, rule: rule) != nil { return nil }
                let size = sizer.size(url)
                return candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil, action: .delete)
            }
        }
    }
}

extension CleanupRule {
    /// Whether the rule's cleanup deletes the items it found, directly or after its tool runs.
    var deletesItems: Bool { (action == .delete && contents == nil && items == nil) || tool?.deletesLocationAfter == true }
}

extension Candidate {
    /// What an earlier delete under this rule left behind.
    public var isLeftover: Bool { Catalog.isLeftover(url.lastPathComponent, of: ruleID) }
    /// The candidate as discovery hands it out, with the base folder it was found under.
    func found(under base: URL) -> Candidate {
        var found = self
        found.scopeRoot = base
        return found
    }
}
