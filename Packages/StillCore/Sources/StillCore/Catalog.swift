import Foundation
import Darwin
import CoreServices

/// What kind of data a rule covers; it decides how the data comes back.
public enum RegenClass: String, Codable, Sendable { case cache, build, updaterDownload, leakedCopy, log, installer, model, userFile }
/// Decision 3: regenerable data is deleted; user files go to Trash. Tool actions arrive with #99.
public enum CleanupAction: String, Codable, Sendable { case delete; case trash = "moveToTrash" }
public enum CatalogCategory: String, Codable, Sendable { case developer, browser, downloads, system, models }

/// Who must be closed before a rule's data is touched.
public struct RuleOwner: Sendable, Hashable {
    public let name: String
    /// App bundle identifiers, checked with NSRunningApplication.
    public let bundleIDs: [String]
    /// Executable names of a command-line tool (Decision 20).
    public let executables: [String]
    /// Script names the tool runs under an interpreter. npm runs as `node …/npm-cli.js`,
    /// so matching the script, not `node`, keeps editors and agents that run node from refusing it.
    public let scripts: [String]
    public init(name: String, bundleIDs: [String] = [], executables: [String] = [], scripts: [String] = []) {
        self.name = name; self.bundleIDs = bundleIDs; self.executables = executables; self.scripts = scripts
    }
}

/// Picks single files inside a rule's location instead of the location itself (Downloads).
/// A file matches when it meets every condition that is set.
public struct ContentsMatch: Sendable {
    /// Lowercased extensions the file must have; empty means any.
    public let extensions: Set<String>
    /// At least this many logical bytes.
    public let minimumBytes: Int64?
    /// Not opened, changed or added for this many days.
    public let unusedDays: Int?
    public init(extensions: Set<String> = [], minimumBytes: Int64? = nil, unusedDays: Int? = nil) {
        self.extensions = extensions; self.minimumBytes = minimumBytes; self.unusedDays = unusedDays
    }
}

/// One catalog entry. Everything category-specific lives here as data.
public struct CleanupRule: Sendable, Identifiable {
    public let id: String
    public let category: CatalogCategory
    public let title: String
    /// Short description for Overview and the plan.
    public let detail: String
    /// What happens if it is removed, shown at review.
    public let consequence: String
    public let regen: RegenClass
    public let action: CleanupAction
    /// Paths relative to the user's home folder; each existing one is a candidate.
    public let locations: [String]
    public let owner: RuleOwner?
    /// Names that are never acted on when they are the item, one of its ancestors, or a top-level entry inside it.
    public let protectedNames: [String]
    /// Extensions never acted on as the item or an ancestor, on top of the global ones.
    public let protectedExtensions: [String]
    /// When set, candidates are the matching files inside each location, not the location.
    public let contents: ContentsMatch?
    public init(id: String, category: CatalogCategory, title: String, detail: String, consequence: String, regen: RegenClass, action: CleanupAction, locations: [String], owner: RuleOwner?, protectedNames: [String] = [], protectedExtensions: [String] = [], contents: ContentsMatch? = nil) {
        self.id = id; self.category = category; self.title = title; self.detail = detail; self.consequence = consequence
        self.regen = regen; self.action = action; self.locations = locations; self.owner = owner; self.protectedNames = protectedNames
        self.protectedExtensions = protectedExtensions; self.contents = contents
    }
}

public enum BuiltInCatalog {
    public static let rules: [CleanupRule] = [
        CleanupRule(id: "npm-cache", category: .developer, title: "npm cache",
                    detail: "Packages npm downloaded for your projects.",
                    consequence: "Permanently removed. npm downloads packages again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: [".npm/_cacache"],
                    owner: RuleOwner(name: "npm", executables: ["npm", "npx"], scripts: ["npm", "npx", "npm-cli.js", "npx-cli.js"])),
        // RESET Decision 18. Installers come first so a large old installer is listed once, as an installer.
        CleanupRule(id: "downloads-installers", category: .downloads, title: "Installers in Downloads",
                    detail: "Disk images, packages and archives you downloaded, at any age.",
                    consequence: "Moved to Trash. The space stays used until you empty the Trash; you can restore them from the Trash in Finder.",
                    regen: .installer, action: .trash, locations: ["Downloads"], owner: nil,
                    protectedExtensions: downloadsProtectedExtensions, contents: ContentsMatch(extensions: ["dmg", "pkg", "zip"])),
        CleanupRule(id: "downloads-old-large", category: .downloads, title: "Large files not opened lately",
                    detail: "Downloads of 500 MB or more not opened in 90 days.",
                    consequence: "Moved to Trash. The space stays used until you empty the Trash; you can restore them from the Trash in Finder.",
                    regen: .userFile, action: .trash, locations: ["Downloads"], owner: nil,
                    protectedExtensions: downloadsProtectedExtensions, contents: ContentsMatch(minimumBytes: 500_000_000, unusedDays: 90)),
    ]
    /// Kept from the Downloads-era policy: libraries and databases are never moved, even inside Downloads.
    static let downloadsProtectedExtensions = ["dsym", "library", "db", "sqlite", "sqlite3"]
}

/// A concrete item a rule found, with the identity it had when sized.
public struct Candidate: Sendable, Identifiable, Hashable {
    public var id: String { ruleID + "|" + url.path + "|" + resourceID + "|" + action.rawValue }
    public let ruleID: String
    public let action: CleanupAction
    public let url: URL
    /// "dev:ino" of the item itself.
    public let resourceID: String
    public let isDirectory: Bool
    public let volumeID: String?
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let logicalBytes: Int64
    public let allocatedBytes: Int64?
    /// False when sizing stopped early; the size is then a lower bound.
    public let sizeComplete: Bool
    /// Most recent of last opened (Spotlight), accessed, changed and added. Files only.
    public let lastUsed: Date?
    public let observedAt: Date
}

public struct Catalog: Sendable {
    public let rules: [CleanupRule]
    public init(rules: [CleanupRule]) { self.rules = rules }
    public func rule(_ id: String) -> CleanupRule? { rules.first { $0.id == id } }

    /// Sizes only the rules' known locations under `home`. Read-only. An item two rules match is offered once, by the first.
    public func discover(home: URL, sizer: KnownLocationSizer = KnownLocationSizer(), now: Date = Date()) -> [Candidate] {
        let base = home.resolvingSymlinksInPath()
        var seen = Set<String>()
        return rules.flatMap { rule in
            rule.locations.flatMap { relative -> [Candidate] in
                let url = base.appendingPathComponent(relative)
                if let contents = rule.contents { return files(in: url, matching: contents, rule: rule, now: now) }
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return [] }
                let size = sizer.size(url)
                return [candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)]
            }
        }.filter { seen.insert($0.resourceID).inserted }
    }

    private func candidate(_ rule: CleanupRule, _ url: URL, _ info: stat, logical: Int64, allocated: Int64?, complete: Bool, lastUsed: Date?) -> Candidate {
        let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return Candidate(ruleID: rule.id, action: rule.action, url: url, resourceID: "\(info.st_dev):\(info.st_ino)",
                         isDirectory: info.st_mode & S_IFMT == S_IFDIR, volumeID: volume,
                         modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                         logicalBytes: logical, allocatedBytes: allocated, sizeComplete: complete, lastUsed: lastUsed, observedAt: Date())
    }

    /// Regular files under `root` that match. Never follows symlinks, crosses volumes or enters packages and protected folders.
    private func files(in root: URL, matching match: ContentsMatch, rule: CleanupRule, now: Date) -> [Candidate] {
        let protectedNames = CandidateCheck.protectedNames.union(rule.protectedNames)
        let protectedExtensions = CandidateCheck.protectedExtensions.union(rule.protectedExtensions)
        let path = strdup(root.path)
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return [] }
        defer { fts_close(tree) }
        var found: [Candidate] = []
        while let entry = fts_read(tree) {
            let kind = Int32(entry.pointee.fts_info)
            guard let info = entry.pointee.fts_statp?.pointee, kind == FTS_D || kind == FTS_F else { continue }
            let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
            let name = url.lastPathComponent, ext = url.pathExtension.lowercased()
            if kind == FTS_D {
                let package = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                if entry.pointee.fts_level > 0, package || protectedNames.contains(name) || protectedExtensions.contains(ext) { fts_set(tree, entry, FTS_SKIP) }
                continue
            }
            guard info.st_uid == geteuid(), !protectedExtensions.contains(ext), info.st_flags & UInt32(SF_DATALESS) == 0 else { continue }
            if !match.extensions.isEmpty, !match.extensions.contains(ext) { continue }
            if let minimum = match.minimumBytes, Int64(info.st_size) < minimum { continue }
            let lastUsed = Self.lastUsed(url, info)
            if let days = match.unusedDays, lastUsed > now.addingTimeInterval(-Double(days) * 86_400) { continue }
            found.append(candidate(rule, url, info, logical: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512, complete: true, lastUsed: lastUsed))
        }
        return found
    }

    /// Conservative "last used": the latest of Spotlight's last-opened date, access, change and creation times.
    static func lastUsed(_ url: URL, _ info: stat) -> Date {
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9) }
        var dates = [date(info.st_atimespec), date(info.st_mtimespec), date(info.st_birthtimespec)]
        if let item = MDItemCreateWithURL(nil, url as CFURL), let opened = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { dates.append(opened) }
        return dates.max()!
    }
}
