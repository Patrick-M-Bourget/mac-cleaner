import Foundation
import Testing
@testable import XcodeProbe
@Test func uncertainOrRunningOwnersNeverAuthorizeCleanup() {
    #expect(XcodePolicy.guidance(version: "27.1", ownerInactive: false) == "Owner active or unknown")
    #expect(XcodePolicy.guidance(version: "27.1", ownerInactive: nil) == "Owner active or unknown")
    #expect(XcodePolicy.guidance(version: "26.0", ownerInactive: true) == "Unvalidated Xcode version")
    #expect(XcodePolicy.guidance(version: "27.1", ownerInactive: true) == nil)
}

@Test func approvedObjectCleanupPreservesProtectedArtifacts() throws {
    let probe = try DisposableXcodeProbe()
    let object = "DerivedData/Probe-abc/Build/Intermediates.noindex/Debug/one.o"
    let protected = ["Project/Sources/main.swift", "Archives/Release.xcarchive/object.o", "DerivedData/Probe-abc/Build/Intermediates.noindex/Debug/Symbols.dSYM/object.o", "DerivedData/Probe-abc/Build/Products/Debug/App.app/main.o", "DerivedData/Probe-abc/Build/Intermediates.noindex/Sources/source.o"]
    try probe.seed(object)
    for path in protected { try probe.seed(path) }
    let result = try probe.execute(probe.prepare(probe.approve(version: "27.1", ownerInactive: true)), ownerInactive: true)
    #expect(result.removed == [object])
    #expect(protected.allSatisfy(probe.exists))
    for path in protected { #expect(try probe.contents(path) == "sentinel") }
}

@Test func changedObjectsAreSkippedAndNeverReplaced() throws {
    let probe = try DisposableXcodeProbe()
    let path = "DerivedData/Probe-abc/Build/Intermediates.noindex/one.o"
    try probe.seed(path, text: "old")
    let run = try probe.prepare(probe.approve(version: "27.1", ownerInactive: true))
    try probe.seed(path, text: "new")
    let result = try probe.execute(run, ownerInactive: true)
    #expect(result.skipped == [path])
    #expect(probe.exists(path))
}

@Test func unknownLayoutsAndSymlinkTreesAreGuidanceOnly() throws {
    let probe = try DisposableXcodeProbe()
    try probe.seed("Outside/sentinel.o")
    try probe.seed("DerivedData/Unknown/Build/Intermediates.noindex/one.o")
    try probe.link("DerivedData/Probe-abc/Build/Intermediates.noindex", to: "Outside")
    let result = try probe.execute(probe.prepare(probe.approve(version: "27.1", ownerInactive: true)), ownerInactive: true)
    #expect(result.removed.isEmpty)
    #expect(probe.exists("Outside/sentinel.o"))
}

@Test func interruptedFixtureRunCannotAutomaticallyResume() throws {
    let probe = try DisposableXcodeProbe()
    let first = "DerivedData/Probe-abc/Build/Intermediates.noindex/a.o"
    let next = "DerivedData/Probe-abc/Build/Intermediates.noindex/b.o"
    try probe.seed(first)
    try probe.seed(next)
    let run = try probe.prepare(probe.approve(version: "27.1", ownerInactive: true))
    let result = try probe.execute(run, ownerInactive: true, stopAfter: 1)
    #expect(result.removed == [first])
    #expect(result.notStarted == [next])
    #expect(throws: DisposableXcodeProbe.ProbeError.self) { try probe.execute(run, ownerInactive: true) }
    #expect(probe.exists(next))
}

@Test func ownerBecomingActiveAfterReviewBlocksExecution() throws {
    let probe = try DisposableXcodeProbe()
    let path = "DerivedData/Probe-abc/Build/Intermediates.noindex/a.o"
    try probe.seed(path)
    let run = try probe.prepare(probe.approve(version: "27.1", ownerInactive: true))
    #expect(throws: DisposableXcodeProbe.ProbeError.self) { try probe.execute(run, ownerInactive: false) }
    #expect(try probe.contents(path) == "sentinel")
}
