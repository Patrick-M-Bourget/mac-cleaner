import Foundation

/// Owns discovery and its final saved outcomes together. Visible scan state may clear before these tasks end.
/// A stop callback interrupts discovery only; the task must still await all of its resulting writes.
@MainActor public final class ScanLifecycle {
    private struct Work {
        let task: Task<Void, Never>
        var stop: (@MainActor () -> Void)?
    }
    private var work: [UUID: Work] = [:]
    public init() {}
    public var isRunning: Bool { !work.isEmpty }

    @discardableResult public func start(stop: @escaping @MainActor () -> Void = {}, operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task {
            await operation()
            work[id] = nil
        }
        work[id] = Work(task: task, stop: stop)
        return task
    }

    /// Requests are idempotent, including requests made while final writes are still in flight.
    public func requestStop() {
        for id in Array(work.keys) {
            let stop = work[id]?.stop
            work[id]?.stop = nil
            stop?()
        }
    }

    public func waitForCompletion() async {
        // A stop may enqueue a final History write. Include that work even when it starts during this wait.
        while let task = work.values.first?.task { await task.value }
    }

    public func stopAndWait() async {
        requestStop()
        await waitForCompletion()
    }
}
