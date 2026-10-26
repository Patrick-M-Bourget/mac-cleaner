import Foundation
import Darwin

/// What kind of data a rule covers; it decides how the data comes back.
public enum RegenClass: String, Codable, Sendable { case cache, build, updaterDownload, leakedCopy, log, installer, model, userFile }
/// Decision 3: regenerable data is deleted; user files go to Trash. Tool actions arrive with #99.
public enum CleanupAction: String, Codable, Sendable { case delete, trash }
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
    public let locations: [String]
    public let owner: RuleOwner?
    /// Names that are never acted on when they are the item, one of its ancestors, or a top-level entry inside it.
    public let protectedNames: [String]
    public init(id: String, category: CatalogCategory, title: String, detail: String, consequence: String, regen: RegenClass, action: CleanupAction, locations: [String], owner: RuleOwner?, protectedNames: [String] = []) {
        self.id = id; self.category = category; self.title = title; self.detail = detail; self.consequence = consequence
        self.regen = regen; self.action = action; self.locations = locations; self.owner = owner; self.protectedNames = protectedNames
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
    ]
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
    public let observedAt: Date
}

public struct Catalog: Sendable {
    public let rules: [CleanupRule]
    public init(rules: [CleanupRule]) { self.rules = rules }
    public func rule(_ id: String) -> CleanupRule? { rules.first { $0.id == id } }

    /// Sizes only the rules' known locations under `home`. Read-only.
    public func discover(home: URL, sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        let base = home.resolvingSymlinksInPath()
        return rules.flatMap { rule in
            rule.locations.compactMap { relative -> Candidate? in
                let url = base.appendingPathComponent(relative)
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return nil }
                let size = sizer.size(url)
                let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                return Candidate(ruleID: rule.id, action: rule.action, url: url, resourceID: "\(info.st_dev):\(info.st_ino)",
                                 isDirectory: info.st_mode & S_IFMT == S_IFDIR, volumeID: volume,
                                 modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                                 logicalBytes: size.logicalBytes, allocatedBytes: size.allocatedBytes, sizeComplete: size.complete, observedAt: Date())
            }
        }
    }
}
