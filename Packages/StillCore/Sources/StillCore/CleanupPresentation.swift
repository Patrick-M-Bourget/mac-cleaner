import Foundation

/// What a cleanup does to an item, as the review groups it (Decision 25). Each consequence is explained once, for its group.
public enum ConsequenceGroup: Int, CaseIterable, Sendable, Comparable {
    case permanentlyRemoved, movedToTrash, localCopiesRemoved, commandsRun

    /// Guidance never joins a plan, so it has no group.
    public init?(_ action: CleanupAction) {
        switch action {
        case .delete: self = .permanentlyRemoved
        case .trash: self = .movedToTrash
        case .evict: self = .localCopiesRemoved
        case .tool: self = .commandsRun
        case .guidance: return nil
        }
    }
    public var title: String {
        switch self {
        case .permanentlyRemoved: "Permanently removed"
        case .movedToTrash: "Moved to Trash"
        case .localCopiesRemoved: "Local copies removed"
        case .commandsRun: "Commands run"
        }
    }
    /// The one sentence the review shows for the group.
    public var consequence: String {
        switch self {
        case .permanentlyRemoved: "Apps download or rebuild these as needed, so the next use may take longer. They can’t be restored from the Trash."
        case .movedToTrash: "Recoverable in Finder until you empty the Trash. The space stays used until then."
        case .localCopiesRemoved: "The files stay in iCloud and download again when you open them, which needs an internet connection."
        case .commandsRun: "Still runs each tool’s own cleanup command, shown with the files. What a command removes is permanently removed."
        }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The review's groups: one per consequence, each with one line per catalog category, in catalog order.
public struct ReviewGroup: Sendable, Identifiable {
    public struct Line: Sendable, Identifiable {
        public var id: String { category.rawValue }
        public let category: CatalogCategory
        /// The category's rules with chosen items in this group, in catalog order.
        public let rules: [CleanupRule]
        public let candidates: [Candidate]
        public let estimate: SizeEstimate
        /// Part of it is copies that share disk blocks, so less may come back (SPEC section 6).
        public var isUpperBound: Bool { rules.contains(where: \.estimateIsUpperBound) }
        public func candidates(for rule: CleanupRule) -> [Candidate] { candidates.filter { $0.ruleID == rule.id } }
    }
    public var id: Int { consequence.rawValue }
    public let consequence: ConsequenceGroup
    public let lines: [Line]
    public var candidates: [Candidate] { lines.flatMap(\.candidates) }

    public static func groups(catalog: Catalog, candidates: [Candidate]) -> [ReviewGroup] {
        let found = catalog.rules.filter { rule in candidates.contains { $0.ruleID == rule.id } }
        return ConsequenceGroup.allCases.compactMap { group in
            let rules = found.filter { ConsequenceGroup($0.action) == group }
            var order: [CatalogCategory] = []
            for rule in rules where !order.contains(rule.category) { order.append(rule.category) }
            let lines = order.map { category in
                let inLine = rules.filter { $0.category == category }, ids = Set(inLine.map(\.id))
                let chosen = candidates.filter { ids.contains($0.ruleID) }
                return Line(category: category, rules: inLine, candidates: chosen, estimate: SizeEstimate(sum: chosen.map(SizeEstimate.init)))
            }
            return lines.isEmpty ? nil : ReviewGroup(consequence: group, lines: lines)
        }
    }
}

extension CleanupRecord {
    /// Not done and not a clean preview: skipped, failed, not started or unresolved. Results list these first, with their reason.
    public var needsAttention: Bool { !wasPreviewed && state != .succeeded }
    /// The size the scan recorded, allocated where known.
    public var recordedBytes: Int64 { allocatedBytes ?? logicalBytes }
}

extension Array where Element == CleanupRecord {
    /// Records that need attention first; each part keeps its run order.
    public var attentionFirst: [CleanupRecord] { filter(\.needsAttention) + filter { !$0.needsAttention } }
}

/// Short locations for rows: the full path goes in a tooltip or a disclosure (Decision 25).
public enum PathDisplay {
    /// Where an item sits, in a few words: "Downloads" for `~/Downloads/Setup.dmg`, "Chrome › Default" for a deeper folder,
    /// "iCloud Drive" for iCloud Drive's top level.
    public static func shortLocation(of url: URL, home: URL) -> String {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        let homePath = home.standardizedFileURL.path
        let drive = homePath + "/" + BuiltInCatalog.iCloudDrivePath
        if parent == drive { return "iCloud Drive" }
        if parent.hasPrefix(drive + "/") { return "iCloud Drive › " + URL(fileURLWithPath: parent).lastPathComponent }
        if parent == homePath { return "Home" }
        let components = URL(fileURLWithPath: parent).pathComponents.filter { $0 != "/" }
        let homeDepth = URL(fileURLWithPath: homePath).pathComponents.filter { $0 != "/" }.count
        let inHome = parent.hasPrefix(homePath + "/")
        let tail = components.suffix(inHome ? Swift.min(2, components.count - homeDepth) : 2)
        return tail.joined(separator: " › ")
    }
}
