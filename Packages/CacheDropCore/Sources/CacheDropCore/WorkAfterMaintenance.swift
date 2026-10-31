import Foundation

/// Work asked for while the maintenance lease is held (History compacting its records, an exclusion being saved), run once
/// it is released, so a scan asked for then is late, never silently dropped (#310). Each kind of work waits once, as last asked.
@MainActor public final class WorkAfterMaintenance {
    /// The kinds of work that wait: each waits once, as last asked.
    public enum Kind: Sendable { case catalogScan, folderScan, folderRecheck }
    private var waiting: [(kind: Kind, rescan: Bool, work: (Bool) -> Void)] = []
    public init() {}
    /// Keeps `work` until the lease is released, in place of any earlier work of the same `kind`.
    public func waitFor(_ kind: Kind, _ work: @escaping () -> Void) {
        waitFor(kind, rescan: false) { _ in work() }
    }
    /// As above, for a scan that may be a rescan (#332): `work` gets true when any request of this `kind` while the lease
    /// was held was a rescan, so a later plain scan never drops the remembered folders' recheck.
    public func waitFor(_ kind: Kind, rescan: Bool, _ work: @escaping (_ rescan: Bool) -> Void) {
        let earlier = waiting.contains { $0.kind == kind && $0.rescan }
        waiting.removeAll { $0.kind == kind }
        waiting.append((kind, rescan || earlier, work))
    }
    /// The lease was released: runs what waited, in the order asked, once.
    public func released(allowingWork: Bool = true) {
        guard allowingWork else { return }
        let due = waiting
        waiting = []
        for item in due { item.work(item.rescan) }
    }
}
