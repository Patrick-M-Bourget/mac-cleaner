import Foundation
import Darwin
import CoreServices

/// What kind of data a rule covers; it decides how the data comes back.
public enum RegenClass: String, Codable, Sendable { case cache, build, updaterDownload, leakedCopy, log, installer, model, userFile }
/// Decision 3: regenerable data is deleted; user files go to Trash. A few rules run the tool's own command (Decision 21).
/// Trash keeps the "moveToTrash" string that Downloads-era journal records use.
public enum CleanupAction: String, Codable, Sendable { case delete; case trash = "moveToTrash"; case tool }

/// A command a `.tool` rule runs, with a time limit. The executable and its arguments are fixed in the rule.
public struct ToolCommand: Sendable, Hashable {
    /// Absolute paths to try in order; the first installed one is used. None installed means the rule doesn't appear.
    public let executables: [String]
    public let arguments: [String]
    public let timeout: TimeInterval
    /// Delete the candidate folder after the command succeeds (Homebrew: `brew cleanup -s` plus its cache folder).
    public let deletesLocationAfter: Bool
    /// An argument replaced by each item's name, as in `ollama rm <model>`; nil for commands that take none.
    public let itemPlaceholder: String?
    public init(executables: [String], arguments: [String], timeout: TimeInterval, deletesLocationAfter: Bool = false, itemPlaceholder: String? = nil) {
        self.executables = executables; self.arguments = arguments; self.timeout = timeout; self.deletesLocationAfter = deletesLocationAfter
        self.itemPlaceholder = itemPlaceholder
    }
    /// The arguments for one item; nil when the command needs an item name and has none.
    public func arguments(for item: String?) -> [String]? {
        guard let itemPlaceholder else { return arguments }
        guard let item else { return nil }
        return arguments.map { $0 == itemPlaceholder ? item : $0 }
    }
    /// As shown to the user and logged, e.g. `brew cleanup -s`.
    public var commandLine: String {
        ([executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""] + arguments).joined(separator: " ")
    }
    /// As shown and logged for one item, e.g. `ollama rm llama3:latest`.
    public func commandLine(for item: String?) -> String {
        guard itemPlaceholder != nil, let arguments = arguments(for: item) else { return commandLine }
        return ([executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""] + arguments).joined(separator: " ")
    }
    /// The first listed executable that is installed on this Mac.
    @Sendable public static func installed(_ command: ToolCommand) -> URL? {
        command.executables.lazy.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
/// Whether none, some or all of a category's items are chosen.
public enum CategorySelectionState: Sendable { case unchecked, mixed, checked }
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
    /// Any later argument, such as a JVM main class (the Gradle daemon runs as `java … org.gradle…`).
    /// All three lists take shell-style patterns (`pip3.*`, `yarn-*.cjs`).
    public let arguments: [String]
    public init(name: String, bundleIDs: [String] = [], executables: [String] = [], scripts: [String] = [], arguments: [String] = []) {
        self.name = name; self.bundleIDs = bundleIDs; self.executables = executables; self.scripts = scripts; self.arguments = arguments
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
    /// A last component of `*` makes each folder directly inside that path a candidate instead
    /// (hidden entries, files and symlinks are skipped; the path itself must be a real folder).
    public let locations: [String]
    public let owner: RuleOwner?
    /// Names that are never acted on when they are the item, one of its ancestors, or a top-level entry inside it.
    public let protectedNames: [String]
    /// The command a `.tool` rule runs; nil for every other action.
    public let tool: ToolCommand?
    /// Extensions never acted on as the item or an ancestor, on top of the global ones.
    public let protectedExtensions: [String]
    /// When set, candidates are the matching files inside each location, not the location.
    public let contents: ContentsMatch?
    /// For `*` locations named by version (DeviceSupport): keep this many newest versions in each folder.
    /// Children whose name has no version are then never offered.
    public let keepNewestVersions: Int?
    /// The name shown for a folder or file the rule found, from its file name; nil shows the file name.
    public let itemName: (@Sendable (String) -> String?)?
    /// When set, candidates are items a tool's own records on disk list, not the location.
    public let items: CatalogItems?
    public init(id: String, category: CatalogCategory, title: String, detail: String, consequence: String, regen: RegenClass, action: CleanupAction, locations: [String], owner: RuleOwner?, protectedNames: [String] = [], tool: ToolCommand? = nil, protectedExtensions: [String] = [], contents: ContentsMatch? = nil, keepNewestVersions: Int? = nil, itemName: (@Sendable (String) -> String?)? = nil, items: CatalogItems? = nil) {
        self.id = id; self.category = category; self.title = title; self.detail = detail; self.consequence = consequence
        self.regen = regen; self.action = action; self.locations = locations; self.owner = owner; self.protectedNames = protectedNames; self.tool = tool
        self.protectedExtensions = protectedExtensions; self.contents = contents; self.keepNewestVersions = keepNewestVersions
        self.itemName = itemName; self.items = items
    }
}

public enum BuiltInCatalog {
    private static let pnpmOwner = RuleOwner(name: "pnpm", executables: ["pnpm", "pnpx"], scripts: ["pnpm", "pnpx", "pnpm.js", "pnpm.cjs", "pnpx.js", "pnpx.cjs"])
    public static let rules: [CleanupRule] = [
        CleanupRule(id: "npm-cache", category: .developer, title: "npm cache",
                    detail: "Packages npm downloaded for your projects.",
                    consequence: "Permanently removed. npm downloads packages again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: [".npm/_cacache"],
                    owner: RuleOwner(name: "npm", executables: ["npm", "npx"], scripts: ["npm", "npx", "npm-cli.js", "npx-cli.js"])),
        CleanupRule(id: "yarn-cache", category: .developer, title: "Yarn cache",
                    detail: "Packages Yarn downloaded for your projects.",
                    consequence: "Permanently removed. Yarn downloads packages again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/Yarn", ".yarn/berry/cache"],
                    owner: RuleOwner(name: "Yarn", executables: ["yarn", "yarnpkg"], scripts: ["yarn", "yarnpkg", "yarn.js", "yarn.cjs", "yarn-*.cjs", "yarn-*.js"])),
        CleanupRule(id: "pnpm-store", category: .developer, title: "pnpm store",
                    detail: "Packages pnpm downloaded that no project uses any more.",
                    consequence: "Runs `pnpm store prune`, which permanently removes only packages no project references. Projects that link into the store keep working.",
                    regen: .cache, action: .tool, locations: ["Library/pnpm/store"],
                    owner: pnpmOwner,
                    tool: ToolCommand(executables: ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm", NSHomeDirectory() + "/Library/pnpm/pnpm"], arguments: ["store", "prune"], timeout: 300)),
        CleanupRule(id: "pnpm-cache", category: .developer, title: "pnpm metadata cache",
                    detail: "Package metadata pnpm downloaded.",
                    consequence: "Permanently removed. pnpm downloads metadata again as needed.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/pnpm"],
                    owner: pnpmOwner),
        CleanupRule(id: "uv-cache", category: .developer, title: "uv cache",
                    detail: "Python packages uv downloaded and built.",
                    consequence: "Permanently removed. uv downloads or builds packages again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: [".cache/uv"],
                    owner: RuleOwner(name: "uv", executables: ["uv", "uvx"])),
        CleanupRule(id: "pip-cache", category: .developer, title: "pip cache",
                    detail: "Python packages pip downloaded and built.",
                    consequence: "Permanently removed. pip downloads packages again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/pip"],
                    owner: RuleOwner(name: "pip", executables: ["pip", "pip3", "pip3.*"], scripts: ["pip", "pip3", "pip3.*"])),
        CleanupRule(id: "cargo-cache", category: .developer, title: "Cargo cache",
                    detail: "Rust crates and git dependencies Cargo downloaded. Installed tools are not included.",
                    consequence: "Permanently removed. Cargo downloads crates again as needed; the next build may take longer.",
                    regen: .cache, action: .delete, locations: [".cargo/registry", ".cargo/git"],
                    owner: RuleOwner(name: "Cargo", executables: ["cargo", "cargo-*"])),
        CleanupRule(id: "gradle-cache", category: .developer, title: "Gradle cache",
                    detail: "Dependencies and build caches Gradle downloaded.",
                    consequence: "Permanently removed. Gradle downloads dependencies again as needed; the next build may take longer.",
                    regen: .cache, action: .delete, locations: [".gradle/caches"],
                    owner: RuleOwner(name: "Gradle", executables: ["gradle", "gradlew"], scripts: ["gradle", "gradlew"], arguments: ["org.gradle.*"])),
        CleanupRule(id: "cocoapods-cache", category: .developer, title: "CocoaPods cache",
                    detail: "Pods CocoaPods downloaded for your projects.",
                    consequence: "Permanently removed. CocoaPods downloads pods again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/CocoaPods"],
                    owner: RuleOwner(name: "CocoaPods", executables: ["pod"], scripts: ["pod"])),
        CleanupRule(id: "homebrew", category: .developer, title: "Homebrew cache",
                    detail: "Downloads Homebrew kept, plus old versions `brew cleanup -s` removes.",
                    consequence: "Runs `brew cleanup -s`, then permanently removes the cache folder. Homebrew downloads again when you install or upgrade.",
                    regen: .cache, action: .tool, locations: ["Library/Caches/Homebrew"],
                    owner: RuleOwner(name: "Homebrew", executables: ["brew"], scripts: ["brew", "brew.sh", "brew.rb"]),
                    tool: ToolCommand(executables: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], arguments: ["cleanup", "-s"], timeout: 300, deletesLocationAfter: true)),
        CleanupRule(id: "xcode-derived-data", category: .developer, title: "Xcode DerivedData",
                    detail: "Build files, indexes and products Xcode keeps for each project.",
                    consequence: "Permanently removed. Xcode rebuilds them; the next build and indexing take longer. Archives and your projects are not touched.",
                    regen: .build, action: .delete, locations: ["Library/Developer/Xcode/DerivedData/*"],
                    owner: xcode),
        CleanupRule(id: "xcode-device-support", category: .developer, title: "Old device support files",
                    detail: "Debug symbols Xcode copied from each OS version of your devices. The 2 newest versions per platform are kept.",
                    consequence: "Permanently removed. Xcode copies them again if you connect a device running one of those versions.",
                    regen: .build, action: .delete,
                    locations: ["iOS", "watchOS", "tvOS", "visionOS", "macOS"].map { "Library/Developer/Xcode/\($0) DeviceSupport/*" },
                    owner: xcode, keepNewestVersions: 2),
        CleanupRule(id: "xcode-simulators", category: .developer, title: "Unavailable simulators",
                    detail: "Simulator devices whose OS version is no longer installed, so they can’t run.",
                    consequence: "Runs `simctl delete unavailable`. Only devices that can’t run are removed, with their apps and data; available simulators are not touched.",
                    regen: .build, action: .tool, locations: ["Library/Developer/CoreSimulator/Devices"], owner: nil,
                    // CoreSimulator's own simctl first: `xcrun` fails while xcode-select points at the Command Line Tools,
                    // and Xcode's wrapper may run first-launch setup, which can ask for an admin password (Decision 4).
                    tool: ToolCommand(executables: ["/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl",
                                                    "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"],
                                      arguments: ["delete", "unavailable"], timeout: 300)),
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
        huggingFaceModels,
        ollamaModels,
    ]
    /// Kept from the Downloads-era policy: libraries and databases are never moved, even inside Downloads.
    static let downloadsProtectedExtensions = ["dsym", "library", "db", "sqlite", "sqlite3"]
    /// Xcode and the build processes that write into DerivedData, including command-line builds.
    static let xcode = RuleOwner(name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"],
                                 executables: ["Xcode", "xcodebuild", "SWBBuildService*", "XCBBuildService*", "swift-driver", "swift-frontend",
                                               "swiftc", "clang", "clang++", "ld", "dsymutil"])
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
    /// The installed executable a `.tool` candidate runs, found at discovery.
    public let toolURL: URL?
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
    /// What the item is called, e.g. a model's name; nil means its file name.
    public internal(set) var itemName: String? = nil
    /// The size is an estimate rather than a measurement (an Ollama model's own, unshared blobs).
    public internal(set) var sizeIsEstimate = false
    /// The file's own size when `logicalBytes` sizes something else (an Ollama manifest stands for its model).
    public internal(set) var fileBytes: Int64? = nil
}

public struct Catalog: Sendable {
    public let rules: [CleanupRule]
    public init(rules: [CleanupRule]) { self.rules = rules }
    public func rule(_ id: String) -> CleanupRule? { rules.first { $0.id == id } }
    /// Load-bearing caches that are never offered, whatever a rule says (spec section 2).
    public static let neverOffered: Set<String> = ["ccache", ".ccache", "sccache"]

    /// Sizes only the rules' known locations under `home`. Read-only. An item two rules match is offered once, by the first.
    /// A `.tool` rule appears only when `locateTool` finds its executable.
    public func discover(home: URL, sizer: KnownLocationSizer = KnownLocationSizer(), now: Date = Date(), locateTool: (ToolCommand) -> URL? = ToolCommand.installed) -> [Candidate] {
        let base = home.resolvingSymlinksInPath()
        var seen = Set<String>()
        return rules.flatMap { rule -> [Candidate] in
            let toolURL = rule.tool.flatMap(locateTool)
            guard rule.action != .tool || toolURL != nil else { return [] }
            return rule.locations.flatMap { Self.expand($0, in: base, keepNewestVersions: rule.keepNewestVersions) }.flatMap { relative -> [Candidate] in
                guard Self.neverOffered.isDisjoint(with: relative.split(separator: "/").map(String.init)) else { return [] }
                let url = base.appendingPathComponent(relative)
                if let contents = rule.contents { return files(in: url, matching: contents, rule: rule, now: now) }
                if rule.items == .ollamaModels { return ollamaModels(in: url, rule: rule, toolURL: toolURL) }
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return [] }
                // A tool that cleans only part of its folder frees an unknown amount; the folder's total would overstate it.
                let size = rule.tool?.deletesLocationAfter == false ? ItemSize(logicalBytes: 0, allocatedBytes: nil, entries: 0, complete: false) : sizer.size(url)
                // Models and disk images show when they were last used, so the user can judge (SPEC section 3).
                let lastUsed = rule.regen == .model ? Self.lastUsedInside(url, info) : nil
                var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: lastUsed, toolURL: toolURL)
                found.itemName = rule.itemName?(url.lastPathComponent)
                return [found]
            }
        }.filter { seen.insert($0.resourceID).inserted }
    }

    func candidate(_ rule: CleanupRule, _ url: URL, _ info: stat, logical: Int64, allocated: Int64?, complete: Bool, lastUsed: Date?, toolURL: URL? = nil) -> Candidate {
        let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return Candidate(ruleID: rule.id, action: rule.action, url: url, resourceID: "\(info.st_dev):\(info.st_ino)",
                         isDirectory: info.st_mode & S_IFMT == S_IFDIR, toolURL: toolURL, volumeID: volume,
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

    /// At most this many children of a `*` location are offered.
    static let childLimit = 1_000
    /// A plain location as is; a `parent/*` location as each real folder directly inside `parent`.
    /// The last component may be a shell pattern such as `models--*`.
    static func expand(_ relative: String, in base: URL, keepNewestVersions keep: Int? = nil) -> [String] {
        let pattern = (relative as NSString).lastPathComponent
        guard pattern.contains("*") else { return [relative] }
        let parent = (relative as NSString).deletingLastPathComponent
        var info = stat()
        guard lstat(base.appendingPathComponent(parent).path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              let names = try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(parent).path) else { return [] }
        let folders = names.filter { name in
            var child = stat()
            return !name.hasPrefix(".") && fnmatch(pattern, name, 0) == 0 && lstat(base.appendingPathComponent(parent + "/" + name).path, &child) == 0 && child.st_mode & S_IFMT == S_IFDIR
        }
        var offered = folders
        if let keep {
            let versions = Dictionary(uniqueKeysWithValues: folders.compactMap { name in version(in: name).map { (name, $0) } })
            let kept = Set(versions.values).sorted { $0.lexicographicallyPrecedes($1) }.suffix(keep)
            offered = folders.filter { versions[$0].map { !kept.contains($0) } ?? false }
        }
        return offered.sorted().prefix(childLimit).map { parent + "/" + $0 }
    }

    /// The version in a DeviceSupport folder name: "17.0 (21A329)" or "iPhone15,2 17.0.1 (21A340)" give [17, 0] and [17, 0, 1].
    static func version(in name: String) -> [Int]? {
        for word in name.split(separator: " ") where word.first?.isNumber == true {
            let parts = word.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            if !parts.contains(nil) { return parts.compactMap { $0 } }
        }
        return nil
    }
}
