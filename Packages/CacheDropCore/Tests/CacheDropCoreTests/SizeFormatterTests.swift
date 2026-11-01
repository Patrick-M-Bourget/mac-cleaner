import Testing
@testable import CacheDropCore

@Test func sizeFormatterUsesDecimalUnits() {
    #expect(SizeFormatter.text(12_200_000_000) == "12.2 GB")
}

@Test func sizeFormatterKeepsUnknownDistinctFromZero() {
    #expect(SizeFormatter.text(SizeEstimate.unknown) == "Unknown")
}

@Test func sizeFormatterLabelsAnUpperBound() {
    #expect(SizeFormatter.text(1_000, upperBound: true) == "Up to 1 KB")
}

/// #568: nothing to free is never hedged ("Up to Zero KB" on Overview after a cleanup).
@Test func sizeFormatterNeverHedgesZero() {
    #expect(SizeFormatter.text(0, upperBound: true) == "Zero KB")
    #expect(SizeFormatter.text(SizeEstimate.measured(0), upperBound: true) == "Zero KB")
}

@Test func sizeFormatterPreservesEachEstimateKind() {
    let estimates: [SizeEstimate] = [.measured(1_000), .about(1_000), .atLeast(1_000), .unknown]
    #expect(estimates.map { SizeFormatter.text($0) } == ["1 KB", "About 1 KB", "At least 1 KB", "Unknown"])
    #expect(SizeFormatter.text(0) == "Zero KB")
    #expect(SizeFormatter.text(nil) == "Unknown")
}

@Test func sizeFormatterPartialSizesStayUnknownUntilSomethingIsMeasured() {
    #expect(SizeFormatter.text(0, complete: false) == "Unknown")
    #expect(SizeFormatter.text(1_000, complete: false, upperBound: true, estimate: true) == "At least 1 KB")
    #expect(SizeFormatter.text(SizeEstimate.atLeast(0)) == "Unknown")
}

@Test func sizeFormatterUsesOneQualifierForAnEstimatedUpperBound() {
    #expect(SizeFormatter.text(1_000, upperBound: true, estimate: true) == "About 1 KB")
    #expect(SizeFormatter.text(SizeEstimate.about(1_000), upperBound: true) == "About 1 KB")
}
