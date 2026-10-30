import Foundation
import Darwin
import CoreServices

/// What kind of data a rule covers; it decides how the data comes back.
public enum RegenClass: String, Codable, Sendable { case cache, build, updaterDownload, leakedCopy, log, installer, model, userFile, cloudCopy }
/// Decision 3: regenerable data is deleted; user files go to Trash. A few rules run the tool's own command (Decision 21).
/// Trash keeps the "moveToTrash" string that Downloads-era journal records use.
/// Evict removes only the local copy of an iCloud file (Decision 13); the original stays in iCloud.
/// Guidance never acts: the rule is sized and points to where the user manages it (SPEC section 3).
/// Raw values are stored in the journal as each record's `action` (#448): a renamed case keeps its string.
public enum CleanupAction: String, Codable, Sendable { case delete = "delete"; case trash = "moveToTrash"; case tool = "tool"; case evict = "evict"; case guidance = "guidance" }

/// A command a `.tool` rule runs, with a time limit. The executable and its arguments are fixed in the rule.
public struct ToolCommand: Sendable, Hashable {
    /// Absolute paths to try in order; the first installed one is used. None installed means the rule doesn't appear.
    public let executables: [String]
    public let arguments: [String]
    /// Settable inside the module only, so tests copy a rule with a shorter limit rather than rebuild it.
    public internal(set) var timeout: TimeInterval
    /// Delete the candidate folder after the command succeeds (Homebrew: `brew cleanup -s` plus its cache folder).
    public let deletesLocationAfter: Bool
    /// An argument replaced by each item's name, as in `ollama rm <model>`; nil for commands that take none.
    public let itemPlaceholder: String?
    /// The command hands its work to a daemon outside its process group (Docker, CoreSimulator, the Ollama server), so stopping it
    /// at a cancel or its time limit doesn't stop the work, which may still be finishing.
    public let daemonBacked: Bool
    /// How this tool is asked where it keeps its data, as in `uv cache dir` (Decision 44); nil when it isn't.
    public let locationQuery: LocationQuery?
    public init(executables: [String], arguments: [String], timeout: TimeInterval, deletesLocationAfter: Bool = false, itemPlaceholder: String? = nil, daemonBacked: Bool = false,
                locationQuery: LocationQuery? = nil) {
        self.executables = executables; self.arguments = arguments; self.timeout = timeout; self.deletesLocationAfter = deletesLocationAfter
        self.itemPlaceholder = itemPlaceholder; self.daemonBacked = daemonBacked
        self.locationQuery = locationQuery
    }
    /// The arguments for one item; nil when the command needs an item name and has none.
    public func arguments(for item: String?) -> [String]? {
        guard let itemPlaceholder else { return arguments }
        guard let item else { return nil }
        return arguments.map { $0 == itemPlaceholder ? item : $0 }
    }
    /// As shown to the user and logged, e.g. `brew cleanup -s`.
    public var commandLine: String { commandLine(for: nil) }
    /// As shown and logged for one item, e.g. `ollama rm llama3:latest`; the plain command when it takes no item or has none.
    public func commandLine(for item: String?) -> String {
        ([executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""] + (self.arguments(for: item) ?? arguments)).joined(separator: " ")
    }
    /// The first listed executable that is installed on this Mac.
    @Sendable public static func installed(_ command: ToolCommand) -> URL? {
        command.executables.lazy.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
/// Whether none, some or all of a category's items are chosen.
public enum CategorySelectionState: Sendable { case unchecked, mixed, checked }
public enum CatalogCategory: String, Codable, Sendable { case developer, browser, downloads, system, models, updaters, logs, icloud, files, managed, leftovers, apps }

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
    /// Folders, such as an app bundle, any process run from inside of which belongs to the owner.
    public let paths: [String]
    /// Lowercased bundle ID prefixes (`com.ableton.`): any running app whose bundle ID starts with one belongs to the owner,
    /// as a removed app's maker does (#173).
    public let bundleIDPrefixes: [String]
    public init(name: String, bundleIDs: [String] = [], executables: [String] = [], scripts: [String] = [], arguments: [String] = [], paths: [String] = [],
                bundleIDPrefixes: [String] = []) {
        self.name = name; self.bundleIDs = bundleIDs; self.executables = executables; self.scripts = scripts; self.arguments = arguments; self.paths = paths
        self.bundleIDPrefixes = bundleIDPrefixes
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
    /// Only an unpacked copy: a file with a smaller compressed source beside it (`rootfs.img` next to `rootfs.img.zst`).
    public let besideCompressedSource: Bool
    public init(extensions: Set<String> = [], minimumBytes: Int64? = nil, unusedDays: Int? = nil, besideCompressedSource: Bool = false) {
        self.extensions = extensions; self.minimumBytes = minimumBytes; self.unusedDays = unusedDays; self.besideCompressedSource = besideCompressedSource
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
    public internal(set) var tool: ToolCommand?
    /// Extensions never acted on as the item or an ancestor, on top of the global ones.
    public let protectedExtensions: [String]
    /// Settings that move the owner's data elsewhere. When one is set the rule offers nothing.
    public let layoutOverrides: [LayoutOverride]
    /// When set, candidates are the matching files inside each location, not the location.
    public let contents: ContentsMatch?
    /// For `*` locations named by version (DeviceSupport): keep this many newest versions in each folder.
    /// Children whose name has no version are then never offered.
    public let keepNewestVersions: Int?
    /// For rules whose owner differs per item (an app's own cache folder): the item's owner, or nil when it
    /// can't be determined. Such an item is never offered, and is refused if its owner can't be found later.
    public let itemOwner: (@Sendable (URL) -> RuleOwner?)?
    /// A broad rule (every app's cache) offers nothing another rule's location names, holds or sits inside,
    /// so no folder is offered twice and no other rule's data goes with a parent folder.
    public let yieldsToOtherRules: Bool
    /// How many levels inside a folder candidate protected names are looked for (1: its top-level entries).
    /// Deeper for folders that can hold live work, such as an agent's git checkout under Caches.
    public let protectedDepth: Int
    /// What `locations` are relative to; the home folder unless set.
    public let base: LocationBase
    /// When set, each folder inside a location is a leaked copy, and the in-use and newest copies are kept.
    public let copies: LeakedCopies?
    /// The name shown for a folder or file the rule found, from its file name; nil shows the file name.
    public let itemName: (@Sendable (String) -> String?)?
    /// When set, candidates are items a tool's own records on disk list, not the location.
    public let items: CatalogItems?
    /// Global protected extensions this rule may act inside, e.g. an app's own VM `.bundle`. Never `sparsebundle` lightly.
    public let unprotectedExtensions: Set<String>
    /// How a `.guidance` rule is sized and where it is managed; nil for every other action.
    public let guidance: Guidance?
    /// Its locations are ones macOS protects (Safari's data): without Full Disk Access they're shown as not accessible.
    public let requiresFullDiskAccess: Bool
    /// macOS folder names (`com.apple.…`) this rule may act inside, such as Safari's own caches folder. Every other one stays protected.
    public let unprotectedNames: Set<String>
    /// Its items are single files from folders the user picked (`UserFiles`), never from its own locations. They're never
    /// taken from the home folder's protected folders, and a git checkout above the picked folder counts too.
    public let fromPickedFolders: Bool
    /// When set, each item inside a location is offered only when old and unused by any process (`TemporaryFiles`).
    public let unused: UnusedItems?
    /// The user picks each item on its own (#144): set for rules whose items aren't all data that rebuilds itself
    /// (a JetBrains folder holds local history), on top of the kinds `choosesItems` already counts.
    public let itemByItem: Bool
    /// The app or plug-in product its items are tied to (#289): files from a deleted app, or an uninstall; nil for every other rule.
    public let family: AppRuleFamily?
    /// A tool asked where a rule's folder is when the rule doesn't run a tool of its own (`npm config get cache`, #170).
    /// Only its query is ever run. A `.tool` rule asks its own `tool` instead.
    public let locationTool: LocationTool?
    /// Folders (by lowercased name) that hold an app's offline content, which keeps the folder out (`AppCaches`, #171).
    public let offlineContent: [String: OfflineContent]
    /// The tool asked where this rule's folder is, if any, decided here only: its own `tool` when that has a `locationQuery`
    /// (`isOwnTool`, so discovery uses the executable it already found), else `locationTool`.
    public var locationAsker: (tool: LocationTool, isOwnTool: Bool)? {
        if let tool, let query = tool.locationQuery { return (LocationTool(executables: tool.executables, query: query), true) }
        return locationTool.map { ($0, false) }
    }
    public init(id: String, category: CatalogCategory, title: String, detail: String, consequence: String, regen: RegenClass, action: CleanupAction, locations: [String], owner: RuleOwner?, protectedNames: [String] = [], tool: ToolCommand? = nil, protectedExtensions: [String] = [], contents: ContentsMatch? = nil, keepNewestVersions: Int? = nil, layoutOverrides: [LayoutOverride] = [], base: LocationBase = .home, copies: LeakedCopies? = nil, itemName: (@Sendable (String) -> String?)? = nil, items: CatalogItems? = nil, unprotectedExtensions: Set<String> = [],
                itemOwner: (@Sendable (URL) -> RuleOwner?)? = nil, yieldsToOtherRules: Bool = false, protectedDepth: Int = 1, requiresFullDiskAccess: Bool = false, guidance: Guidance? = nil,
                unprotectedNames: Set<String> = [], fromPickedFolders: Bool = false, unused: UnusedItems? = nil, itemByItem: Bool = false, locationTool: LocationTool? = nil,
                offlineContent: [String: OfflineContent] = [:], family: AppRuleFamily? = nil) {
        self.id = id; self.category = category; self.title = title; self.detail = detail; self.consequence = consequence
        self.regen = regen; self.action = action; self.locations = locations; self.owner = owner; self.protectedNames = protectedNames; self.tool = tool
        self.protectedExtensions = protectedExtensions; self.contents = contents; self.keepNewestVersions = keepNewestVersions; self.layoutOverrides = layoutOverrides
        self.base = base; self.copies = copies
        self.itemName = itemName; self.items = items; self.unprotectedExtensions = unprotectedExtensions
        self.itemOwner = itemOwner; self.yieldsToOtherRules = yieldsToOtherRules; self.protectedDepth = protectedDepth
        self.requiresFullDiskAccess = requiresFullDiskAccess; self.unprotectedNames = unprotectedNames
        self.guidance = guidance; self.fromPickedFolders = fromPickedFolders
        self.unused = unused; self.itemByItem = itemByItem; self.locationTool = locationTool; self.offlineContent = offlineContent
        self.family = family
    }
}

extension CleanupRule {
    /// Rules whose items the user chooses one by one: single Downloads files, each model or disk image, each iCloud copy,
    /// and rules marked `itemByItem`. The one definition: the Cleanup plan lists their items, and Smart clean never takes them.
    public var choosesItems: Bool { contents != nil || regen == .model || action == .evict || fromPickedFolders || items?.choosesEachItem == true || itemByItem }
}

public enum BuiltInCatalog {
    private static let pnpmOwner = RuleOwner(name: "pnpm", executables: ["pnpm", "pnpx"], scripts: ["pnpm", "pnpx", "pnpm.js", "pnpm.cjs", "pnpx.js", "pnpx.cjs"])
    /// The catalog as the app uses it, with installed apps found through LaunchServices.
    public static let rules: [CleanupRule] = rules(apps: SystemAppLookup())
    /// The catalog with installed apps found by `apps`. Tests pass a fake, so they never depend on this Mac's apps.
    public static func rules(apps: any AppLookup) -> [CleanupRule] { fixedRules + BrowserCaches.rules + AppDataCaches.rules(apps: apps) + AppCaches.rules(apps: apps) + dockerRules + developerDeviceRules + guidanceRules
        + TemporaryFiles.rules(apps: apps) + AITools.rules
        + AppRuleFamily.rules }
    private static let fixedRules: [CleanupRule] = [
        CleanupRule(id: "npm-cache", category: .developer, title: "npm cache",
                    detail: "Packages npm downloaded for your projects.",
                    consequence: "npm downloads packages again as needed.",
                    regen: .cache, action: .delete, locations: [".npm/_cacache"],
                    owner: RuleOwner(name: "npm", executables: ["npm", "npx"], scripts: ["npm", "npx", "npm-cli.js", "npx-cli.js"]),
                    locationTool: LocationTool(executables: ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"],
                                               query: LocationQuery(["config", "get", "cache"], whenUnanswered: .defaultLocations, reportedSubfolder: "_cacache",
                                                                    configuredIn: .npmrc))),
        CleanupRule(id: "yarn-cache", category: .developer, title: "Yarn cache",
                    detail: "Packages Yarn downloaded for your projects.",
                    consequence: "Yarn downloads packages again as needed.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/Yarn", ".yarn/berry/cache"],
                    owner: RuleOwner(name: "Yarn", executables: ["yarn", "yarnpkg"], scripts: ["yarn", "yarnpkg", "yarn.js", "yarn.cjs", "yarn-*.cjs", "yarn-*.js"])),
        CleanupRule(id: "pnpm-store", category: .developer, title: "pnpm store",
                    detail: "Packages pnpm downloaded that no project uses any more.",
                    consequence: "Only packages no project uses go, so projects that link into the store keep working.",
                    regen: .cache, action: .tool, locations: ["Library/pnpm/store"],
                    owner: pnpmOwner,
                    tool: ToolCommand(executables: ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm", NSHomeDirectory() + "/Library/pnpm/pnpm"], arguments: ["store", "prune"], timeout: 300,
                                      locationQuery: LocationQuery(["store", "path"], whenUnanswered: .defaultLocations))),
        CleanupRule(id: "pnpm-cache", category: .developer, title: "pnpm metadata cache",
                    detail: "Package metadata pnpm downloaded.",
                    consequence: "pnpm downloads metadata again as needed.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/pnpm"],
                    owner: pnpmOwner),
        // Decision 44: uv's docs say to change its cache only through uv, so uv names the folder and prunes it.
        CleanupRule(id: "uv-cache", category: .developer, title: "uv cache",
                    detail: "Python packages uv downloaded and built that it no longer needs.",
                    consequence: "Only unused cache entries go, and uv downloads or builds packages again as needed.",
                    regen: .cache, action: .tool, locations: [".cache/uv"],
                    owner: RuleOwner(name: "uv", executables: ["uv", "uvx"]),
                    tool: ToolCommand(executables: [NSHomeDirectory() + "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.cargo/bin/uv"],
                                      arguments: ["cache", "prune"], timeout: 300, locationQuery: LocationQuery(["cache", "dir"]))),
        CleanupRule(id: "pip-cache", category: .developer, title: "pip cache",
                    detail: "Python packages pip downloaded and built.",
                    consequence: "pip downloads packages again as needed.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/pip"],
                    owner: RuleOwner(name: "pip", executables: ["pip", "pip3", "pip3.*"], scripts: ["pip", "pip3", "pip3.*"]),
                    // pip's cache holds `http-v2` (pip 23.3 on) or `http` (earlier), per https://pip.pypa.io/en/stable/topics/caching/,
                    // and `wheels`, per pip's `src/pip/_internal/cache.py` (`os.path.join(self.cache_dir, "wheels", ...)`).
                    locationTool: LocationTool(executables: ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Developer/CommandLineTools/usr/bin/python3"],
                                               query: LocationQuery(["-m", "pip", "cache", "dir"], whenUnanswered: .defaultLocations, cacheMarkers: ["http-v2", "http", "wheels"],
                                                                    configuredIn: .pipConf))),
        CleanupRule(id: "cargo-cache", category: .developer, title: "Cargo cache",
                    detail: "Rust crates and git dependencies Cargo downloaded. Installed tools are not included.",
                    consequence: "Cargo downloads crates again as needed.",
                    regen: .cache, action: .delete, locations: [".cargo/registry", ".cargo/git"],
                    owner: RuleOwner(name: "Cargo", executables: ["cargo", "cargo-*"])),
        CleanupRule(id: "gradle-cache", category: .developer, title: "Gradle cache",
                    detail: "Dependencies and build caches Gradle downloaded.",
                    consequence: "Gradle downloads dependencies again as needed.",
                    regen: .cache, action: .delete, locations: [".gradle/caches"],
                    owner: RuleOwner(name: "Gradle", executables: ["gradle", "gradlew"], scripts: ["gradle", "gradlew"], arguments: ["org.gradle.*"])),
        CleanupRule(id: "cocoapods-cache", category: .developer, title: "CocoaPods cache",
                    detail: "Pods CocoaPods downloaded for your projects.",
                    consequence: "CocoaPods downloads pods again as needed.",
                    regen: .cache, action: .delete, locations: ["Library/Caches/CocoaPods"],
                    owner: RuleOwner(name: "CocoaPods", executables: ["pod"], scripts: ["pod"])),
        CleanupRule(id: "homebrew", category: .developer, title: "Homebrew cache",
                    detail: "Downloads Homebrew kept, plus old versions `brew cleanup -s` removes.",
                    consequence: "Homebrew downloads again when you install or upgrade.",
                    regen: .cache, action: .tool, locations: ["Library/Caches/Homebrew"],
                    owner: RuleOwner(name: "Homebrew", executables: ["brew"], scripts: ["brew", "brew.sh", "brew.rb"]),
                    // `brew --cache` holds `downloads` (Homebrew's `download_strategy/abstract_file_download_strategy.rb`: `HOMEBREW_CACHE/"downloads/..."`)
                    // and `api` (`api.rb`: `HOMEBREW_CACHE_API = HOMEBREW_CACHE/"api"`), from https://github.com/Homebrew/brew.
                    tool: ToolCommand(executables: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], arguments: ["cleanup", "-s"], timeout: 300, deletesLocationAfter: true,
                                      locationQuery: LocationQuery(["--cache"], whenUnanswered: .defaultLocations, cacheMarkers: ["downloads", "api"]))),
        CleanupRule(id: "xcode-derived-data", category: .developer, title: "Xcode DerivedData",
                    detail: "Build files, indexes and products Xcode keeps for each project.",
                    consequence: "Xcode rebuilds them, and archives and your projects are kept.",
                    regen: .build, action: .delete, locations: ["Library/Developer/Xcode/DerivedData/*"],
                    owner: xcode),
        CleanupRule(id: "xcode-device-support", category: .developer, title: "Old device support files",
                    detail: "Debug symbols Xcode copied from each OS version of your devices. The 2 newest versions per platform are kept.",
                    consequence: "Xcode copies them again if you connect a device running one of those versions.",
                    regen: .build, action: .delete,
                    locations: ["iOS", "watchOS", "tvOS", "visionOS", "macOS"].map { "Library/Developer/Xcode/\($0) DeviceSupport/*" },
                    owner: xcode, keepNewestVersions: 2),
        CleanupRule(id: "xcode-simulators", category: .developer, title: "Unavailable simulators",
                    detail: "Simulator devices whose OS version is no longer installed, so they can’t run.",
                    consequence: "Only simulators that can’t run go, with their apps and data.",
                    regen: .build, action: .tool, locations: ["Library/Developer/CoreSimulator/Devices"], owner: nil,
                    tool: ToolCommand(executables: simctlExecutables, arguments: ["delete", "unavailable"], timeout: 300, daemonBacked: true),
                    items: .unavailableSimulators),
        // RESET Decision 83 (#342; amends 18): Downloads is one place to look, every file at any size or age. Smart clean takes
        // the ones untouched for 7 days (`RecommendedPlan`).
        CleanupRule(id: CleanupRule.downloadsID, category: .downloads, title: "Downloads",
                    detail: "Every file in your Downloads folder, at any size or age.",
                    consequence: "",
                    regen: .userFile, action: .trash, locations: ["Downloads"], owner: nil,
                    protectedExtensions: downloadsProtectedExtensions, contents: ContentsMatch()),
        // #135: restore images Finder (formerly iTunes) downloaded to update or restore a device.
        CleanupRule(id: "ios-software-updates", category: .updaters, title: "Old iOS update files",
                    detail: "iPhone, iPad and iPod software updates downloaded to update or restore a device.",
                    consequence: "Finder downloads the update again when a device needs it.",
                    regen: .installer, action: .trash,
                    locations: ["iPhone", "iPad", "iPod"].map { "Library/iTunes/\($0) Software Updates" }, owner: nil,
                    contents: ContentsMatch(extensions: ["ipsw"])),
        // Field note section 3: Chrome copies itself for code-sign checks and never removes the copies.
        CleanupRule(id: "chrome-code-sign-clones", category: .browser, title: "Chrome code-sign copies",
                    detail: "Copies of Google Chrome it made to check its signature and never removed. The copy Chrome is using and the newest copy are kept.",
                    consequence: "Chrome doesn’t need them again, and they share disk space with it, so less may come back than shown.",
                    regen: .leakedCopy, action: .delete, locations: ["X/com.google.Chrome.code_sign_clone"], owner: nil,
                    base: .userFolder, copies: LeakedCopies(owner: RuleOwner(name: "Google Chrome", bundleIDs: ["com.google.Chrome"], executables: ["Google Chrome", "Google Chrome Helper*"]))),
        huggingFaceModels,
        lmStudioModels,
        ollamaModels,
        appVMImages,
        iCloudLocalCopies,
        // Its items come only from folders the user picked (`UserFiles.candidates`); it has no locations of its own.
        UserFiles.rule,
        // Build folders in projects inside picked folders (`ProjectBuilds.candidates`); no locations of its own either.
        ProjectBuilds.rule,
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
    public var id: String { ruleID + "|" + url.path + "|" + resourceID + "|" + action.rawValue + (toolItem.map { "|" + $0 } ?? "") }
    /// Set once by discovery; an uninstall moves a leftover to its own rule (`uninstalled(with:ruleID:)`).
    public internal(set) var ruleID: String
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
    /// What a `*` in the rule's location matched, such as a browser profile folder; nil for a fixed location.
    public let profile: String?
    /// The app an item belongs to, for rules whose owner differs per item (an app's own cache folder).
    public internal(set) var appName: String? = nil
    /// What the item is called, e.g. a model's name; nil means its file name.
    public internal(set) var itemName: String? = nil
    /// What a per-item tool command takes for this item when it isn't its name, such as a simulator's UDID.
    public internal(set) var toolItem: String? = nil
    /// The argument a per-item tool command runs with: `toolItem`, else the item's name.
    public var toolArgument: String? { toolItem ?? itemName }
    /// The size is an estimate rather than a measurement (an Ollama model's own, unshared blobs).
    public internal(set) var sizeIsEstimate = false
    /// The file's own size when `logicalBytes` sizes something else (an Ollama manifest stands for its model).
    public internal(set) var fileBytes: Int64? = nil
    /// What the scan sized: allocated bytes where known, else logical bytes.
    public var estimatedBytes: Int64 { allocatedBytes ?? logicalBytes }
    /// Whether cleaning it frees space: anything but a move to the Trash, whose space stays used until the Trash is emptied
    /// (SPEC section 6). Only these count in a total of space released (#350).
    public var releasesSpace: Bool { action != .trash }
    /// Where a tool-asked rule's folder came from, shown on the item (#206): "Location from npm", or "Default location"
    /// when the tool wasn't asked successfully. Nil for every other rule.
    public internal(set) var folderSource: String? = nil
    /// The base folder the item was found under (home or the user's folder); the check refuses an item without one.
    public internal(set) var scopeRoot: URL? = nil
    /// What ties a leftover of a removed app to that app (#173); nil for every other item.
    public internal(set) var leftover: LeftoverTie? = nil
    /// The installed app this item is uninstalled with (#177); nil for every other item.
    public internal(set) var uninstall: AppUninstall.Target? = nil
    /// The rows of the products a shared plug-in item is uninstalled with, ticked one by one (#176); empty for every other item.
    public internal(set) var sharedBy: [String] = []
    /// The receipts that listed a plug-in support item, or anything in it, at the scan: it is moved only while no other receipt
    /// lists it and they still list all of it, read again before acting (#288, #291).
    public internal(set) var installedBy: Set<String>? = nil
    /// Why the scan found it held (#374): an app or process using it, or a project being worked on. It stays on the plan,
    /// unticked unless the user ticks it, and is checked again at Clean up; nil when nothing held it.
    public internal(set) var hold: CandidateHold? = nil
}

/// What held an item at the scan (#374), so the plan shows it unticked with why, never as free space.
public struct CandidateHold: Sendable, Hashable {
    /// The reason a run would skip it now.
    public let refusal: CheckRefusal
    /// The known app holding it, which quitting frees; nil when the holder isn't a known app (any process, a project).
    public let app: RuleOwner?
    public init(_ refusal: CheckRefusal, app: RuleOwner? = nil) { self.refusal = refusal; self.app = app }
    /// The row's line: "In use by X · Quit X to clean it", or the refusal's own reason without a known app.
    public var line: String { app.map { "In use by \($0.name) · Quit \($0.name) to clean it" } ?? refusal.reason }
}

public struct Catalog: Sendable {
    public let rules: [CleanupRule]
    public init(rules: [CleanupRule]) { self.rules = rules }
    public func rule(_ id: String) -> CleanupRule? { rules.first { $0.id == id } }
    /// Who must be closed before the candidate is touched: the rule's owner, or the item's own when it has one.
    public func owner(for candidate: Candidate) -> RuleOwner? {
        guard let rule = rule(candidate.ruleID), case .mustBeClosed(let owner) = Self.ownership(of: candidate, under: rule) else { return nil }
        return owner
    }

    /// Whose processes guard an item, and how.
    enum Ownership {
        /// Must be closed before the item is touched.
        case mustBeClosed(RuleOwner)
        /// May keep running but must not be using the item: the app a leaked copy is of.
        case mustNotUse(RuleOwner)
        /// The item's own owner can't be determined. Such an item is never offered, and refused.
        case unknown
        /// Nothing guards it.
        case none
    }
    /// The one place an item's owner is resolved, from the rule's `owner`, `itemOwner` and `copies.owner`.
    /// A leftover from an earlier delete has no owner to close, since no app uses a folder renamed aside,
    /// but a leaked copy's app may still have one open.
    static func ownership(of candidate: Candidate, under rule: CleanupRule) -> Ownership {
        // A removed app's leftovers wait for every app of its maker to close (#173), an app and its files for the app (#177,
        // Decision 29); one without its tie or app is refused.
        if let family = rule.family { return family.owner(of: candidate).map { .mustBeClosed($0) } ?? .unknown }
        return ownership(of: candidate.url, under: rule)
    }
    static func ownership(of url: URL, under rule: CleanupRule) -> Ownership {
        if let copies = rule.copies { return .mustNotUse(copies.owner) }
        if rule.unused != nil, rule.itemOwner == nil { return .mustNotUse(.anyApp) }
        if Catalog.isLeftover(url.lastPathComponent, of: rule.id) { return .none }
        if let itemOwner = rule.itemOwner { return itemOwner(url).map(Ownership.mustBeClosed) ?? .unknown }
        return rule.owner.map(Ownership.mustBeClosed) ?? .none
    }
    /// Load-bearing caches that are never offered, whatever a rule says (spec section 2).
    public static let neverOffered: Set<String> = ["ccache", ".ccache", "sccache"]

    /// Sizes only the rules' known locations under `home`. Read-only. An item two rules match is offered once, by the first.
    /// A `.tool` rule appears only when `locateTool` finds its executable. Rules based in the user's
    /// `/private/var/folders` entry appear only when `userFolder` is given (`Catalog.currentUserFolder()` in the app).
    /// Absolute paths in a rule's layout overrides are read under `systemRoot`.
    public func discover(home: URL, userFolder: URL? = nil, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = SystemInUseChecker(), sizer: KnownLocationSizer = KnownLocationSizer(), now: Date = Date(), locateTool: (ToolCommand) -> URL? = ToolCommand.installed,
                         systemRoot: URL = URL(fileURLWithPath: "/"), cloud: any UbiquitousItemAccess = SystemUbiquitousItems()) -> [Candidate] {
        discovery(home: home, userFolder: userFolder, exclusions: exclusions, inUse: inUse, sizer: sizer, now: now, locateTool: locateTool, systemRoot: systemRoot, cloud: cloud).candidates
    }

    /// `discover`, plus notes on rules that kept items back, such as copies kept because their use couldn't be checked.
    /// A rule that needs Full Disk Access CacheDrop doesn't have (`access`) is never read; it comes back in `notAccessible`.
    public func discovery(home: URL, userFolder: URL? = nil, exclusions: ExclusionPolicy = ExclusionPolicy(), inUse: any InUseChecking = SystemInUseChecker(), sizer: KnownLocationSizer = KnownLocationSizer(), now: Date = Date(), locateTool: (ToolCommand) -> URL? = ToolCommand.installed,
                          systemRoot: URL = URL(fileURLWithPath: "/"), cloud: any UbiquitousItemAccess = SystemUbiquitousItems(), access: FullDiskAccessStatus = .unknown,
                          progress: (CatalogDiscoveryProgress) -> Void = { _ in }) -> CatalogDiscovery {
        // Guidance rules report their own access (`guidance(home:)`).
        let notAccessible = rules.filter { $0.action != .guidance && $0.access(given: access) == .needsFullDiskAccess }
        let homeBase = home.resolvingSymlinksInPath(), userBase = userFolder
        // One reading of the process table for every rule that asks what is in use.
        let inUse = inUse.snapshot()
        var seen = Set<String>()
        var notes: [CatalogNote] = []
        var scanned: [String] = []
        var notMeasured: [String: Set<String>] = [:]
        // `docker system df` runs once per scan for every Docker rule, whenever the CLI is installed: without its folder
        // nothing is offered, but a daemon that doesn't answer is still shown.
        var dockerUsage: [String: Result<[DockerStorageCategory], ToolPreviewError>] = [:]
        // simctl's lists are read once per scan for both simulator rules (#134).
        var simulators: [String: Result<SimulatorInventory, ToolPreviewError>] = [:]
        let overridden = Set(overriddenRules(home: home, systemRoot: systemRoot).map(\.id))
        // Guidance rules are sized by `guidance(home:)` and never become candidates.
        let checked = rules.filter { $0.action != .guidance && !overridden.contains($0.id) && ($0.base == .home || userBase != nil) }
        func offered(by rule: CleanupRule) -> [Candidate] {
            guard let base = rule.base == .home ? homeBase : userBase else { return [] }
            // Looked at but not read: What grew records it as not measured, so access granted later is coverage, not growth.
            if notAccessible.contains(where: { $0.id == rule.id }) { scanned.append(rule.id); return [] }
            // What an earlier cleanup left half-deleted comes back under the same rule, even if its tool is gone.
            var leftovers = leftovers(of: rule, in: base, sizer: sizer)
            let toolURL = rule.tool.flatMap(locateTool)
            guard rule.action != .tool || toolURL != nil else { return leftovers.map { $0.found(under: base) } }
            scanned.append(rule.id)
            for location in rule.locations where Self.cantRead(location, under: base) { notMeasured[rule.id, default: []].insert(location) }
            if case .docker = rule.items, let toolURL {
                let usage = dockerUsage[toolURL.path] ?? DockerDiskUsage.read(toolURL)
                if dockerUsage[toolURL.path] == nil, case .failure(let error) = usage { notes.append(CatalogNote(ruleID: rule.id, text: DockerDiskUsage.notice(error))) }
                dockerUsage[toolURL.path] = usage
                if case .failure = usage { notMeasured[rule.id, default: []].formUnion(rule.locations); return leftovers.map { $0.found(under: base) } }
            }
            // A tool that names its own folder (`uv cache dir`, `npm config get cache`) is asked; its answer replaces the rule's locations.
            var reported: URL?, defaultsNote: CatalogNote?, folderSource: String?
            if let (asker, isOwnTool) = rule.locationAsker {
                let location = reportedLocation(of: rule, asking: asker, at: isOwnTool ? toolURL : locateTool(asker.lookup), base: base)
                // An interrupted clean of the named folder left its rest next to it (#202).
                if let named = location.named { leftovers += self.leftovers(of: rule, nextTo: named, in: base, sizer: sizer) }
                switch location {
                case .folder(let folder, let source): reported = folder; folderSource = source
                case .defaults(let note, let source): defaultsNote = note; folderSource = source ?? "Default location"
                case .notOffered(let note, let unmeasured, _):
                    notes.append(note)
                    if unmeasured { notMeasured[rule.id, default: []].formUnion(rule.locations) }
                    return leftovers.map { $0.found(under: base) }
                }
            }
            // A trailing `/*` offers each folder inside (DeviceSupport versions); a `*` inside the path names a profile.
            let located = reported.map { [($0, String?.none)] } ?? rule.locations.flatMap { location -> [(URL, String?)] in
                // A pattern as the last component (`models--*`) also offers each matching folder.
                (location as NSString).lastPathComponent.contains("*")
                    ? Self.childFolders(of: location, in: base, keepNewestVersions: rule.keepNewestVersions).map { (base.appendingPathComponent($0), nil) }
                    : Self.pathsMatching(location, under: base).map { ($0.0, $0.1.isEmpty ? nil : $0.1.joined(separator: "/")) }
            }
            // An app's folder holding a web-view profile offers everything but the profile, and the profile's caches (#203, #241).
            let places = rule.id == AppCaches.appCachesRuleID
                ? located.flatMap { url, profile in AppCaches.offeredFolders(in: url, offlineContent: rule.offlineContent).map { ($0, profile) } } : located
            let found = places.flatMap { url, profile -> [Candidate] in
                guard Protection(rule).protectedComponent(of: url, below: base) == nil, ScopeContainment.contains(url, in: base) else { return [] }
                if let copies = rule.copies {
                    let (found, note) = leakedCopies(rule, copies, in: url, sizer: sizer, inUse: inUse)
                    notes += note.map { [$0] } ?? []
                    return found
                }
                if let unused = rule.unused {
                    let (found, note) = unusedItems(rule, unused, in: url, base: base, now: now, sizer: sizer, inUse: inUse)
                    notes += note.map { [$0] } ?? []
                    return found
                }
                if rule.action == .evict { return cloudCandidates(in: url, rule: rule, cloud: cloud, exclusions: exclusions) }
                if let contents = rule.contents { return files(in: url, matching: contents, rule: rule, now: now) }
                if rule.items == .ollamaModels { return ollamaModels(in: url, rule: rule, toolURL: toolURL) }
                if rule.items == .androidVirtualDevices { return androidVirtualDevices(in: url, rule: rule, sizer: sizer) }
                if rule.items == .androidSystemImages {
                    let (found, note) = androidSystemImages(in: url, home: base, rule: rule, sizer: sizer)
                    notes += note.map { [$0] } ?? []
                    return found
                }
                if rule.items == .simulatorRuntimes || rule.items == .simulatorDevices, let toolURL {
                    let read = simulators[toolURL.path] ?? SimulatorInventory.read(toolURL)
                    if simulators[toolURL.path] == nil, case .failure = read { notes.append(CatalogNote(ruleID: rule.id, text: SimulatorInventory.notice)) }
                    simulators[toolURL.path] = read
                    // Every rule that reads simctl is unmeasured when it fails, never read as gone (Decision 45, #212).
                    guard case .success(let inventory) = read else { notMeasured[rule.id, default: []].formUnion(rule.locations); return [] }
                    return rule.items == .simulatorDevices ? simulatorDevices(in: url, rule: rule, toolURL: toolURL, inventory: inventory, sizer: sizer)
                        : simulatorRuntimes(anchor: url, rule: rule, toolURL: toolURL, inventory: inventory)
                }
                if rule.items == .unavailableSimulators, let toolURL {
                    let read = simulators[toolURL.path] ?? SimulatorInventory.read(toolURL)
                    // Sized from the list, so measuring it again after a stopped run has a baseline (#209).
                    if case .success(let inventory) = read {
                        simulators[toolURL.path] = read
                        return unavailableSimulators(in: url, rule: rule, toolURL: toolURL, inventory: inventory, sizer: sizer)
                    }
                    // Without the list it is offered at an unknown size, as before, and is never measured as gone. The
                    // simulator rules read the list again and say why.
                    notMeasured[rule.id, default: []].formUnion(rule.locations)
                }
                if case .docker(let kind) = rule.items, let toolURL {
                    guard case .success(let rows)? = dockerUsage[toolURL.path] else { return [] }
                    return dockerCandidate(kind, at: url, rule: rule, toolURL: toolURL, usage: rows).map { [$0] } ?? []
                }
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { return [] }
                if rule.yieldsToOtherRules, claimedByAnotherRule(url, besides: rule, base: base) { return [] }
                // Folders holding live work (a git checkout, protected data) are left out of the plan; the check refuses them either way.
                if info.st_mode & S_IFMT == S_IFDIR, CandidateCheck.protectedEntry(in: url, rule: rule) != nil { return [] }
                var appName: String?
                switch Self.ownership(of: url, under: rule) {
                case .unknown: return []
                case .mustBeClosed(let owner) where rule.itemOwner != nil: appName = owner.name
                default: break
                }
                // A tool that cleans only part of its folder frees an unknown amount; the folder's total would overstate it.
                let size = rule.tool?.deletesLocationAfter == false ? ItemSize(logicalBytes: 0, allocatedBytes: nil, entries: 0, complete: false) : sizer.size(url)
                // Models and disk images show when they were last used, so the user can judge (SPEC section 3).
                let lastUsed = rule.regen == .model ? Self.lastUsedInside(url, info) : nil
                var found = candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: lastUsed, toolURL: toolURL,
                                      profile: profile)
                found.itemName = rule.itemName?(url.lastPathComponent)
                found.appName = appName
                found.folderSource = folderSource
                return [found]
            }
            // The default folder offered in place of one the tool didn't name says so (#170).
            if let defaultsNote, !found.isEmpty { notes.append(defaultsNote) }
            return (found + leftovers).map { $0.found(under: base) }
        }
        var candidates: [Candidate] = []
        // One rule at a time, in catalog order, so progress can report each as it finishes (#128).
        for (index, rule) in checked.enumerated() {
            progress(.checking(ruleID: rule.id, title: rule.title, number: index + 1, total: checked.count))
            let kept = offered(by: rule).filter { candidate in
                // Excluded items are never candidates (SPEC section 2); the check refuses them again just before acting.
                // With exclusions set, an item whose volume can't be read can't be cleared of them, so it is left out too.
                if !exclusions.rules.isEmpty, candidate.volumeID.map({ exclusions.covers(candidate.url, volumeID: $0) }) ?? true { return false }
                return seen.insert(spaceKey(of: candidate)).inserted
            }
            candidates += kept
            progress(.finished(ruleID: rule.id, number: index + 1, total: checked.count, found: kept))
        }
        return CatalogDiscovery(candidates: candidates, notes: notes, scannedRuleIDs: scanned, notAccessible: notAccessible, notMeasured: notMeasured)
    }

    /// Whether a location exists but can't be listed (macOS privacy protection, permissions): the folder it names, or
    /// the one its first `*` part is matched in. Nothing found there is then a measurement of 0.
    static func cantRead(_ location: String, under base: URL) -> Bool {
        let fixed = location.split(separator: "/").prefix { !$0.contains("*") }.joined(separator: "/")
        let url = fixed.isEmpty ? base : base.appendingPathComponent(fixed)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return false }
        return !isReadable(url, info)
    }

    /// What a candidate's space is keyed on, so the same space is offered once (`SpaceKey`).
    func spaceKey(of candidate: Candidate) -> String {
        SpaceKey.of(resourceID: candidate.resourceID, ruleID: candidate.ruleID, action: candidate.action, item: candidate.toolItem)
    }

    /// Whether another rule's location is this item, holds it, or exists inside it, whether or not that rule offers it now.
    func claimedByAnotherRule(_ url: URL, besides rule: CleanupRule, base: URL) -> Bool {
        let parts = Array(url.pathComponents.dropFirst(base.pathComponents.count))
        return rules.contains { other in
            other.id != rule.id && other.base == rule.base && other.locations.contains { location in
                let pattern = location.split(separator: "/").map(String.init)
                let shared = min(pattern.count, parts.count)
                guard zip(pattern.prefix(shared), parts.prefix(shared)).allSatisfy({ fnmatch($0, $1, 0) == 0 }) else { return false }
                if pattern.count <= parts.count { return true }
                return Self.pathsMatching(pattern.dropFirst(shared).joined(separator: "/"), under: url).contains { found, _ in
                    var info = stat()
                    return lstat(found.path, &info) == 0
                }
            }
        }
    }

    func candidate(_ rule: CleanupRule, _ url: URL, _ info: stat, logical: Int64, allocated: Int64?, complete: Bool, lastUsed: Date?, toolURL: URL? = nil, profile: String? = nil,
                   action: CleanupAction? = nil) -> Candidate {
        let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return Candidate(ruleID: rule.id, action: action ?? rule.action, url: url, resourceID: info.resourceID,
                         isDirectory: info.st_mode & S_IFMT == S_IFDIR, toolURL: toolURL, volumeID: volume,
                         modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                         logicalBytes: logical, allocatedBytes: allocated, sizeComplete: complete, lastUsed: lastUsed, observedAt: Date(), profile: profile)
    }

    /// The paths a location names under `base`. A `*` component matches each visible folder at that level, and a
    /// component such as `*.ShipIt` each visible folder whose name matches it
    /// (a browser profile, say), never a symlink; the matched names come back with the path.
    static func pathsMatching(_ relative: String, under base: URL) -> [(URL, [String])] {
        relative.split(separator: "/").map(String.init).reduce([(base, [String]())]) { paths, part in
            guard part.contains("*") else { return paths.map { ($0.0.appendingPathComponent(part), $0.1) } }
            return paths.flatMap { url, matched in
                ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted().compactMap { name -> (URL, [String])? in
                    var info = stat()
                    let child = url.appendingPathComponent(name)
                    guard !name.hasPrefix("."), fnmatch(part, name, 0) == 0, lstat(child.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
                    return (child, matched + [name])
                }
            }
        }
    }

    /// Regular files under `root` that match. Never follows symlinks, crosses volumes or enters packages and protected folders.
    private func files(in root: URL, matching match: ContentsMatch, rule: CleanupRule, now: Date) -> [Candidate] {
        let protection = Protection(rule)
        var found: [Candidate] = []
        FileTree.walk(root) { entry in
            let kind = Int32(entry.pointee.fts_info)
            guard let info = entry.pointee.fts_statp?.pointee, kind == FTS_D || kind == FTS_F else { return .continue }
            let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
            let name = url.lastPathComponent, ext = url.pathExtension.lowercased()
            if kind == FTS_D {
                let package = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                // A git working tree is live work: nothing inside it is offered (the check refuses it too).
                return GitCheckout.isRoot(url) || (entry.pointee.fts_level > 0 && (package || protection.protects(name))) ? .skip : .continue
            }
            guard info.st_uid == geteuid(), !protection.protects(name), info.st_flags & UInt32(SF_DATALESS) == 0 else { return .continue }
            if !match.extensions.isEmpty, !match.extensions.contains(ext) { return .continue }
            if let minimum = match.minimumBytes, Int64(info.st_size) < minimum { return .continue }
            if match.besideCompressedSource, !Self.hasCompressedSource(url, size: Int64(info.st_size)) { return .continue }
            // A download's or installer's age ignores access time (#336), so Smart clean can tell an old one (#342).
            let lastUsed = rule.regen == .installer || rule.category == .downloads ? Self.lastOpenedOrChanged(url, info) : Self.lastUsed(url, info)
            if let days = match.unusedDays, lastUsed > now.addingTimeInterval(-Double(days) * .secondsPerDay) { return .continue }
            found.append(candidate(rule, url, info, logical: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512, complete: true, lastUsed: lastUsed))
            return .continue
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
    /// An installer's age (#336): the latest of Spotlight's last-opened date, change and creation times. Not its access time,
    /// which anything that reads the file sets (Spotlight's import, a backup, an antivirus scan), so an old installer would
    /// never look old.
    static func lastOpenedOrChanged(_ url: URL, _ info: stat) -> Date {
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9) }
        var dates = [date(info.st_mtimespec), date(info.st_birthtimespec)]
        if let item = MDItemCreateWithURL(nil, url as CFURL), let opened = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { dates.append(opened) }
        return dates.max()!
    }

    /// At most this many children of a `*` location are offered.
    static let childLimit = 1_000
    /// A plain location as is; a `parent/*` location as each real folder directly inside `parent`.
    /// The last component may be a shell pattern such as `models--*`.
    static func childFolders(of relative: String, in base: URL, keepNewestVersions keep: Int? = nil) -> [String] {
        let pattern = (relative as NSString).lastPathComponent
        guard pattern.contains("*") else { return [relative] }
        let parent = (relative as NSString).deletingLastPathComponent
        // A `*` above the last component (`models/*/*`: each publisher's models) expands to each matching folder first.
        if parent.contains("*") {
            return pathsMatching(parent, under: base).flatMap { _, names -> [String] in
                var matched = names.makeIterator()
                let expanded = parent.split(separator: "/").map { $0.contains("*") ? matched.next() ?? "" : String($0) }.joined(separator: "/")
                return childFolders(of: expanded + "/" + pattern, in: base, keepNewestVersions: keep)
            }
        }
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
