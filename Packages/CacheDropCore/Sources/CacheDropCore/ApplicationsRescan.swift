import Foundation

/// Whether the Applications page waits for the running catalog scan (Decision 123, #556). After a run that changed nothing
/// the page lists (`CatalogExecutionResult.changesApplications`), the rescan that follows keeps its apps and plug-ins: they
/// stay readable, can be ticked and reviewed. Files from deleted apps, every other page and Clean up still wait for the scan,
/// and any other scan asked for meanwhile makes the page wait again.
public struct ApplicationsRescan: Sendable, Equatable {
    /// The running rescan, or the one about to start, keeps the apps and plug-ins.
    public private(set) var keeps = false
    /// The last prepared scan that could change what the page lists: a kept rescan carries it over, so the page reads its
    /// lists again only after a scan that could change them. Nil while such a scan runs, or after one that prepared nothing.
    public private(set) var listsScan: UUID?
    /// The last run changed nothing the page lists; used up by the rescan after it.
    private var lastRunKept = false
    public init() {}

    /// A run starts: until it ends saying otherwise, it may change anything.
    public mutating func runStarted() { lastRunKept = false }
    /// A run ended; `kept` when it changed nothing the page lists.
    public mutating func runEnded(keptApplications kept: Bool) { lastRunKept = kept }
    /// A scan was asked for: `afterRun` for the rescan a run ends with, any other for launch, Scan again, a Put back and the
    /// rest. One asked for while `scanning` waits for the running scan; if it may change the page, the page waits for the
    /// running one too, and one that keeps the page never vouches for a scan already running.
    public mutating func rescanRequested(afterRun: Bool, scanning: Bool) {
        let keeping = afterRun && lastRunKept
        if afterRun { lastRunKept = false }
        if scanning { if !keeping { keeps = false } } else { keeps = keeping }
    }
    public mutating func scanStarted() { if !keeps { listsScan = nil } }
    public mutating func scanPrepared(_ id: UUID) { if !keeps { listsScan = id } }
    /// The scan found nothing it could offer (the Protected items couldn't be read): the lists are read again.
    public mutating func scanFoundNothing() { listsScan = nil }

    /// Whether Apps and Plug-ins wait for the scan: dimmed, and not read.
    public func appsWait(scanning: Bool) -> Bool { scanning && !keeps }
    /// Whether `items` can be ticked, or reviewed together, now: anything once no scan runs; during a kept rescan only an
    /// installed app's or plug-in product's items.
    public func canChoose(_ items: [Candidate], scanning: Bool) -> Bool {
        !scanning || (keeps && items.allSatisfy { AppRuleFamily.of(ruleID: $0.ruleID)?.isUninstall == true })
    }
}
