import Foundation
import Darwin

/// What kind of data a rule covers; it decides how the data comes back.
public enum RegenClass: String, Codable, Sendable { case cache, build, updaterDownload, leakedCopy, log, installer, model, userFile }
/// Decision 3: regenerable data is deleted; user files go to Trash. A few rules run the tool's own command (Decision 21).
public enum CleanupAction: String, Codable, Sendable { case delete, trash, tool }

/// A command a `.tool` rule runs, with a time limit. The executable and its arguments are fixed in the rule.
public struct ToolCommand: Sendable, Hashable {
    /// Absolute paths to try in order; the first installed one is used. None installed means the rule doesn't appear.
    public let executables: [String]
    public let arguments: [String]
    public let timeout: TimeInterval
    /// Delete the candidate folder after the command succeeds (Homebrew: `brew cleanup -s` plus its cache folder).
    public let deletesLocationAfter: Bool
    public init(executables: [String], arguments: [String], timeout: TimeInterval, deletesLocationAfter: Bool = false) {
        self.executables = executables; self.arguments = arguments; self.timeout = timeout; self.deletesLocationAfter = deletesLocationAfter
    }
    /// As shown to the user and logged, e.g. `brew cleanup -s`.
    public var commandLine: String {
        ([executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""] + arguments).joined(separator: " ")
    }
    /// The first listed executable that is installed on this Mac.
    @Sendable public static func installed(_ command: ToolCommand) -> URL? {
        command.executables.lazy.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
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
    /// For `*` locations named by version (DeviceSupport): keep this many newest versions in each folder.
    /// Children whose name has no version are then never offered.
    public let keepNewestVersions: Int?
    public init(id: String, category: CatalogCategory, title: String, detail: String, consequence: String, regen: RegenClass, action: CleanupAction, locations: [String], owner: RuleOwner?, protectedNames: [String] = [], tool: ToolCommand? = nil, keepNewestVersions: Int? = nil) {
        self.id = id; self.category = category; self.title = title; self.detail = detail; self.consequence = consequence
        self.regen = regen; self.action = action; self.locations = locations; self.owner = owner; self.protectedNames = protectedNames; self.tool = tool
        self.keepNewestVersions = keepNewestVersions
    }
}

public enum BuiltInCatalog {
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
                    detail: "Packages pnpm downloaded for your projects.",
                    consequence: "Permanently removed. pnpm downloads packages again as needed; the next install may take longer.",
                    regen: .cache, action: .delete, locations: ["Library/pnpm/store", "Library/Caches/pnpm"],
                    owner: RuleOwner(name: "pnpm", executables: ["pnpm", "pnpx"], scripts: ["pnpm", "pnpx", "pnpm.js", "pnpm.cjs", "pnpx.js", "pnpx.cjs"])),
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
    ]

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
    public let observedAt: Date
}

public struct Catalog: Sendable {
    public let rules: [CleanupRule]
    public init(rules: [CleanupRule]) { self.rules = rules }
    public func rule(_ id: String) -> CleanupRule? { rules.first { $0.id == id } }
    /// Load-bearing caches that are never offered, whatever a rule says (spec section 2).
    public static let neverOffered: Set<String> = ["ccache", ".ccache", "sccache"]

    /// Sizes only the rules' known locations under `home`. Read-only.
    /// A `.tool` rule appears only when `locateTool` finds its executable.
    public func discover(home: URL, sizer: KnownLocationSizer = KnownLocationSizer(), locateTool: (ToolCommand) -> URL? = ToolCommand.installed) -> [Candidate] {
        let base = home.resolvingSymlinksInPath()
        return rules.flatMap { rule -> [Candidate] in
            let toolURL = rule.tool.flatMap(locateTool)
            guard rule.action != .tool || toolURL != nil else { return [] }
            return rule.locations.flatMap { Self.expand($0, in: base, keepNewestVersions: rule.keepNewestVersions) }.compactMap { relative -> Candidate? in
                guard Self.neverOffered.isDisjoint(with: relative.split(separator: "/").map(String.init)) else { return nil }
                let url = base.appendingPathComponent(relative)
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return nil }
                // A tool that cleans only part of its folder frees an unknown amount; the folder's total would overstate it.
                let size = rule.tool?.deletesLocationAfter == false ? ItemSize(logicalBytes: 0, allocatedBytes: nil, entries: 0, complete: false) : sizer.size(url)
                let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                return Candidate(ruleID: rule.id, action: rule.action, url: url, resourceID: "\(info.st_dev):\(info.st_ino)",
                                 isDirectory: info.st_mode & S_IFMT == S_IFDIR, toolURL: toolURL, volumeID: volume,
                                 modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                                 logicalBytes: size.logicalBytes, allocatedBytes: size.allocatedBytes, sizeComplete: size.complete, observedAt: Date())
            }
        }
    }

    /// At most this many children of a `*` location are offered.
    static let childLimit = 1_000
    /// A plain location as is; a `parent/*` location as each real folder directly inside `parent`.
    static func expand(_ relative: String, in base: URL, keepNewestVersions keep: Int? = nil) -> [String] {
        guard relative.hasSuffix("/*") else { return [relative] }
        let parent = String(relative.dropLast(2))
        var info = stat()
        guard lstat(base.appendingPathComponent(parent).path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              let names = try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(parent).path) else { return [] }
        let folders = names.filter { name in
            var child = stat()
            return !name.hasPrefix(".") && lstat(base.appendingPathComponent(parent + "/" + name).path, &child) == 0 && child.st_mode & S_IFMT == S_IFDIR
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
