import Foundation
import Darwin

extension Catalog {
    /// Sizes the guidance-only rules (SPEC section 3). Reads metadata only, through `sizer`; never file contents.
    /// A rule appears when one of its locations exists; one CacheDrop can't read is `.notAccessible`, never 0.
    /// Without Full Disk Access, a rule that needs it is `.notAccessible` without being touched, so no privacy prompt appears.
    public func guidance(home: URL, systemRoot: URL = URL(fileURLWithPath: "/"), sizer: KnownLocationSizer = KnownLocationSizer(),
                         snapshots: any LocalSnapshotListing = TmutilSnapshots(), fullDiskAccess: FullDiskAccessStatus = .unknown) -> [GuidanceFinding] {
        rules.compactMap { rule -> GuidanceFinding? in
            guard rule.action == .guidance, let guidance = rule.guidance else { return nil }
            if rule.access(given: fullDiskAccess) == .needsFullDiskAccess { return GuidanceFinding(ruleID: rule.id, size: .notAccessible, folder: nil) }
            if guidance.sizing == .localSnapshots {
                guard let count = snapshots.count() else { return GuidanceFinding(ruleID: rule.id, size: .unavailable, folder: nil) }
                return count > 0 ? GuidanceFinding(ruleID: rule.id, size: .snapshots(count), folder: nil) : nil
            }
            var parts: [SizeEstimate] = [], denied = 0, folder: URL?, read: [URL] = []
            for location in rule.locations {
                let url = location.hasPrefix("/") ? systemRoot.appendingPathComponent(String(location.dropFirst())) : home.appendingPathComponent(location)
                var info = stat()
                if lstat(url.path, &info) != 0 {
                    if errno != ENOENT { denied += 1 }
                    continue
                }
                folder = folder ?? url
                guard Self.isReadable(url, info) else { denied += 1; continue }
                read.append(url)
                switch guidance.sizing {
                case .foldersNamed(let name): parts.append(Self.sizeOfFolders(named: name, in: url, sizer: sizer))
                default: parts.append(Self.estimate(sizer.size(url)))
                }
            }
            if parts.isEmpty { return denied > 0 ? GuidanceFinding(ruleID: rule.id, size: .notAccessible, folder: folder) : nil }
            if denied > 0 { parts.append(.unknown) }
            let total = SizeEstimate(sum: parts)
            // Nothing there, such as a Mail folder with no attachments, is no finding.
            guard total != .measured(0) else { return nil }
            let workspaces = guidance.sizing == .agentWorkspaces ? WorkspaceGit.workspaces(in: read) : nil
            return GuidanceFinding(ruleID: rule.id, size: .estimate(total), folder: folder, workspaces: workspaces)
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

    /// Opens where the finding is managed. When its app doesn't open, usually because it isn't installed (GarageBand
    /// without Logic Pro), the folder is revealed in Finder instead (#139). False when there is nowhere to go or it didn't open.
    public func open(_ finding: GuidanceFinding, using opener: any GuidanceOpening) async -> Bool {
        guard let target = target(for: finding) else { return false }
        if await opener.open(target) { return true }
        guard case .app = target, let folder = finding.folder else { return false }
        return await opener.open(.folder(folder))
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
        var parts: [SizeEstimate] = [], complete = true, entries = 0
        let opened = FileTree.walk(root) { entry in
            entries += 1
            var next = FileTree.Next.continue
            switch Int32(entry.pointee.fts_info) {
            case FTS_DNR, FTS_ERR, FTS_NS: complete = false
            case FTS_D:
                let url = URL(fileURLWithPath: String(cString: entry.pointee.fts_path))
                if entry.pointee.fts_level > 0, url.lastPathComponent == name { parts.append(estimate(sizer.size(url))); next = .skip }
            default: break
            }
            if entries % 1024 == 0, ProcessInfo.processInfo.systemUptime > deadline { complete = false; return .stop }
            return next
        }
        guard opened else { return .unknown }
        if !complete { parts.append(.unknown) }
        return parts.isEmpty ? .measured(0) : SizeEstimate(sum: parts)
    }
}
