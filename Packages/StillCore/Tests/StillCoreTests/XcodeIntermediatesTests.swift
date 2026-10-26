import Foundation
import Testing
import Darwin
import StillCore

private struct XcodeFixture: XcodeBuildEnvironment {
    let root: URL
    var activity: XcodeOwnerActivity = .running
    var unknownProject = false
    func validateInstallation() throws {}
    func standardDerivedDataURL() throws -> URL { root.appendingPathComponent("DerivedData") }
    func ownerObservation() throws -> XcodeOwnerObservation { .init(activity: activity, reason: "Owned builder") }
    func projects(in root: URL) throws -> XcodeProjectMapping {
        .init(associations: [.init(projectURL: self.root.appendingPathComponent("Probe.xcodeproj"), derivedDataURL: root.appendingPathComponent("Probe-hash"), intermediateRootURL: root.appendingPathComponent("Probe-hash/Build/Intermediates.noindex"), metadataURL: root.appendingPathComponent("Probe-hash/info.plist"), projectMetadataURLs: [self.root.appendingPathComponent("Probe.xcodeproj/project.pbxproj")])], unavailable: unknownProject ? [.init(derivedDataURL: root.appendingPathComponent("Unknown-hash"), reason: "Project association is unknown.")] : [])
    }
    func now() -> Date { Date(timeIntervalSince1970: 42) }
}
// Synthetic bounded format fixture, not a claim of compiler-generated native evidence.
private func xcodeObjectData(_ payload: String = "object") -> Data {
    Data([0xcf,0xfa,0xed,0xfe, 0x0c,0,0,1, 0,0,0,0, 1,0,0,0, 1,0,0,0, 8,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0, 8,0,0,0]) + Data(payload.utf8)
}
private func xcodeFixture() throws -> URL {
    let canonical = realpath(FileManager.default.temporaryDirectory.path, nil)!
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent("StillXcodeCore-" + UUID().uuidString)
    let objects = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64")
    try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Probe.xcodeproj"), withIntermediateDirectories: true)
    try Data("project metadata".utf8).write(to: root.appendingPathComponent("Probe.xcodeproj/project.pbxproj"))
    try Data("metadata".utf8).write(to: root.appendingPathComponent("DerivedData/Probe-hash/info.plist"))
    try xcodeObjectData().write(to: objects.appendingPathComponent("main.o"))
    try Data("preserve".utf8).write(to: objects.appendingPathComponent("main.dia"))
    return root
}
@Test func xcodeInspectionRetainsExactFindingsWithOwnerOpenButCannotApprove() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let module = XcodeIntermediates(environment: XcodeFixture(root: root), journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    #expect(inspection.unavailableReason == nil)
    #expect(inspection.projects.count == 1)
    #expect(inspection.projects.first?.artifacts.count == 1)
    #expect(inspection.projects.first?.artifacts.first?.logicalBytes == 46)
    #expect(inspection.owner.activity == .running)
    do { _ = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id))); Issue.record("Running owner approved") } catch {}
}

@Test func xcodeExactApprovalRemovesOnlyUnchangedFrozenObjectsAndReloadsOutcomes() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let objects = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64")
    try xcodeObjectData("second").write(to: objects.appendingPathComponent("helper.o"))
    let environment = XcodeFixture(root: root, activity: .closed)
    let journal = root.appendingPathComponent("journal.json")
    let module = XcodeIntermediates(environment: environment, journalURL: journal)
    let inspection = await module.inspectStandardDerivedData()
    let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
    try xcodeObjectData("replacement").write(to: objects.appendingPathComponent("main.o"), options: .atomic)
    try xcodeObjectData("new").write(to: objects.appendingPathComponent("late.o"))
    let result = await module.execute(approval, cancellation: CleanupCancellation())
    #expect(result.disposition == .completed)
    #expect(result.artifacts.filter { $0.status == .succeeded }.count == 1)
    #expect(result.artifacts.filter { $0.status == .skipped }.count == 1)
    #expect(!FileManager.default.fileExists(atPath: objects.appendingPathComponent("helper.o").path))
    #expect(try Data(contentsOf: objects.appendingPathComponent("main.o")) == xcodeObjectData("replacement"))
    #expect(try Data(contentsOf: objects.appendingPathComponent("late.o")) == xcodeObjectData("new"))
    #expect(try String(contentsOf: objects.appendingPathComponent("main.dia"), encoding: .utf8) == "preserve")
    let reloaded = XcodeIntermediates(environment: environment, journalURL: journal)
    #expect(try await reloaded.records().first?.artifacts.filter { $0.status == .succeeded }.count == 1)
    let replay = await module.execute(approval, cancellation: CleanupCancellation())
    #expect(replay.disposition == .rejected)
}

@Test func xcodeJournalDestinationConflictStopsBeforeNextMutationWithoutInventingUnknownAction() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let objects = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64")
    try xcodeObjectData("second").write(to: objects.appendingPathComponent("helper.o"))
    let sentinel = root.appendingPathComponent("protected.txt")
    try Data("protected journal destination".utf8).write(to: sentinel)
    let journal = root.appendingPathComponent("journal.json")
    let module = XcodeIntermediates(environment: XcodeFixture(root: root, activity: .closed), journalURL: journal)
    let inspection = await module.inspectStandardDerivedData()
    let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
    let result = await module.execute(approval, cancellation: CleanupCancellation()) { progress in
        if progress.resolved == 1 {
            try? FileManager.default.removeItem(at: journal)
            try? FileManager.default.createSymbolicLink(at: journal, withDestinationURL: sentinel)
        }
    }
    #expect(result.disposition == .recoveryRequired)
    #expect(result.artifacts.filter { $0.status == .succeeded }.count == 1)
    #expect(result.artifacts.filter { $0.status == .notStarted }.count == 1)
    #expect(result.artifacts.filter { $0.status == .unknown }.isEmpty)
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "protected journal destination")
    #expect(try FileManager.default.contentsOfDirectory(atPath: objects.path).filter { $0.hasSuffix(".o") }.count == 1)
}

@Test func xcodeCannotApproveRegeneratedArtifactWithoutFreshInspection() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let object = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64/main.o")
    let module = XcodeIntermediates(environment: XcodeFixture(root: root, activity: .closed), journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    try xcodeObjectData("regenerated").write(to: object, options: .atomic)
    do {
        _ = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
        Issue.record("Regenerated artifact entered confirmation without fresh review")
    } catch {}
    #expect(try Data(contentsOf: object) == xcodeObjectData("regenerated"))
}

@Test func xcodeUnknownProjectAssociationIsVisibleWithoutHidingVerifiedProject() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let environment = XcodeFixture(root: root, activity: .closed, unknownProject: true)
    let module = XcodeIntermediates(environment: environment, journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    #expect(inspection.projects.count == 1)
    #expect(inspection.unavailableProjects.first?.reason == "Project association is unknown.")
    let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
    #expect(approval.artifacts.count == 1)
}

@Test func xcodeProviderLocationDoesNotCreateArtifactAuthority() async throws {
    let original = try xcodeFixture()
    let outer = original.deletingLastPathComponent().appendingPathComponent("StillXcodeProvider-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: outer) }
    let root = outer.appendingPathComponent("Library/CloudStorage/OwnedFixture")
    try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original, to: root)
    let module = XcodeIntermediates(environment: XcodeFixture(root: root, activity: .closed), journalURL: outer.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    #expect(inspection.projects.isEmpty)
    #expect(inspection.unavailableReason != nil)
}

@Test func xcodeChangedProjectMetadataSafetyStopsRatherThanCancelsApprovedWorkspace() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let module = XcodeIntermediates(environment: XcodeFixture(root: root, activity: .closed), journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
    try Data("changed project settings".utf8).write(to: root.appendingPathComponent("Probe.xcodeproj/project.pbxproj"))
    let result = await module.execute(approval, cancellation: CleanupCancellation())
    #expect(result.disposition == .safetyStopped)
    #expect(result.artifacts.allSatisfy { $0.status == .notStarted })
    #expect(result.stopReason != nil)
    #expect(try Data(contentsOf: root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64/main.o")) == xcodeObjectData())
}

private final class SwitchingXcodeFixture: XcodeBuildEnvironment, @unchecked Sendable {
    let base: XcodeFixture
    private let lock = NSLock()
    private var activity: XcodeOwnerActivity = .closed
    init(root: URL) { base = XcodeFixture(root: root, activity: .closed) }
    func setRunning() { lock.lock(); activity = .running; lock.unlock() }
    func validateInstallation() throws { try base.validateInstallation() }
    func standardDerivedDataURL() throws -> URL { try base.standardDerivedDataURL() }
    func ownerObservation() throws -> XcodeOwnerObservation { lock.lock(); defer { lock.unlock() }; return .init(activity: activity, reason: activity == .running ? "Owned build appeared." : nil) }
    func projects(in root: URL) throws -> XcodeProjectMapping { try base.projects(in: root) }
    func now() -> Date { base.now() }
}
@Test func xcodeUserStopAndOwnerSafetyStopKeepDistinctDurableOutcomes() async throws {
    for ownerStop in [false, true] {
        let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let objects = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64")
        try xcodeObjectData("second").write(to: objects.appendingPathComponent("helper.o"))
        let environment = SwitchingXcodeFixture(root: root)
        let module = XcodeIntermediates(environment: environment, journalURL: root.appendingPathComponent("journal.json"))
        let inspection = await module.inspectStandardDerivedData()
        let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
        let cancellation = CleanupCancellation()
        let result = await module.execute(approval, cancellation: cancellation) { progress in
            if progress.resolved == 1 { if ownerStop { environment.setRunning() } else { cancellation.cancel() } }
        }
        #expect(result.disposition == (ownerStop ? .safetyStopped : .cancelled))
        #expect(result.artifacts.filter { $0.status == .succeeded }.count == 1)
        #expect(result.artifacts.filter { $0.status == (ownerStop ? .notStarted : .cancelled) }.count == 1)
        #expect(cancellation.isCancelled == !ownerStop)
        #expect(try await module.records().first?.disposition == result.disposition)
        #expect(try FileManager.default.contentsOfDirectory(atPath: objects.path).filter { $0.hasSuffix(".o") }.count == 1)
    }
}

@Test func xcodeInspectionPreservesNonObjectBytesDespiteObjectSuffixAndMatchingLayout() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let unrelated = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64/unrelated.o")
    try Data("personal text with object suffix".utf8).write(to: unrelated)
    let module = XcodeIntermediates(environment: XcodeFixture(root: root, activity: .closed), journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    #expect(inspection.projects.first?.artifacts.count == 1)
    let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
    let result = await module.execute(approval, cancellation: CleanupCancellation())
    #expect(result.artifacts.count == 1)
    #expect(try String(contentsOf: unrelated, encoding: .utf8) == "personal text with object suffix")
}

@Test func xcodePublicModulePreservesProtectedArtifactAndLinkMatrix() async throws {
    let root = try xcodeFixture(); defer { try? FileManager.default.removeItem(at: root) }
    let intermediate = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex")
    let objects = intermediate.appendingPathComponent("Probe.build/Debug/Probe.build/Objects-normal/arm64")
    let paths = [
        "Sources/keep.o", "Archives/Owned.xcarchive/Products/keep.o",
        "DerivedData/Probe-hash/Build/Products/Debug/Owned.dSYM/Contents/Resources/DWARF/keep.o",
        "DerivedData/Probe-hash/Build/Products/Debug/keep.o",
        "DerivedData/Probe-hash/SourcePackages/checkouts/Owned/keep.o",
        "DerivedData/Probe-hash/Index.noindex/keep.o", "DerivedData/Probe-hash/ModuleCache.noindex/keep.o",
        "DerivedData/Probe-hash/Build/Intermediates.noindex/Owned.dSYM/Debug/Target.build/Objects-normal/arm64/keep.o",
        "DerivedData/Probe-hash/Build/Intermediates.noindex/Owned.xcarchive/Debug/Target.build/Objects-normal/arm64/keep.o",
        "DerivedData/Probe-hash/Build/Intermediates.noindex/SourcePackages/Debug/Target.build/Objects-normal/arm64/keep.o",
        "DerivedData/Probe-hash/Build/Intermediates.noindex/Index.noindex/Debug/Target.build/Objects-normal/arm64/keep.o",
        "DerivedData/Probe-hash/Build/Intermediates.noindex/ModuleCache.noindex/Debug/Target.build/Objects-normal/arm64/keep.o",
        "External/Debug/Target.build/Objects-normal/arm64/keep.o"
    ]
    var protected: [URL: Data] = [:]
    for path in paths {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = xcodeObjectData("protected " + path)
        try data.write(to: url); protected[url] = data
    }
    let source = root.appendingPathComponent("Sources/keep.o")
    try FileManager.default.linkItem(at: source, to: objects.appendingPathComponent("hardlinked.o"))
    try FileManager.default.createSymbolicLink(at: objects.appendingPathComponent("linked.o"), withDestinationURL: source)
    try FileManager.default.createSymbolicLink(at: intermediate.appendingPathComponent("Redirect.build"), withDestinationURL: root.appendingPathComponent("External"))
    let module = XcodeIntermediates(environment: XcodeFixture(root: root, activity: .closed), journalURL: root.appendingPathComponent("journal.json"))
    let inspection = await module.inspectStandardDerivedData()
    #expect(inspection.projects.first?.artifacts.count == 1)
    let approval = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id)))
    let result = await module.execute(approval, cancellation: CleanupCancellation())
    #expect(result.artifacts.filter { $0.status == .succeeded }.count == 1)
    for (url, expected) in protected { #expect(try Data(contentsOf: url) == expected) }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: objects.appendingPathComponent("linked.o").path) == source.path)
    #expect(FileManager.default.fileExists(atPath: objects.appendingPathComponent("hardlinked.o").path))
    #expect(try String(contentsOf: root.appendingPathComponent("Probe.xcodeproj/project.pbxproj"), encoding: .utf8) == "project metadata")
}
