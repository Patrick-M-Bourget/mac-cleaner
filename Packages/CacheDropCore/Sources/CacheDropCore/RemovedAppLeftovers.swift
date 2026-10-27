import Foundation
import Darwin

/// Leftovers of apps you removed (#173, Decision 41): files in `~/Library` whose app is no longer on this Mac, grouped per app.
/// An item is tied to a removed app only by its bundle ID or an installer receipt; a name-only match is "possibly related",
/// shown with its reason and never ticked with its group. Everything goes to Trash, so Put back works.
public enum RemovedAppLeftovers {
    public static let ruleID = "removed-app-leftovers"
    public static let possiblyRelatedRuleID = "removed-app-possibly-related"
    static let consequence = "Moved to Trash. The app is no longer installed; you can restore them from the Trash in Finder."
    public static let rules: [CleanupRule] = [
        CleanupRule(id: ruleID, category: .leftovers, title: "Leftovers of removed apps",
                    detail: "Settings, caches and data of apps no longer on this Mac, tied to each app by its bundle ID or installer receipt.",
                    consequence: consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth),
        CleanupRule(id: possiblyRelatedRuleID, category: .leftovers, title: "Possibly related",
                    detail: "Folders named like a removed app or its maker. Nothing ties them to it for sure, so check each one.",
                    consequence: consequence, regen: .userFile, action: .trash, locations: [], owner: nil, protectedDepth: AppCaches.liveWorkDepth,
                    itemByItem: true),
    ]
    static let ruleIDs: Set<String> = [ruleID, possiblyRelatedRuleID]

    /// The `~/Library` folders looked in; each entry directly inside one is an item.
    static let places = ["Application Support", "Caches", "Containers", "Group Containers", "Preferences", "Saved Application State",
                         "LaunchAgents", "HTTPStorages", "WebKit", "Logs"].map { "Library/" + $0 }

    /// The bundle ID an entry's name carries, if any: `com.x.y.plist`, `com.x.y.savedState`, `com.x.y.binarycookies`,
    /// a group container's `TEAMID.com.x.y` or `group.com.x.y`.
    static func bundleID(inName name: String) -> String? {
        var key = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where key.hasSuffix(suffix) { key = String(key.dropLast(suffix.count)) }
        if key.hasPrefix("group.") { key = String(key.dropFirst(6)) }
        let parts = key.split(separator: ".", maxSplits: 1)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) { key = String(parts[1]) }
        return AppCaches.isBundleID(key) ? key : nil
    }
    /// The maker part of a bundle ID: `com.ableton` for `com.ableton.live`.
    static func vendor(of bundleID: String) -> String { bundleID.lowercased().split(separator: ".").prefix(2).joined(separator: ".") }
    /// A name for an app known only by its bundle ID: "Live" for `com.ableton.live`.
    static func appName(from bundleID: String) -> String {
        let parts = bundleID.split(separator: ".").map(String.init)
        let generic: Set<String> = ["app", "mac", "macos", "osx", "desktop", "client"]
        let word = parts.reversed().first { !generic.contains($0.lowercased()) } ?? parts.last ?? bundleID
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// The leftovers under `home`. Read-only. Offers nothing when the installed apps can't be listed: an app counts as removed
    /// only when no copy is found, by Launch Services or Spotlight, on any volume.
    public static func scan(home: URL, apps: any AppPresence, receipts: any InstallerReceiptReading, exclusions: ExclusionPolicy = ExclusionPolicy(),
                            sizer: KnownLocationSizer = KnownLocationSizer()) -> [Candidate] {
        guard let installed = apps.installedApps() else { return [] }
        let base = home.resolvingSymlinksInPath()
        let catalog = Catalog(rules: rules)
        // A maker with an installed app or plug-in keeps every item named for it: a helper, extension or shared group may be that product's.
        let makers = InstalledMakers(installed)
        func isRemovedApp(_ id: String) -> Bool { isRemoved(id, apps: apps, installed: installed) && !makers.makes(vendor(of: id)) }
        // Receipts whose every app is gone from where it was installed and from Spotlight's list, of a maker with nothing installed.
        let removedReceipts = receipts.receipts().filter { receipt in
            !receipt.apps.isEmpty && !makers.makes(vendor(of: receipt.id)) && receipt.apps.allSatisfy { app in
                !FileManager.default.fileExists(atPath: app) && !makers.goesBy(token(receiptAppName(app)))
            }
        }
        let entries = places.flatMap { place -> [(URL, stat)] in
            let folder = base.appendingPathComponent(place)
            return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().compactMap { name in
                let url = folder.appendingPathComponent(name)
                var info = stat()
                guard !name.hasPrefix("."), !isNeverOffered(name), !launchAgentProgramExists(url), lstat(url.path, &info) == 0, info.st_uid == geteuid(),
                      [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT),
                      let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString, !exclusions.covers(url, volumeID: volume),
                      info.st_mode & S_IFMT != S_IFDIR || CandidateCheck.protectedEntry(in: url, rule: rules[0]) == nil else { return nil }
                return (url, info)
            }
        }
        // Only an app has a container or saved window state: those prove an ID was an app's. A command-line tool's or an
        // installer's preferences and caches don't (#251).
        let appIDs = Set(entries.compactMap { appEvidence($0.0) })
        // The removed apps the bundle-ID items name, for matching the rest by name.
        let removedIDs = appIDs.filter(isRemovedApp).sorted()
        func tie(_ url: URL) -> LeftoverTie? {
            let name = url.lastPathComponent
            // A group container is shared by the maker's apps: offered only when it is named exactly for a removed app.
            if isGroupContainer(url) {
                guard let id = bundleID(inName: name), appIDs.contains(id.lowercased()), isRemovedApp(id) else { return nil }
                return LeftoverTie(app: appName(from: id), bundleID: id, vendor: vendor(of: id), evidence: .bundleID)
            }
            if let id = bundleID(inName: name) {
                guard isRemovedApp(id) else { return nil }
                if appIDs.contains(id.lowercased()) { return LeftoverTie(app: appName(from: id), bundleID: id, vendor: vendor(of: id), evidence: .bundleID) }
                return LeftoverTie(app: appName(from: id), bundleID: id, vendor: vendor(of: id), evidence: .nameOnly(
                    "Named for \(id), but no app, plug-in or installer receipt on this Mac has that ID, and nothing shows it was an app's. A command-line tool may use it."))
            }
            if let receipt = removedReceipts.first(where: { $0.paths.contains(url.path) || $0.paths.contains { $0.hasPrefix(url.path + "/") } }) {
                return LeftoverTie(app: receipt.apps.first.map(receiptAppName) ?? receipt.id, bundleID: nil, vendor: vendor(of: receipt.id), evidence: .receipt(receipt.id))
            }
            let named = token(name)
            guard named.count >= 3, !makers.goesBy(named) else { return nil }
            if let id = removedIDs.first(where: { token(appName(from: $0)) == named }) {
                return LeftoverTie(app: appName(from: id), bundleID: id, vendor: vendor(of: id), evidence: .nameOnly("Named like \(appName(from: id)) (\(id)), which is no longer installed"))
            }
            if let id = removedIDs.first(where: { vendorToken($0) == named }) {
                return LeftoverTie(app: appName(from: id), bundleID: id, vendor: vendor(of: id), evidence: .nameOnly("Named like the maker of \(appName(from: id)) (\(id)), which is no longer installed"))
            }
            return nil
        }
        return entries.compactMap { url, info in
            guard let tie = tie(url) else { return nil }
            let rule = tie.isNameOnly ? rules[1] : rules[0]
            let size = sizer.size(url)
            var item = catalog.candidate(rule, url, info, logical: size.logicalBytes, allocated: size.allocatedBytes, complete: size.complete, lastUsed: nil)
            item.leftover = tie
            item.appName = tie.app
            return item.found(under: base)
        }
    }
    /// A name reduced to its lowercased letters and digits, for matching folder names to app and maker names.
    static func token(_ name: String) -> String { String(name.lowercased().filter { $0.isLetter || $0.isNumber }) }
    /// The maker's word in a bundle ID: "ableton" for `com.ableton.live`.
    static func vendorToken(_ bundleID: String) -> String { token(bundleID.split(separator: ".").dropFirst().first.map(String.init) ?? "") }
    static func receiptAppName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    static func isGroupContainer(_ url: URL) -> Bool { url.deletingLastPathComponent().lastPathComponent == "Group Containers" }
    /// The app ID an entry proves was an app's, lowercased: a container (`Containers/<id>`) or saved window state.
    static func appEvidence(_ url: URL) -> String? {
        let name = url.lastPathComponent
        switch url.deletingLastPathComponent().lastPathComponent {
        case "Containers": return AppCaches.isBundleID(name) ? name.lowercased() : nil
        case "Saved Application State": return name.hasSuffix(".savedState") ? bundleID(inName: name)?.lowercased() : nil
        default: return nil
        }
    }

    /// The leftovers no catalog item already covers: one that is, holds or sits inside an offered item is left to its rule,
    /// so no space is offered twice.
    public static func notOffered(by offered: [Candidate], _ leftovers: [Candidate]) -> [Candidate] {
        let paths = offered.map { $0.url.standardizedFileURL.path }
        return leftovers.filter { item in
            let path = item.url.standardizedFileURL.path
            return !paths.contains { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }
        }
    }

    /// The check just before acting (#173): license, macOS and CacheDrop's own data are refused wherever a scan found them,
    /// and an app that is on this Mac again, or whose presence can't be read, keeps its leftovers.
    static func refusal(for url: URL, tie: LeftoverTie, below root: URL, apps: any AppPresence) -> CheckRefusal? {
        if let part = url.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count).first(where: isNeverOffered) { return .protected(part) }
        guard let installed = apps.installedApps() else { return .appInstalled(tie.app) }
        let makers = InstalledMakers(installed)
        if makers.makes(tie.vendor) { return .appInstalled(tie.app) }
        if let id = tie.bundleID, !isRemoved(id, apps: apps, installed: installed) { return .appInstalled(tie.app) }
        if tie.bundleID == nil, makers.goesBy(token(tie.app)) { return .appInstalled(tie.app) }
        if tie.isNameOnly, makers.goesBy(token(url.lastPathComponent)) { return .appInstalled(tie.app) }
        // A group container only on an exact match, and a confirmed bundle-ID item only while the app's container or saved
        // state shows the ID was an app's (#251).
        let name = url.lastPathComponent
        if isGroupContainer(url), tie.isNameOnly || bundleID(inName: name)?.lowercased() != tie.bundleID?.lowercased() { return .protected(name) }
        if tie.evidence == .bundleID, let id = tie.bundleID?.lowercased(), !hasAppEvidence(id, below: root) { return .protected(name) }
        return nil
    }

    /// Whether a container or saved window state under `root` still shows `id` was an app's.
    static func hasAppEvidence(_ id: String, below root: URL) -> Bool {
        let library = root.appendingPathComponent("Library")
        return ["Containers", "Saved Application State"].contains { place in
            ((try? FileManager.default.contentsOfDirectory(atPath: library.appendingPathComponent(place).path)) ?? [])
                .contains { appEvidence(library.appendingPathComponent(place).appendingPathComponent($0)) == id }
        }
    }

    /// Names never offered, whatever ties them to a removed app: macOS's own (`com.apple.*`), CacheDrop's and Still's, and
    /// license and copy-protection data (iLok/PACE, eLicenser, CodeMeter and any name about a license or activation), which
    /// other apps of the maker, or a reinstall, still need.
    static func isNeverOffered(_ name: String) -> Bool {
        let lower = name.lowercased()
        if AppCaches.isMacOSOrOwn(name) || lower.hasPrefix("group.com.apple.") || lower.contains(".com.apple.") { return true }
        if bundleID(inName: name).map({ AppCaches.isMacOSOrOwn($0) || isAppleLegacy($0) || isSharedFramework($0) }) == true { return true }
        return licenseWords.contains { lower.contains($0) }
    }
    /// Apple's IDs outside `com.apple.`: Shortcuts keeps Workflow's (`is.workflow.*`, `group.is.workflow.*`), and its data
    /// is the user's shortcuts (#251).
    static let appleLegacyPrefixes = ["is.workflow."]
    static func isAppleLegacy(_ bundleID: String) -> Bool { appleLegacyPrefixes.contains { bundleID.lowercased().hasPrefix($0) } }
    /// Frameworks and SDKs that installed apps embed and name their files by (#251): they never identify a removed app.
    static let sharedFrameworkPrefixes = ["org.sparkle-project.", "com.juce.", "com.segment.", "com.telemetrydeck.", "io.branch.", "com.github.electron."]
    static func isSharedFramework(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased() + "."
        return sharedFrameworkPrefixes.contains { id.hasPrefix($0) }
    }
    static let licenseWords = ["ilok", "paceap", "pace anti", "elicenser", "syncrosoft", "codemeter", "wibu", "licens", "licenc", "activation", "authoriz"]
    /// A LaunchAgent whose program is still on disk belongs to something installed, whatever its label says.
    static func launchAgentProgramExists(_ url: URL) -> Bool {
        guard url.deletingLastPathComponent().lastPathComponent == "LaunchAgents" else { return false }
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return true }
        guard let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first else { return true }
        return FileManager.default.fileExists(atPath: program)
    }

    /// Whether no copy of the app is installed: neither Spotlight's list nor Launch Services knows it.
    static func isRemoved(_ bundleID: String, apps: any AppPresence, installed: [InstalledApp]) -> Bool {
        let id = bundleID.lowercased()
        return !installed.contains { $0.bundleID.lowercased() == id } && !apps.isRegistered(bundleID: bundleID)
    }
}

/// The makers of what is installed (#251): apps, plug-ins and other bundles, by bundle ID vendor (`com.fabfilter`) and by the
/// maker their bundles name ("Reason Studios" makes `com.reasonstudios.*`). Any product of a maker keeps all of the maker's items.
struct InstalledMakers {
    let vendors: Set<String>
    /// Installed apps' and plug-ins' names, their makers' words and bundle ID makers, as tokens.
    let names: Set<String>
    /// Tokens long enough to match as a prefix: "propellerhead" for `se.propellerheads`, "reason" for "Reason Companion".
    let prefixes: Set<String>
    static let generic: Set<String> = ["software", "ab", "inc", "gmbh", "ltd", "llc", "co", "corp", "audio", "music", "technology", "technologies", "labs", "the"]

    init(_ installed: [InstalledApp]) {
        typealias L = RemovedAppLeftovers
        vendors = Set(installed.filter { !$0.bundleID.isEmpty }.map { L.vendor(of: $0.bundleID) })
        let makerWords = installed.compactMap(\.maker).flatMap { maker -> [String] in
            let words = maker.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { L.token(String($0)) }
            return [L.token(maker), words.filter { !Self.generic.contains($0) }.joined()] + words.filter { !Self.generic.contains($0) }
        }
        let ids = installed.filter { !$0.bundleID.isEmpty }.flatMap { [L.token(L.appName(from: $0.bundleID)), L.vendorToken($0.bundleID)] }
        names = Set((installed.map { L.token($0.name) } + ids + makerWords).filter { !$0.isEmpty })
        prefixes = Set((installed.filter { !$0.bundleID.isEmpty }.map { L.vendorToken($0.bundleID) } + makerWords).filter { $0.count >= 4 })
    }
    /// Whether a maker (`com.maker`) has something installed, by bundle ID or by the maker's name.
    func makes(_ vendor: String) -> Bool {
        if vendors.contains(vendor.lowercased()) { return true }
        let word = RemovedAppLeftovers.vendorToken(vendor)
        return word.count >= 4 && prefixes.contains { $0.hasPrefix(word) || word.hasPrefix($0) }
    }
    /// Whether a name (as a token) is an installed product's or its maker's, or starts with a maker's name.
    func goesBy(_ name: String) -> Bool { names.contains(name) || prefixes.contains { name.hasPrefix($0) } }
}

/// What ties a leftover to the removed app it is grouped under.
public struct LeftoverTie: Sendable, Hashable {
    public enum Evidence: Sendable, Hashable {
        /// Its name is the app's bundle ID.
        case bundleID
        /// An installer receipt with this package ID lists it.
        case receipt(String)
        /// Only its name matches; the reason is shown with it.
        case nameOnly(String)
    }
    /// The app's name, as the group shows it.
    public let app: String
    public let bundleID: String?
    /// The maker part of the bundle or package ID (`com.ableton`); any running process of the maker's blocks the group.
    public let vendor: String
    public let evidence: Evidence
    /// Who must be closed first: every app of the maker (#173), named after it ("Ableton" for `com.ableton`).
    public var owner: RuleOwner {
        let word = vendor.split(separator: ".").dropFirst().first.map(String.init) ?? vendor
        return RuleOwner(name: word.prefix(1).uppercased() + word.dropFirst(), bundleIDPrefixes: [vendor + "."])
    }
    var isNameOnly: Bool { if case .nameOnly = evidence { true } else { false } }
    /// Why a possibly related item is shown; nil for a confirmed one.
    public var reason: String? { if case .nameOnly(let reason) = evidence { reason } else { nil } }
}

extension CleanupRule {
    /// Its items are ticked one by one, never with their category, rule or app (#173: possibly related leftovers).
    public var selectedOneByOne: Bool { id == RemovedAppLeftovers.possiblyRelatedRuleID }
}

/// Which apps are on this Mac, on every volume. Injected so tests never ask Launch Services or Spotlight.
public protocol AppPresence: Sendable {
    /// Every app found, on any volume; nil when the list can't be read, so nothing is offered.
    func installedApps() -> [InstalledApp]?
    /// Whether Launch Services knows an app with this bundle ID.
    func isRegistered(bundleID: String) -> Bool
    /// This presence read once, for checking many items together.
    func snapshot() -> any AppPresence
}
extension AppPresence {
    public func snapshot() -> any AppPresence { self }
}

/// An installer receipt (`pkgutil`): its package ID, the app bundles it installed and every path it lists, all absolute.
public struct InstallerReceipt: Sendable, Hashable {
    public let id: String
    public let apps: [String]
    public let paths: Set<String>
    public init(id: String, apps: [String], paths: Set<String>) { self.id = id; self.apps = apps; self.paths = paths }
}
/// Reads the installer receipts. Injected so tests never read this Mac's.
public protocol InstallerReceiptReading: Sendable {
    func receipts() -> [InstallerReceipt]
}
