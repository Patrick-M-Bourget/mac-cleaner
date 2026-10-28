import Testing
import CacheDropCore

/// #362: Overview's summary is read on every redraw, so reading it again at the same revision returns what was built.
@Test func readingTwiceAtTheSameRevisionBuildsOnce() {
    var summary = BuiltPerRevision<[String]>()
    var builds = 0
    let first = summary.value(at: 1) { builds += 1; return ["developer"] }
    let second = summary.value(at: 1) { builds += 1; return ["browser"] }

    #expect(first == ["developer"])
    #expect(second == ["developer"])
    #expect(builds == 1)
    #expect(summary.builds == 1)
}

/// A change in what it's built from moves the revision, and the next read builds it again, once.
@Test func aNewRevisionBuildsAgainOnce() {
    var summary = BuiltPerRevision<Int?>()
    #expect(summary.value(at: 0) { nil } == nil)
    #expect(summary.value(at: 0) { 7 } == nil)
    #expect(summary.value(at: 1) { 7 } == 7)
    #expect(summary.value(at: 1) { 8 } == 7)

    #expect(summary.builds == 2)
}
