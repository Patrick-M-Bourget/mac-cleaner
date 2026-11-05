import Foundation

/// Smart clean's one-screen summary (#779, Decision 173): "Free up X" over its rows, "Clean up X" in the bottom bar, and the
/// one caption under the rows. X is what the ticked items release (SPEC section 6): never what goes to the Trash, "Up to"
/// when part of it is copies that share disk blocks.
public struct SmartCleanSummary: Sendable, Equatable {
    public static let title = "Free up"
    public static let notIncluded = "Not included: newer downloads, models, iCloud copies"
    public static let adjust = "Adjust in Cleanup plan"

    /// What the ticked items release; nil when nothing ticked releases space.
    public let freeUp: String?
    /// How many items are ticked, Trash-bound ones included.
    public let itemCount: Int

    public init(ticked: [Candidate], catalog: Catalog) {
        let releasing = ticked.filter(\.releasesSpace)
        itemCount = ticked.count
        freeUp = releasing.isEmpty ? nil : SizeEstimate(sum: releasing.map(SizeEstimate.init))
            .text(upperBound: releasing.contains { catalog.rule($0.ruleID)?.estimateIsUpperBound == true })
    }

    /// The bottom bar's button: "Clean up X", or "Clean up" when nothing ticked releases space.
    public var cleanUpTitle: String { freeUp.map { "Clean up " + $0 } ?? "Clean up" }
}
