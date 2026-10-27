import Foundation
import Darwin

/// The large and old files explorer: files in a folder the user picked, offered one by one for Trash.
/// Candidates come from the folder's existing `FolderScanner` scan, never a second walk, and are checked
/// like any catalog item (SPEC section 4) under the "user files" rule.
public enum UserFiles {
    public static let ruleID = "user-files"
    /// RESET Decision 18, shared with the Downloads rule: 500 MB or more is large; not opened in 90 days is old.
    public static let largeBytes: Int64 = 500_000_000
    public static let unusedDays = 90
    /// At most this many files are listed, largest first.
    public static let listLimit = 500

    public static let rule = CleanupRule(id: ruleID, category: .files, title: "Large and old files",
        detail: "Files in folders you picked: 500 MB or more, or not opened in 90 days.",
        consequence: "Moved to Trash. The space stays used until you empty the Trash; you can restore them from the Trash in Finder.",
        regen: .userFile, action: .trash, locations: [], owner: nil,
        protectedExtensions: BuiltInCatalog.downloadsProtectedExtensions, fromPickedFolders: true)

    /// The scan's files that are large or old, largest first. Read-only.
    public static func candidates(in scan: ScanResult, rule: CleanupRule = rule, exclusions: ExclusionPolicy = ExclusionPolicy(),
                                  home: URL, now: Date = Date()) -> [Candidate] {
        // The scope and its items in canonical form, so containment holds for `/var` against `/private/var`.
        guard let scopePath = realPath(scan.scope.path) else { return [] }
        let catalog = Catalog(rules: [rule]), scope = URL(fileURLWithPath: scopePath, isDirectory: true)
        let protection = Protection(rule)
        // A folder picked inside a git working tree (a project's build folder) offers nothing.
        if GitCheckout.encloses(scope, upTo: nil, home: home) { return [] }
        let cutoff = now.addingTimeInterval(-Double(unusedDays) * 86_400)
        var seen = Set<String>(), found: [Candidate] = []
        for item in scan.observations.filter({ $0.kind == .file }).sorted(by: { ($0.logicalBytes ?? 0) > ($1.logicalBytes ?? 0) }) {
            guard found.count < listLimit else { break }
            var info = stat()
            guard lstat(item.url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.resourceID == item.resourceID,
                  seen.insert(info.resourceID).inserted, let path = realPath(item.url.path) else { continue }
            let url = URL(fileURLWithPath: path)
            guard info.st_uid == geteuid(), info.st_flags & UInt32(SF_DATALESS) == 0, item.cloud.membership == false,
                  protection.protectedComponent(of: url, below: scope) == nil, protectedFolder(of: url, home: home) == nil, !GitCheckout.encloses(url, upTo: scope, home: home) else { continue }
            let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            if !exclusions.rules.isEmpty, volume.map({ exclusions.covers(url, volumeID: $0) }) ?? true { continue }
            let size = Int64(info.st_size)
            if size < largeBytes, statDates(info).max()! > cutoff { continue }
            let lastUsed = Catalog.lastUsed(url, info)
            guard size >= largeBytes || lastUsed <= cutoff else { continue }
            found.append(catalog.candidate(rule, url, info, logical: size, allocated: Int64(info.st_blocks) * 512, complete: true, lastUsed: lastUsed).found(under: scope))
        }
        return found
    }

    /// The picked files still worth offering after a run (#125): drops only the ones it acted on, or may have,
    /// so a cleanup never wipes a folder's other large and old files.
    public static func remaining(_ files: [Candidate], after result: CatalogExecutionResult) -> [Candidate] {
        let touched = Set(result.records.filter { [.succeeded, .intent, .unknown].contains($0.state) }.map(\.candidateID))
        return files.filter { !touched.contains($0.id) }
    }

    /// Folders in the home folder whose files are never offered from a picked folder, whatever the scope:
    /// `Library` holds app and browser data (logins, cookies, history, mail) that SPEC section 2 never touches.
    static let protectedFolders = ["Library"]
    /// The protected home folder `url` lies in, if any.
    static func protectedFolder(of url: URL, home: URL) -> String? {
        guard let item = realPath(url.path) ?? realPath(url.deletingLastPathComponent().path), let home = realPath(home.path) else { return nil }
        return protectedFolders.first { item.hasPrefix(home + "/" + $0 + "/") || item == home + "/" + $0 }
    }

    /// Access, change and creation times; Spotlight's last-opened date can only make a file more recent.
    private static func statDates(_ info: stat) -> [Date] {
        [info.st_atimespec, info.st_mtimespec, info.st_birthtimespec].map { Date(timeIntervalSince1970: Double($0.tv_sec) + Double($0.tv_nsec) / 1e9) }
    }
}
