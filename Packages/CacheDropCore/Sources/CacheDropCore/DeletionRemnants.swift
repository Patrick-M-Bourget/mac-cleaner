import Foundation
import Darwin

/// A delete first renames its item aside to `.cachedrop-deleting-<rule id>-<uuid>`, in the same folder, then removes it.
/// When removal stops partway, the rest stays there; discovery offers it again under the same rule.
extension Catalog {
    static let deletionRemnantMarker = ".cachedrop-deleting-"
    /// The marker Still, the app's former name, renamed items aside with; its deletion remnants are still offered (#150).
    static let legacyDeletionRemnantMarker = ".still-deleting-"
    static func deletionRemnantName(for ruleID: String) -> String { deletionRemnantMarker + ruleID + "-" + UUID().uuidString }
    /// Whether `name` is what a delete under `ruleID` renamed its item to, by CacheDrop or by Still.
    static func isDeletionRemnant(_ name: String, of ruleID: String) -> Bool {
        [deletionRemnantMarker, legacyDeletionRemnantMarker].contains { marker in
            let prefix = marker + ruleID + "-"
            return name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
        }
    }

    /// Deletion remnants of `rule`'s earlier deletes: siblings of its locations, or entries of a leaked-copies or unused-items location.
    /// Each is offered as a plain delete, whatever the rule's own action.
    func deletionRemnants(of rule: CleanupRule, in base: URL, sizer: KnownLocationSizer) -> [Candidate] {
        guard rule.deletesItems else { return [] }
        return deletionRemnants(of: rule, in: Set(deletionRemnantFolders(of: rule, in: base)), base: base, sizer: sizer)
    }

    /// The folders `rule`'s own deletion remnants are looked for in, from its locations.
    func deletionRemnantFolders(of rule: CleanupRule, in base: URL) -> [URL] {
        rule.locations.flatMap { location in
            Self.pathsMatching(rule.copies != nil || rule.unused != nil ? location : (location as NSString).deletingLastPathComponent, under: base).map(\.0)
        }
    }

    /// Deletion remnants of an interrupted clean of a folder a tool named or its config set (#170, #201): siblings of that folder,
    /// which may itself be missing, since a delete renames it aside first (#202). The named folder must not be inside the
    /// user's own folders or hold more than the tool's cache, and each deletion remnant passes #205's write-scope checks; only the
    /// tool's markers aren't asked for, since a half-deleted cache may have lost them. Folders the usual deletion remnants are
    /// looked for in are skipped, so nothing is offered twice.
    func deletionRemnants(of rule: CleanupRule, nextTo named: URL, in base: URL, sizer: KnownLocationSizer) -> [Candidate] {
        let folder = named.deletingLastPathComponent().standardizedFileURL
        guard rule.deletesItems, !holdsMoreThanACache(named, base: base, besides: rule), Self.userContentFolder(holding: named, base: base) == nil,
              !deletionRemnantFolders(of: rule, in: base).contains(where: { $0.standardizedFileURL.path == folder.path }) else { return [] }
        return deletionRemnants(of: rule, in: [folder], base: base, sizer: sizer).filter { notACache($0.url, of: rule, markers: nil, base: base) == nil }
    }

    private func deletionRemnants(of rule: CleanupRule, in folders: Set<URL>, base: URL, sizer: KnownLocationSizer) -> [Candidate] {
        folders.sorted { $0.path < $1.path }.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().filter { Self.isDeletionRemnant($0, of: rule.id) }.compactMap { name -> Candidate? in
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
    public var isDeletionRemnant: Bool { Catalog.isDeletionRemnant(url.lastPathComponent, of: ruleID) }
    /// The candidate as discovery hands it out, with the base folder it was found under.
    func found(under base: URL) -> Candidate {
        var found = self
        found.scopeRoot = base
        return found
    }
}
