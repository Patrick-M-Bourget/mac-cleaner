/// Work that runs in the background while any screen is open (Decision 46), each labelled by what it is (#230).
public enum BackgroundJob: Hashable, Sendable {
    /// The catalog's scan of its known locations.
    case catalogScan
    /// Scan again's recheck of the selected locations.
    case folderRecheck
    /// A new folder picked with "Scan a folder…" or "Add folder…".
    case folderScan(folder: String)

    /// The accessibility identifier of the bar's line while this work leads it.
    public var identifier: String {
        switch self {
        case .catalogScan: "catalogScanProgress"
        case .folderRecheck: "folderRecheckProgress"
        case .folderScan: "folderScanProgress"
        }
    }
    /// What the bar says; the catalog's text is read live ("Checking npm cache… 4 of 31").
    public func text(catalogProgress: String) -> String {
        switch self {
        case .catalogScan: catalogProgress
        case .folderRecheck: "Rechecking selected locations…"
        case .folderScan(let folder): "Scanning \(folder)…"
        }
    }
    /// Work that starts at the same moment, as Scan again's two scans do, is ordered folder scans first.
    fileprivate var startOrder: Int { if case .catalogScan = self { 1 } else { 0 } }
}

/// Background work the bottom bar reports as one quiet line (Decision 46): the work that started first, plus how many more
/// are running ("Checking npm cache… 4 of 31 · +1 more").
public struct BackgroundWork: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// The identifier of the work the line names.
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
    }
    /// Running work, earliest first.
    public private(set) var running: [BackgroundJob] = []
    public init() {}
    /// Records what runs now: finished work leaves, new work goes after the work already running.
    public mutating func update(running now: Set<BackgroundJob>) {
        running.removeAll { !now.contains($0) }
        running += now.subtracting(running).sorted { ($0.startOrder, $0.identifier) < ($1.startOrder, $1.identifier) }
    }
    /// The bar's line; nil when nothing runs.
    public func line(catalogProgress: String) -> Line? {
        guard let first = running.first else { return nil }
        let others = running.count - 1
        let text = first.text(catalogProgress: catalogProgress)
        return Line(id: first.identifier, text: others > 0 ? text + " · +\(others) more" : text)
    }
}
