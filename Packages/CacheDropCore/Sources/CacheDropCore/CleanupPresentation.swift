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
        case .permanentlyRemoved: "Delete permanently"
        case .movedToTrash: "Move to Trash"
        case .localCopiesRemoved: "Remove local copies"
        case .commandsRun: "Run cleanup commands"
        }
    }
    /// The one sentence the review shows for the group.
    public var consequence: String {
        switch self {
        case .permanentlyRemoved: "Apps download or rebuild these when they need them."
        case .movedToTrash: "You can put these back until you empty the Trash."
        case .localCopiesRemoved: "The files stay in iCloud and download again when you open them, which needs an internet connection."
        case .commandsRun: "Each tool’s own cleanup command deletes these permanently."
        }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
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

extension PathDisplay {
    /// A catalog item's short location: iCloud Drive by name, otherwise `shortLocation(of:home:)`, e.g. `~/Downloads`.
    public static func shortLocation(of url: URL, home: URL) -> String {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        let drive = home.standardizedFileURL.path + "/" + BuiltInCatalog.iCloudDrivePath
        if parent == drive { return "iCloud Drive" }
        if parent.hasPrefix(drive + "/") { return "iCloud Drive › " + URL(fileURLWithPath: parent).lastPathComponent }
        return shortLocation(of: url.path, home: home.path)
    }
}
