import Foundation
import Observation

/// One approved installation owns admission until it is canceled, fails, or hands off to Sparkle.
/// Cleanup and maintenance report natural completion; neither is canceled by an update.
@MainActor @Observable public final class UpdateInstallation {
    public enum State: Equatable, Sendable { case idle, waitingForCleanup, finishingCurrentWork, installing }
    public private(set) var state = State.idle
    public var blocksNewWork: Bool { state != .idle }
    public var canCancel: Bool { state == .waitingForCleanup || state == .finishingCurrentWork }
    private let finishWork: @MainActor () async throws -> Void
    private let resumeWork: @MainActor () -> Void
    private var cleanupRunning = false
    private var maintenanceRunning = false
    private var generation = UUID()
    private var preparation: Task<Void, Never>?
    private var install: (@MainActor () -> Void)?
    private var cancellation: (@MainActor () -> Void)?

    public init(finishWork: @escaping @MainActor () async throws -> Void, resumeWork: @escaping @MainActor () -> Void) {
        self.finishWork = finishWork; self.resumeWork = resumeWork
    }

    @discardableResult public func request(cleanupRunning: Bool, maintenanceRunning: Bool,
                                           install: @escaping @MainActor () -> Void, cancel: @escaping @MainActor () -> Void) -> Bool {
        guard state == .idle else { return false }
        generation = UUID()
        self.install = install; cancellation = cancel
        state = .finishingCurrentWork
        workChanged(cleanupRunning: cleanupRunning, maintenanceRunning: maintenanceRunning)
        return true
    }

    public func workChanged(cleanupRunning: Bool, maintenanceRunning: Bool) {
        self.cleanupRunning = cleanupRunning; self.maintenanceRunning = maintenanceRunning
        guard canCancel else { return }
        state = cleanupRunning ? .waitingForCleanup : .finishingCurrentWork
        guard !cleanupRunning, !maintenanceRunning, preparation == nil else { return }
        let token = generation
        preparation = Task {
            guard token == generation, canCancel else { return }
            do { try await finishWork() }
            catch {
                guard token == generation else { return }
                cancel()
                return
            }
            guard token == generation, canCancel else { return }
            preparation = nil
            // Admission has stayed closed throughout preparation, so work cannot race this final handoff.
            guard !self.cleanupRunning, !self.maintenanceRunning else {
                workChanged(cleanupRunning: self.cleanupRunning, maintenanceRunning: self.maintenanceRunning)
                return
            }
            let handoff = install
            install = nil; cancellation = nil
            state = .installing
            handoff?()
        }
    }

    public func cancel() {
        guard canCancel else { return }
        let reply = cancellation
        reset()
        reply?()
    }

    /// Sparkle has aborted the cycle already, so its obsolete reply must not be invoked again.
    public func failed() { guard state != .idle else { return }; reset() }

    private func reset() {
        generation = UUID(); install = nil; cancellation = nil; preparation = nil
        state = .idle
        resumeWork()
    }

    public func waitForPreparation() async { await preparation?.value }
}
