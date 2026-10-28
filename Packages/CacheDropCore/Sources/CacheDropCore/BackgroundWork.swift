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
    /// The work's name when its progress follows it on the line.
    var title: String {
        switch self {
        case .catalogScan: "Checking known locations"
        case .folderRecheck: "Rechecking selected locations"
        case .folderScan(let folder): "Scanning \(folder)"
        }
    }
    /// Work that starts at the same moment, as Scan again's two scans do, is ordered folder scans first.
    fileprivate var startOrder: Int { if case .catalogScan = self { 1 } else { 0 } }
}

/// Background work the bottom bar reports as one quiet line (Decision 46): the work that started first, plus how many more
/// are running ("Checking npm cache… 4 of 31 · +1 more"). A folder scan's line also carries its phase and count (#235).
public struct BackgroundWork: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// One piece of the line, with its own accessibility identifier ("scanPhase", "scanProgressSummary").
        public struct Part: Equatable, Sendable {
            public let id: String
            public let text: String
            public init(id: String, text: String) { self.id = id; self.text = text }
        }
        public let parts: [Part]
        /// Whether a folder scan runs, so the line can offer Stop scan and Return to scan.
        public let runsFolderScan: Bool
        public init(parts: [Part], runsFolderScan: Bool = false) { self.parts = parts; self.runsFolderScan = runsFolderScan }
        /// The identifier of the work the line names.
        public var id: String { parts.first?.id ?? "" }
        public var text: String { parts.map(\.text).joined(separator: " · ") }
    }
    /// Running work, earliest first.
    public private(set) var running: [BackgroundJob] = []
    public init() {}
    /// Records what runs now: finished work leaves, new work goes after the work already running.
    public mutating func update(running now: Set<BackgroundJob>) {
        running.removeAll { !now.contains($0) }
        running += now.subtracting(running).sorted { ($0.startOrder, $0.identifier) < ($1.startOrder, $1.identifier) }
    }
    /// The bar's line; nil when nothing runs. `folderPhase` and `inspectedEntries` are the running folder scan's progress.
    public func line(catalogProgress: String, folderPhase: ScanPhase? = nil, inspectedEntries: Int? = nil) -> Line? {
        guard let first = running.first else { return nil }
        var parts: [Line.Part]
        if first != .catalogScan, let folderPhase {
            parts = [.init(id: first.identifier, text: first.title), .init(id: "scanPhase", text: folderPhase.progressText)]
            if let inspectedEntries { parts.append(.init(id: "scanProgressSummary", text: "\(inspectedEntries) \(inspectedEntries == 1 ? "entry" : "entries") inspected")) }
        } else {
            parts = [.init(id: first.identifier, text: first.text(catalogProgress: catalogProgress))]
        }
        if running.count > 1 { parts.append(.init(id: "backgroundWorkMore", text: "+\(running.count - 1) more")) }
        return Line(parts: parts, runsFolderScan: running.contains { $0 != .catalogScan })
    }
}

extension ScanPhase {
    /// The phase as a folder scan's progress line names it (#235).
    public var progressText: String {
        switch self {
        case .enumerating: "Reading file metadata…"
        case .checkingDirectories: "Checking directory stability…"
        case .rechecking: "Rechecking changed coverage…"
        }
    }
}

/// Where the catalog scan is, for the bar's line (#308): discovery counts its known locations, then each later phase is
/// named, so the scan's longest part never shows the last location as if it had hung.
public enum CatalogScanPhase: Equatable, Sendable {
    /// Before discovery has named its first location.
    case starting
    /// Discovery is checking location `number` of `total`.
    case location(title: String, number: Int, total: Int)
    /// After discovery, in the order the scan runs them.
    case removedAppLeftovers, appsAndPlugIns, openApps, storageTrends, appManagedStorage

    public var progressText: String {
        switch self {
        case .starting: "Checking known locations…"
        case .location(let title, let number, let total): "Checking \(title)… \(number) of \(total)"
        case .removedAppLeftovers: "Checking leftovers of removed apps…"
        case .appsAndPlugIns: "Checking apps and plug-ins…"
        case .openApps: "Checking which apps are open…"
        case .storageTrends: "Recording storage trends…"
        case .appManagedStorage: "Checking app-managed storage…"
        }
    }
}
