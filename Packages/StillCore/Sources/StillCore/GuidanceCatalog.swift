import Foundation
import Darwin

/// How a guidance-only rule (SPEC section 3) is sized and where the user manages it. Still never changes these.
public struct Guidance: Sendable {
    public enum Sizing: Sendable, Equatable {
        /// Each location's whole tree, metadata only.
        case locations
        /// Only folders with this name inside the locations (Mail keeps attachments in `Attachments` folders).
        case foldersNamed(String)
        /// Time Machine local snapshots: counted, never sized, since macOS reports no size per snapshot.
        case localSnapshots
    }
    /// Where "Open …" goes.
    public enum Place: Sendable, Equatable {
        /// The first existing location, in Finder.
        case folder
        /// The owning app.
        case app(bundleID: String)
        /// A System Settings pane or other URL.
        case url(URL)
    }
    public let sizing: Sizing
    public let place: Place
    /// The place's name, as in "Open Photos".
    public let placeName: String
    public init(sizing: Sizing = .locations, place: Place, placeName: String) {
        self.sizing = sizing; self.place = place; self.placeName = placeName
    }
    public var openTitle: String { "Open " + placeName }
}

/// What Still could see of a guidance category. Unknown is never 0 (SPEC section 1).
public enum GuidanceSize: Sendable, Equatable {
    case estimate(SizeEstimate)
    /// macOS didn't let Still read it, usually because it needs Full Disk Access.
    case notAccessible
    /// Time Machine local snapshots: how many, size unknown.
    case snapshots(Int)
}

/// One guidance category found on this Mac. It is never a candidate and never in a plan.
public struct GuidanceFinding: Sendable, Identifiable, Equatable {
    public var id: String { ruleID }
    public let ruleID: String
    public let size: GuidanceSize
    /// The first existing location, which a `.folder` place opens.
    public let folder: URL?
}

/// What "Open …" opens for a finding.
public enum GuidanceTarget: Sendable, Equatable {
    case folder(URL), app(bundleID: String), url(URL)
}

/// Opens a guidance target. The app uses NSWorkspace; tests pass a fake, so nothing opens.
public protocol GuidanceOpening: Sendable {
    func open(_ target: GuidanceTarget) async -> Bool
}

/// Counts Time Machine local snapshots. nil means they couldn't be listed.
public protocol LocalSnapshotListing: Sendable {
    func count() -> Int?
}

/// `tmutil listlocalsnapshots /`, which needs no admin rights. It names snapshots but gives no sizes.
public struct TmutilSnapshots: LocalSnapshotListing {
    public init() {}
    public func count() -> Int? {
        guard let output = try? BoundedTool.run(executable: URL(fileURLWithPath: "/usr/bin/tmutil"), arguments: ["listlocalsnapshots", "/"], timeout: 10) else { return nil }
        return Self.count(in: output)
    }
    /// Lines naming a snapshot, such as `com.apple.TimeMachine.2026-10-26-101010.local`.
    public static func count(in output: String) -> Int {
        output.split(whereSeparator: \.isNewline).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("com.apple.TimeMachine.") }.count
    }
}

extension BuiltInCatalog {
    private static func guidanceRule(_ id: String, _ title: String, detail: String, locations: [String], protected: Bool = false, _ guidance: Guidance) -> CleanupRule {
        CleanupRule(id: id, category: .managed, title: title, detail: detail,
                    consequence: "Guidance only. Still shows the size and where to manage it, and never changes it.",
                    regen: .userFile, action: .guidance, locations: locations, owner: nil, requiresFullDiskAccess: protected, guidance: guidance)
    }
    /// SPEC section 3, "Guidance only". Locations starting with `/` are read under the system root.
    static let guidanceRules: [CleanupRule] = [
        guidanceRule("device-backups", "iPhone and iPad backups",
                     detail: "Backups of your devices. Manage them in Finder: select a connected device, then Manage Backups.",
                     locations: ["Library/Application Support/MobileSync/Backup"], protected: true,
                     Guidance(place: .app(bundleID: "com.apple.finder"), placeName: "Finder")),
        guidanceRule("mail-attachments", "Mail attachments",
                     detail: "Attachments Mail downloaded. Remove large messages or attachments in Mail.",
                     locations: ["Library/Mail", "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], protected: true,
                     Guidance(sizing: .foldersNamed("Attachments"), place: .app(bundleID: "com.apple.mail"), placeName: "Mail")),
        guidanceRule("messages-attachments", "Messages attachments",
                     detail: "Photos, videos and files from your conversations. Review them in Messages, or in System Settings → General → Storage.",
                     locations: ["Library/Messages/Attachments"], protected: true,
                     Guidance(place: .app(bundleID: "com.apple.MobileSMS"), placeName: "Messages")),
        guidanceRule("photos-library", "Photos library",
                     detail: "Your Photos library. Photos manages it; with iCloud Photos, Optimize Mac Storage keeps smaller copies on this Mac.",
                     locations: ["Pictures/Photos Library.photoslibrary"], protected: true,
                     Guidance(place: .app(bundleID: "com.apple.Photos"), placeName: "Photos")),
        guidanceRule("time-machine-snapshots", "Time Machine local snapshots",
                     detail: "macOS keeps these and removes them on its own when space runs low. Their size isn’t reported.",
                     locations: [],
                     Guidance(sizing: .localSnapshots, place: .url(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!), placeName: "Storage Settings")),
        guidanceRule("xcode-archives", "Xcode archives",
                     detail: "Builds you archived to distribute. Keep the ones you may need to diagnose crashes; manage them in Xcode’s Organizer.",
                     locations: ["Library/Developer/Xcode/Archives"],
                     Guidance(place: .app(bundleID: "com.apple.dt.Xcode"), placeName: "Xcode")),
        guidanceRule("audio-plug-ins", "Audio plug-ins",
                     detail: "Plug-ins you bought or installed. Remove them with the vendor’s uninstaller, and reinstall through the vendor.",
                     locations: ["/Library/Audio/Plug-Ins", "Library/Audio/Plug-Ins"],
                     Guidance(place: .folder, placeName: "in Finder")),
    ]
}

extension Catalog {
    /// Sizes the guidance-only rules (SPEC section 3). Reads metadata only, through `sizer`; never file contents.
    /// A rule appears when one of its locations exists; one Still can't read is `.notAccessible`, never 0.
    /// Without Full Disk Access, a rule that needs it is `.notAccessible` without being touched, so no privacy prompt appears.
    public func guidance(home: URL, systemRoot: URL = URL(fileURLWithPath: "/"), sizer: KnownLocationSizer = KnownLocationSizer(),
                         snapshots: any LocalSnapshotListing = TmutilSnapshots(), fullDiskAccess: FullDiskAccessStatus = .unknown) -> [GuidanceFinding] {
        rules.compactMap { rule -> GuidanceFinding? in
            guard rule.action == .guidance, let guidance = rule.guidance else { return nil }
            if rule.access(given: fullDiskAccess) == .needsFullDiskAccess { return GuidanceFinding(ruleID: rule.id, size: .notAccessible, folder: nil) }
            if guidance.sizing == .localSnapshots {
                guard let count = snapshots.count() else { return GuidanceFinding(ruleID: rule.id, size: .notAccessible, folder: nil) }
                return count > 0 ? GuidanceFinding(ruleID: rule.id, size: .snapshots(count), folder: nil) : nil
            }
            var parts: [SizeEstimate] = [], denied = 0, folder: URL?
            for location in rule.locations {
                let url = location.hasPrefix("/") ? systemRoot.appendingPathComponent(String(location.dropFirst())) : home.appendingPathComponent(location)
                var info = stat()
                if lstat(url.path, &info) != 0 {
                    if errno != ENOENT { denied += 1 }
                    continue
                }
                folder = folder ?? url
                guard Self.isReadable(url, info) else { denied += 1; continue }
                switch guidance.sizing {
                case .foldersNamed(let name): parts.append(Self.sizeOfFolders(named: name, in: url, sizer: sizer))
                default: parts.append(Self.estimate(sizer.size(url)))
                }
            }
            if parts.isEmpty { return denied > 0 ? GuidanceFinding(ruleID: rule.id, size: .notAccessible, folder: folder) : nil }
            if denied > 0 { parts.append(.unknown) }
            let total = SizeEstimate(sum: parts)
            // Nothing there, such as a Mail folder with no attachments, is no finding.
            return total == .measured(0) ? nil : GuidanceFinding(ruleID: rule.id, size: .estimate(total), folder: folder)
        }
    }

    /// What "Open …" opens for a finding: the owning app, a settings pane, or the folder in Finder.
    public func target(for finding: GuidanceFinding) -> GuidanceTarget? {
        guard let guidance = rule(finding.ruleID)?.guidance else { return nil }
        switch guidance.place {
        case .app(let bundleID): return .app(bundleID: bundleID)
        case .url(let url): return .url(url)
        case .folder: return finding.folder.map(GuidanceTarget.folder)
        }
    }

    /// Opens where the finding is managed. False when there is nowhere to go or it didn't open.
    public func open(_ finding: GuidanceFinding, using opener: any GuidanceOpening) async -> Bool {
        guard let target = target(for: finding) else { return false }
        return await opener.open(target)
    }

    /// A folder must list its entries to be sized; macOS privacy protection (TCC) refuses that without Full Disk Access.
    static func isReadable(_ url: URL, _ info: stat) -> Bool {
        guard info.st_mode & S_IFMT == S_IFDIR else { return true }
        guard let dir = opendir(url.path) else { return false }
        closedir(dir)
        return true
    }

    static func estimate(_ size: ItemSize) -> SizeEstimate {
        let bytes = size.allocatedBytes ?? size.logicalBytes
        return size.complete ? .measured(bytes) : bytes > 0 ? .atLeast(bytes) : .unknown
    }

    /// The summed size of every folder called `name` inside `root`, whose contents are never listed beyond sizing.
    static func sizeOfFolders(named name: String, in root: URL, sizer: KnownLocationSizer) -> SizeEstimate {
        let deadline = ProcessInfo.processInfo.systemUptime + sizer.timeBudget
        let path = strdup(root.path)
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let tree = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return .unknown }
        defer { fts_close(tree) }
        var parts: [SizeEstimate] = [], complete = true, entries = 0
        while let entry = fts_read(tree) {
            entries += 1
            switch Int32(entry.pointee.fts_info) {
            case FTS_DNR, FTS_ERR, FTS_NS: complete = false
            case FTS_D:
                let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                guard entry.pointee.fts_level > 0, url.lastPathComponent == name else { continue }
                parts.append(estimate(sizer.size(url)))
                fts_set(tree, entry, FTS_SKIP)
            default: break
            }
            if entries % 1024 == 0, ProcessInfo.processInfo.systemUptime > deadline { complete = false; break }
        }
        if !complete { parts.append(.unknown) }
        return parts.isEmpty ? .measured(0) : SizeEstimate(sum: parts)
    }
}
