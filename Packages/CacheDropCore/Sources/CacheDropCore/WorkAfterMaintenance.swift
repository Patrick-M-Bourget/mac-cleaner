import Foundation

/// Work asked for while the maintenance lease is held (History compacting its records, an exclusion being saved), run once
/// it is released, so a scan asked for then is late, never silently dropped (#310). Each kind of work waits once, as last asked.
@MainActor public final class WorkAfterMaintenance {
    private var waiting: [(kind: String, work: () -> Void)] = []
    public init() {}
    /// Keeps `work` until the lease is released, in place of any earlier work of the same `kind`.
    public func waitFor(_ kind: String, _ work: @escaping () -> Void) {
        waiting.removeAll { $0.kind == kind }
        waiting.append((kind, work))
    }
    /// The lease was released: runs what waited, in the order asked, once.
    public func released() {
        let due = waiting
        waiting = []
        for item in due { item.work() }
    }
}
