import Foundation
import Darwin

/// Old items in the user's own temp (`T`) and cache (`C`) folders under `/private/var/folders` (#132). Each visible
/// file or folder directly inside a location is one item. It is offered only when the user owns everything in it,
/// nothing in it changed for `unusedDays`, and no process of the user's has a file in it open or mapped.
public struct UnusedItems: Sendable {
    /// Days since anything inside last changed (modified or its metadata changed).
    public let unusedDays: Int
    public init(unusedDays: Int) { self.unusedDays = unusedDays }
}

extension RuleOwner {
    /// Any process of the user's: an item it has open or mapped is in use.
    public static let anyApp = RuleOwner(name: "An app", executables: ["*"])
}

public enum TemporaryFiles {
    /// Field note sections 3 and 6: temp and cache files apps left behind. `X` is never a location; only the Chrome rule acts there.
    static let rule = CleanupRule(
        id: "temporary-files", category: .system, title: "Old temporary files",
        detail: "Temp and cache files apps left in your temporary folder, unchanged for 3 days.",
        consequence: "Permanently removed. Nothing open or recently changed is offered; an app that wants one again recreates it.",
        regen: .cache, action: .delete, locations: ["T", "C"], owner: nil, base: .userFolder,
        yieldsToOtherRules: true, protectedDepth: AppCaches.liveWorkDepth, unused: UnusedItems(unusedDays: 3))
}

extension Catalog {
    /// Items inside `root` that meet `rule`'s conditions. When in-use status can't be determined, nothing is offered and the note says why.
    func unusedItems(_ rule: CleanupRule, _ unused: UnusedItems, in root: URL, base: URL, now: Date, sizer: KnownLocationSizer,
                     inUse checker: any InUseChecking) -> ([Candidate], CatalogNote?) {
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR, rootInfo.st_uid == geteuid() else { return ([], nil) }
        let protection = Protection(rule)
        let cutoff = now.addingTimeInterval(-Double(unused.unusedDays) * 86_400)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted().prefix(Self.childLimit)
        let found = names.compactMap { name -> (URL, stat, ItemSize)? in
            var info = stat()
            let url = root.appendingPathComponent(name)
            guard !name.hasPrefix("."), !protection.protects(name), lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                  [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return nil }
            guard let changed = Self.lastChange(in: url), changed < cutoff, !claimedByAnotherRule(url, besides: rule, base: base) else { return nil }
            if info.st_mode & S_IFMT == S_IFDIR, CandidateCheck.protectedEntry(in: url, rule: rule) != nil { return nil }
            let size = sizer.size(url)
            // Nothing to free: empty folders and lock files stay out of the plan.
            guard (size.allocatedBytes ?? 0) > 0 else { return nil }
            return (url, info, size)
        }
        guard !found.isEmpty else { return ([], nil) }
        guard let used = checker.inUse(found.map(\.0), by: .anyApp) else {
            return ([], CatalogNote(ruleID: rule.id, text: "\(rule.title): kept all, because Still couldn’t tell which ones apps are using."))
        }
        return (found.filter { !used.contains($0.0.path) }.map { url, info, size in
            candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
        }, nil)
    }

    /// The latest modification or status change of `url` and everything inside it; nil when part of it can't be read,
    /// another user owns part of it, or it holds too many entries to check.
    static func lastChange(in url: URL) -> Date? {
        var latest = timespec(tv_sec: 0, tv_nsec: 0), seen = 0, known = true
        func later(_ a: timespec, _ b: timespec) -> Bool { (a.tv_sec, a.tv_nsec) > (b.tv_sec, b.tv_nsec) }
        let opened = FileTree.walk(url) { entry in
            let kind = Int32(entry.pointee.fts_info)
            if kind == FTS_DP { return .continue }
            seen += 1
            guard seen <= CandidateCheck.protectedSearchLimit, ![FTS_DNR, FTS_ERR, FTS_NS].contains(kind),
                  let info = entry.pointee.fts_statp?.pointee, info.st_uid == geteuid() else { known = false; return .stop }
            for time in [info.st_mtimespec, info.st_ctimespec] where later(time, latest) { latest = time }
            return .continue
        }
        guard opened, known else { return nil }
        return Date(timeIntervalSince1970: Double(latest.tv_sec) + Double(latest.tv_nsec) / 1e9)
    }
}
