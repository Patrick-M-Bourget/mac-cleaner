import Foundation

/// The trial (Decisions 135 and 137): Clean up and Applications uninstall are free until they have freed 2 GB on this Mac.
public enum Trial {
    /// 2 GB in SizeFormatter's decimal units, so "2 GB" on screen is exactly the cap.
    public static let freeBytes: Int64 = 2_000_000_000
}

/// What Clean up may free now: anything (gating off, or an active license) or what the trial has left.
public enum CleanupAllowance: Equatable, Sendable {
    case unlimited
    case trial(left: Int64)

    /// A key that isn't valid or is revoked counts as no license, so the trial applies.
    public init(gating: Bool, license: LicenseState, used: Int64) {
        if !gating { self = .unlimited; return }
        if case .active = license { self = .unlimited; return }
        self = .trial(left: max(0, Trial.freeBytes - used))
    }

    /// Whether a plan freeing `plan` bytes may run: never past the cap, and a dry run is never blocked.
    public func permits(_ plan: Int64, dryRun: Bool) -> Bool {
        guard !dryRun, case .trial(let left) = self else { return true }
        return plan <= left
    }
}

extension CatalogApproval {
    /// The plan's size against the trial: what Clean up will act on, removed or moved to the Trash, each space once (as
    /// the run's estimate counts it), without the items the review says will be skipped.
    public func trialBytes(skipping skipped: Set<String>, catalog: Catalog) -> Int64 {
        var seen = Set<String>()
        return candidates.filter { !skipped.contains($0.id) && seen.insert(catalog.spaceKey(of: $0)).inserted }.reduce(0) { $0 + $1.estimatedBytes }
    }
}

extension CatalogExecutionResult {
    /// What this run uses of the trial: the reported sizes of the items it actually removed or moved to the Trash, each
    /// space once. Failed, skipped and stopped items count nothing, and a dry run counts nothing.
    public func trialBytes(of approval: CatalogApproval, catalog: Catalog) -> Int64 {
        guard !dryRun else { return 0 }
        let done = Set(records.filter { $0.state == .succeeded && !$0.wasDryRun }.map(\.candidateID))
        return CatalogApproval(candidates: approval.candidates.filter { done.contains($0.id) }, dryRun: false)
            .trialBytes(skipping: [], catalog: catalog)
    }
}

extension CleanupAllowance {
    /// Settings › License's first line while no key is active (Decision 137); nil when unlimited, so the license's own
    /// line shows.
    public var settingsLine: String? {
        guard case .trial(let left) = self else { return nil }
        return left > 0 ? SizeFormatter.text(left) + " of free cleanup left" : "Free trial used"
    }
    /// The review sheet's one line: what the trial has left against the plan's size. Nil when unlimited or in a dry run,
    /// which uses none of it.
    public func reviewLine(plan: Int64, dryRun: Bool) -> String? {
        guard !dryRun, case .trial(let left) = self, let settingsLine else { return nil }
        let size = SizeFormatter.text(plan)
        if permits(plan, dryRun: false) { return settingsLine + " · this cleanup uses " + size }
        return left > 0 ? "This cleanup is \(size), more than the \(SizeFormatter.text(left)) of free cleanup left" : settingsLine + " · this cleanup is " + size
    }
}

/// The license's price beside Buy (Decision 135): 29.99 shown struck through, then 19.99, the same numbers in every
/// currency sold, in the Mac's region currency when it's one of them and US dollars otherwise, as checkout charges. The
/// website's Buy link carries the real price.
public enum LicensePrice {
    public static let buyURL = URL(string: "https://cachedrop.io/buy")!
    /// The currencies the Payment Links sell in (Decision 135).
    static let currencies: Set<String> = ["USD", "CAD", "EUR", "GBP", "AUD"]
    public static func text(locale: Locale = .current) -> (was: String, now: String) {
        let formatter = NumberFormatter()
        formatter.locale = locale; formatter.numberStyle = .currency
        let regional = locale.currency?.identifier
        formatter.currencyCode = regional.map(currencies.contains) == true ? regional : "USD"
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        func format(_ value: Decimal) -> String { formatter.string(from: value as NSDecimalNumber) ?? "\(value)" }
        return (format(29.99), format(19.99))
    }
}
