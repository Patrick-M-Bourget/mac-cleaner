import Foundation

/// Whether the Applications page waits for the running catalog scan (Decisions 123 and 134, #556, #647). The rescan after a
/// run keeps the apps and plug-ins the run didn't touch (`CatalogExecutionResult.touchedApplications`): they stay readable,
/// can be ticked and reviewed, and only the touched rows wait. A row whose app or product went leaves at once. Files from
/// deleted apps, every other page and Clean up still wait for the scan, and any other scan asked for meanwhile makes the page
/// wait again.
public struct ApplicationsRescan: Sendable, Equatable {
    /// The running rescan, or the one about to start, keeps the apps and plug-ins it doesn't read again.
    public private(set) var keeps = false
    /// The rows the running rescan reads again, while it `keeps` the rest.
    public private(set) var rereads = TouchedApplications()
    /// The last prepared scan that could change what the page lists: a kept rescan carries it over, so the page reads its
    /// lists again only after a scan that could change them. Nil while such a scan runs, or after one that prepared nothing.
    public private(set) var listsScan: UUID?
    /// What the last run touched; used up by the rescan after it. Nil: it may have changed anything.
    private var lastRun: TouchedApplications?
    /// The rows whose app or product went since `listsScan`'s lists were read, so the page no longer lists them.
    private var removedRows: Set<String> = []
    /// The lists `removedRows` were removed from.
    private var removedFrom: UUID?
    public init() {}

    /// A run starts: until it ends saying otherwise, it may change anything.
    public mutating func runStarted() { lastRun = nil }
    /// A run ended having touched `touched`; nil when it can't say, so the rescan after it is a full scan.
    public mutating func runEnded(touched: TouchedApplications?) { lastRun = touched }
    /// The run left nothing of these rows' apps or products (`TouchedApplications.gone`): the page stops listing them.
    public mutating func runRemoved(_ rows: Set<String>) {
        removedRows = removedFrom == listsScan ? removedRows.union(rows) : rows
        removedFrom = listsScan
    }
    /// A scan was asked for: `afterRun` for the rescan a run ends with, any other for launch, Scan again, a Put back and the
    /// rest. One asked for while `scanning` waits for the running scan; if it may change the page, the page waits for the
    /// running one too, and one that keeps the page never vouches for a scan already running.
    public mutating func rescanRequested(afterRun: Bool, scanning: Bool) {
        let keeping = afterRun ? lastRun : nil
        if afterRun { lastRun = nil }
        if scanning {
            if keeping == nil { keeps = false }
        } else {
            keeps = keeping != nil; rereads = keeping ?? TouchedApplications()
        }
    }
    public mutating func scanStarted() { if !keeps { listsScan = nil } }
    public mutating func scanPrepared(_ id: UUID) { if !keeps { listsScan = id } }
    /// The scan found nothing it could offer (the Protected items couldn't be read): the lists are read again.
    public mutating func scanFoundNothing() { listsScan = nil }

    /// Whether Apps and Plug-ins wait for the scan as a whole: dimmed, and not read.
    public func appsWait(scanning: Bool) -> Bool { scanning && !keeps }
    /// Whether the row `id` waits for the scan, dimmed: every row while Apps and Plug-ins wait, during a kept rescan only
    /// one it reads again.
    public func rowWaits(_ id: String, scanning: Bool) -> Bool { scanning && (!keeps || rereads.rows.contains(id)) }
    /// Whether the page no longer lists the row `id`, in the lists read for the scan `loaded`: its app or product went.
    public func hides(_ id: String, loaded: UUID?) -> Bool { removedFrom == loaded && removedRows.contains(id) }
    /// Whether `items` can be ticked, or reviewed together, now: anything once no scan runs; during a kept rescan only the
    /// items of an installed app or plug-in product whose row it doesn't read again.
    public func canChoose(_ items: [Candidate], scanning: Bool) -> Bool {
        !scanning || (keeps && items.allSatisfy { AppRuleFamily.of(ruleID: $0.ruleID)?.isUninstall == true && !rereads.touches($0) })
    }
}
