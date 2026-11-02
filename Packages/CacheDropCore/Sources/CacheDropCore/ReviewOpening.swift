import Foundation

/// A page's review sheet from the click to Clean up (Decision 126, #463). The sheet opens at the click with its click-time
/// checks running in it; Clean up has a review to run only once those checks finish for the same choices.
public struct ReviewOpening<Review> {
    /// One click's checks: the page that clicked and its choices' revision then.
    public struct Attempt: Equatable, Sendable {
        let id: UInt64
        public let source: CleanupSelections.Source
        public let revision: UInt64
    }
    /// What became of one click's checks.
    public enum Outcome: Equatable, Sendable {
        /// Clean up may run the checked review.
        case ready
        /// The page's choices changed while the checks ran: the sheet closed, and the page says so (#307).
        case choicesChanged
        /// The checks couldn't build a review: the sheet closed, and the page says why from the result's error.
        case failed
        /// The sheet closed, or another click opened it, before these checks ended: their result is dropped.
        case dropped
    }
    private enum Phase { case closed, checking(Attempt), ready(Attempt, Review) }
    private var phase = Phase.closed
    private var attempts: UInt64 = 0
    public init() {}

    private var attempt: Attempt? {
        switch phase { case .closed: nil; case .checking(let attempt), .ready(let attempt, _): attempt }
    }
    /// Whether `source`'s sheet is open, checking or ready.
    public func isOpen(for source: CleanupSelections.Source) -> Bool { attempt?.source == source }
    /// The checks are running; Clean up is unavailable.
    public var isChecking: Bool { if case .checking = phase { true } else { false } }
    /// What Clean up runs; nil until the checks finish.
    public var review: Review? { if case .ready(_, let review) = phase { review } else { nil } }

    /// Opens `source`'s sheet at the click, its checks running. Nil when a sheet is already open: one at a time (#308).
    public mutating func open(_ source: CleanupSelections.Source, revision: UInt64) -> Attempt? {
        guard attempt == nil else { return nil }
        attempts += 1
        let attempt = Attempt(id: attempts, source: source, revision: revision)
        phase = .checking(attempt)
        return attempt
    }
    /// The checks of `attempt` ended with `result`, while the page's choices are at `revision`.
    public mutating func finish(_ attempt: Attempt, with result: Result<Review, any Error>, revision: UInt64) -> Outcome {
        guard self.attempt == attempt, case .checking = phase else { return .dropped }
        guard case .success(let review) = result else { phase = .closed; return .failed }
        guard revision == attempt.revision else { phase = .closed; return .choicesChanged }
        phase = .ready(attempt, review)
        return .ready
    }
    /// The sheet closed (Cancel, Clean up or the choices changed): checks still running are dropped when they end.
    public mutating func close() { phase = .closed }
    /// `source`'s choices are now at `revision`. Its open sheet, checking or ready, closes when they differ from the click's,
    /// and true says the page should tell the user (Decision 54). Another page's choices never close it.
    public mutating func choicesChanged(_ source: CleanupSelections.Source, to revision: UInt64) -> Bool {
        guard let attempt, attempt.source == source, attempt.revision != revision else { return false }
        phase = .closed
        return true
    }
}

/// The click-time checks of a review sheet, in steps (Decision 126, #563). Cancel stops them at their next step: a step
/// already running finishes, its result is dropped, and the next one never starts. Smart clean, the plan and Applications
/// all run their checks through it.
public enum ReviewCheckSteps {
    /// Runs `first`, then `next` with what it found, unless the checks were cancelled first; throws `CancellationError` then.
    /// Both steps run on the caller's actor.
    public static func run<Found, Result>(isolation: isolated (any Actor)? = #isolation, _ first: () async throws -> Found,
                                          then next: (Found) async throws -> Result) async throws -> Result {
        try Task.checkCancellation()
        let found = try await first()
        try Task.checkCancellation()
        return try await next(found)
    }
}
