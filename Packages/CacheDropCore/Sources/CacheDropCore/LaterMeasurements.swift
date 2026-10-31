import Foundation

/// Owns optional work after cleanup. A lifecycle handoff cancels only its timers: measurements and
/// their saved findings finish normally. It never cancels the cleanup that produced the outcomes.
@MainActor public final class LaterMeasurements {
    public typealias Wait = @Sendable (Duration) async -> Bool
    private struct Pending {
        var task: Task<Void, Never>
        var sleep: Task<Bool, Never>?
        var skipWaiting = false
    }
    private var pending: [UUID: Pending] = [:]
    private var handingOff = false

    public init() {}

    /// The operation uses the supplied wait for every optional delay, including later retries.
    public func schedule(wait: @escaping Wait = CleanupExecutor.sleeping,
                         operation: @escaping @MainActor @Sendable (@escaping Wait) async -> Void) {
        guard !handingOff else { return }
        let id = UUID()
        let task = Task {
            await operation { delay in await self.wait(id, for: delay, using: wait) }
            pending[id] = nil
        }
        pending[id] = Pending(task: task)
    }

    private func wait(_ id: UUID, for delay: Duration, using sleep: @escaping Wait) async -> Bool {
        guard pending[id]?.skipWaiting == false else { return false }
        let timer = Task { await sleep(delay) }
        pending[id]?.sleep = timer
        let elapsed = await timer.value
        pending[id]?.sleep = nil
        return elapsed && pending[id]?.skipWaiting == false
    }

    /// Stops sleeping work promptly and waits for work already measuring, including its final writes.
    /// Repeated callers await the same tasks. New optional work stays suspended until `resume()`.
    public func finishForLifecycle() async {
        handingOff = true
        let tasks = pending.values.map(\.task)
        for id in Array(pending.keys) {
            pending[id]?.skipWaiting = true
            pending[id]?.sleep?.cancel()
        }
        for task in tasks { await task.value }
    }

    /// Future cleanups may schedule normally; skipped timers from the previous handoff stay skipped.
    public func resume() { handingOff = false }
}
