import Foundation

/// The read-only report behind Smart clean's test-and-tweak loop (#319): the real scan, the plan Smart clean would build
/// from it and the checks it would run at Clean up, listed by category with sizes and a reason per item. It only scans and
/// checks: it holds no executor, Trash mover or journal, so nothing in it can act, and it writes nothing, not even its text.
public struct SmartCleanReport: Sendable {
    public struct Item: Sendable {
        public let candidate: Candidate
        /// Why Smart clean takes it.
        public let reason: String
    }
    /// What the scan and the checks read, injected so tests read only a fixture home.
    public struct Sources: Sendable {
        public let catalog: Catalog
        public let home: URL
        public let userFolder: URL?
        public let exclusions: ExclusionPolicy
        public let apps: any AppPresence
        public let receipts: any InstallerReceiptReading
        public let locateTool: @Sendable (ToolCommand) -> URL?
        public let systemRoot: URL
        public let cloud: any UbiquitousItemAccess
        public let inUse: any InUseChecking
        public let running: any RunningAppChecking
        public let access: FullDiskAccessStatus
        public init(catalog: Catalog, home: URL, userFolder: URL?, exclusions: ExclusionPolicy, apps: any AppPresence, receipts: any InstallerReceiptReading,
                    locateTool: @escaping @Sendable (ToolCommand) -> URL?, systemRoot: URL, cloud: any UbiquitousItemAccess, inUse: any InUseChecking,
                    running: any RunningAppChecking, access: FullDiskAccessStatus) {
            self.catalog = catalog; self.home = home; self.userFolder = userFolder; self.exclusions = exclusions; self.apps = apps; self.receipts = receipts
            self.locateTool = locateTool; self.systemRoot = systemRoot; self.cloud = cloud; self.inUse = inUse; self.running = running; self.access = access
        }
        #if DEBUG
        /// This Mac as the app scans it, with the exclusions the user saved, read without the store's lock.
        /// Debug only: the owner's opt-in report test calls it, and Release never does (#334).
        public static func thisMac() throws -> Sources {
            let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
            let exclusions = try ExclusionStore.policy(readingOnly: LocalStateLocation.root(create: false).appendingPathComponent("Exclusions", isDirectory: true))
            return Sources(catalog: Catalog(rules: BuiltInCatalog.rules), home: home, userFolder: Catalog.currentUserFolder(), exclusions: exclusions,
                           apps: SystemAppPresence(), receipts: ReadReceipts(ReceiptListings.read(under: URL(fileURLWithPath: "/")), home: home), locateTool: ToolCommand.installed,
                           systemRoot: URL(fileURLWithPath: "/"), cloud: SystemUbiquitousItems(), inUse: SystemInUseChecker(), running: SystemRunningAppChecker(),
                           access: FullDiskAccessProbe(home: home).status())
        }
        #endif
    }

    public let home: URL
    public let date: Date
    /// What Smart clean would take, in scan order.
    public let picked: [Item]
    /// What it would take but the checks would skip at Clean up, with the reason.
    public let skipped: [(candidate: Candidate, refusal: CheckRefusal)]
    let catalog: Catalog

    /// The plan from `found` with `check` run now, as Smart clean's Clean up would build it.
    public init(catalog: Catalog, home: URL, found: [Candidate], now: Date = Date(), check: (Candidate) -> CheckRefusal?) {
        self.catalog = catalog; self.home = home; date = now
        var refusals: [String: CheckRefusal] = [:]
        let plan = RecommendedPlan(catalog: catalog, candidates: found, now: now) { candidate in
            let refusal = check(candidate)
            if let refusal { refusals[candidate.id] = refusal }
            return refusal
        }
        picked = plan.candidates.compactMap { candidate in catalog.rule(candidate.ruleID).map { Item(candidate: candidate, reason: Self.reason(candidate, rule: $0, now: now)) } }
        skipped = RecommendedPlan(catalog: catalog, candidates: found, now: now) { _ in nil }.candidates.compactMap { candidate in refusals[candidate.id].map { (candidate, $0) } }
    }

    /// The scan the app runs: the catalog's discovery, then leftovers of removed apps no catalog item covers.
    public static func scan(_ sources: Sources) -> [Candidate] {
        let discovered = sources.catalog.discovery(home: sources.home, userFolder: sources.userFolder, exclusions: sources.exclusions, inUse: sources.inUse,
                                                   locateTool: sources.locateTool, systemRoot: sources.systemRoot, cloud: sources.cloud, access: sources.access)
        let leftovers = RemovedAppLeftovers.scan(home: sources.home, apps: sources.apps, receipts: sources.receipts, exclusions: sources.exclusions)
        return discovered.candidates + RemovedAppLeftovers.notOffered(by: discovered.candidates, leftovers)
    }

    /// Scans, builds the plan and runs the full checks, as Clean up would, without acting.
    public static func run(_ sources: Sources, now: Date = Date()) -> SmartCleanReport {
        let found = scan(sources)
        let check = CandidateCheck(catalog: sources.catalog, running: sources.running, exclusions: sources.exclusions, inUse: sources.inUse, cloud: sources.cloud,
                                   home: sources.home, apps: sources.apps, systemRoot: sources.systemRoot).snapshotted()
        return SmartCleanReport(catalog: sources.catalog, home: sources.home, found: found, now: now, check: check.check)
    }

    /// Why Smart clean takes `candidate`, from the plan's own `RecommendedPlan.Basis` so the two never disagree.
    static func reason(_ candidate: Candidate, rule: CleanupRule, now: Date) -> String {
        switch RecommendedPlan.basis(candidate, rule: rule, now: now) {
        case .leftover(let tie):
            switch tie.evidence {
            case .bundleID: return "Leftover tied to \(tie.app) by bundle ID \(tie.bundleID ?? "")"
            case .receipt(let id): return "Leftover tied to \(tie.app) by installer receipt \(id)"
            case .nameOnly(let why): return why
            }
        case .oldInstaller:
            let days = candidate.lastUsed.map { Int(now.timeIntervalSince($0) / .secondsPerDay) } ?? 0
            return "Installer not opened or changed in \(days) days"
        case .rebuildsItself where rule.action == .tool:
            return rule.title + ", cleaned by `" + (rule.tool?.commandLine(for: candidate.toolArgument) ?? "its tool") + "`"
        case .rebuildsItself, nil:
            let kind: String = switch rule.regen {
            case .build: "build files"
            case .updaterDownload: "an update download"
            case .log: "a log"
            case .leakedCopy: "a leftover app copy"
            default: "a cache"
            }
            return rule.title + ", " + kind + (rule.regen == .build ? " that come back on their own" : " that comes back on its own")
        }
    }

    /// The report as text, printed for the owner and never saved.
    public var text: String {
        let home = self.home.standardizedFileURL.path
        func path(_ url: URL) -> String { url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path }
        func size(_ items: [Candidate]) -> String {
            switch SizeEstimate(sum: items.map(SizeEstimate.init)) {
            case .measured(let bytes): ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
            case .about(let bytes): "about " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
            case .atLeast(let bytes): "at least " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
            case .unknown: "unknown size"
            }
        }
        let all = picked.map(\.candidate), trash = all.filter { $0.action == .trash }
        var lines = ["Smart clean report for \(home), \(ISO8601DateFormatter().string(from: date))",
                     "Read-only: it scanned and checked as Clean up would. Nothing on disk was changed, and this text is not saved.",
                     "Would pick \(all.count) \(all.count == 1 ? "item" : "items"), \(size(all))" + (trash.isEmpty ? "" : "; " + SmartCleanConsequence.goesToTrash(size(trash))), ""]
        var order: [CatalogCategory] = []
        for rule in catalog.rules where !order.contains(rule.category) && all.contains(where: { $0.ruleID == rule.id }) { order.append(rule.category) }
        for category in order {
            let items = picked.filter { catalog.rule($0.candidate.ruleID)?.category == category }
            let rules = catalog.rules.filter { rule in rule.category == category && items.contains { $0.candidate.ruleID == rule.id } }
            lines.append("\(category.rawValue) · \(size(items.map(\.candidate))) · \(SmartCleanConsequence.line(for: category, rules: rules))")
            for item in items.sorted(by: { $0.candidate.estimatedBytes > $1.candidate.estimatedBytes }) {
                lines.append("  \(size([item.candidate]))  \(path(item.candidate.url))  — \(item.reason)")
            }
            lines.append("")
        }
        if !skipped.isEmpty {
            lines.append("Left out by the checks (\(skipped.count)):")
            for (candidate, refusal) in skipped { lines.append("  \(size([candidate]))  \(path(candidate.url))  — will be skipped: \(refusal.reason)") }
        }
        return lines.joined(separator: "\n")
    }
}
