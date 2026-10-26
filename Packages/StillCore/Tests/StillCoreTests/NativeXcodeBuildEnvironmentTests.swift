import Foundation
import Testing
import StillCore

private struct OwnedXcodeSnapshot: XcodeOwnerSnapshotReading {
    let value: XcodeOwnerSnapshot
    func snapshot() throws -> XcodeOwnerSnapshot { value }
}

@Test func nativeXcodeObservationRecognizesOwnersWithoutRequiringEveryProcessIdentity() throws {
    let unrelated = XcodeProcessRecord(pid: 42, uid: 501, shortName: "ordinary-app", executable: nil, started: 1)
    let exited = XcodeProcessRecord(pid: 43, uid: nil, shortName: "", executable: nil, started: nil, exited: true)
    let closed = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [unrelated, exited], complete: true)))
    #expect(try closed.ownerObservation().activity == .closed)
    let compiler = XcodeProcessRecord(pid: 44, uid: 501, shortName: "swift-frontend", executable: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend", started: 2)
    let active = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [unrelated, compiler], complete: true)))
    #expect(try active.ownerObservation().activity == .running)
}

@Test func nativeXcodeObservationRefusesRelevantUnknownAndIncompleteSnapshots() throws {
    let candidate = XcodeProcessRecord(pid: 44, uid: 501, shortName: "SWBBuildService", executable: nil, started: 2)
    let unknown = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [candidate], complete: true)))
    #expect(try unknown.ownerObservation().activity == .unknown)
    let incomplete = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [], complete: false)))
    #expect(try incomplete.ownerObservation().activity == .unknown)
}

@Test func nativeXcodeObservationRecognizesSharedServicesAndTheirTruncatedUnknownNames() throws {
    let service = XcodeProcessRecord(pid: 50, uid: 501, shortName: "SWBBuildService", executable: "/Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/PlugIns/SWBBuildService.bundle/Contents/MacOS/SWBBuildService", started: 3)
    let active = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [service], complete: true)))
    #expect(try active.ownerObservation().activity == .running)
    let unavailable = XcodeProcessRecord(pid: 51, uid: 501, shortName: "SWBBuildServiceB", executable: nil, started: 4)
    let unknown = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [unavailable], complete: true)))
    #expect(try unknown.ownerObservation().activity == .unknown)
}

@Test func nativeXcodeObservationRefusesInconsistentCandidateAndUnqualifiedInstallation() throws {
    let changed = XcodeProcessRecord(pid: 60, uid: 501, shortName: "xcodebuild", executable: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", started: 5, consistent: false)
    let environment = NativeXcodeBuildEnvironment(ownerReader: OwnedXcodeSnapshot(value: .init(currentUID: 501, records: [changed], complete: true)), applicationURL: URL(fileURLWithPath: "/never-probe-Xcode.app"))
    #expect(try environment.ownerObservation().activity == .unknown)
    #expect(throws: (any Error).self) { try environment.validateInstallation() }
    #expect(throws: (any Error).self) { try environment.projects(in: URL(fileURLWithPath: "/never-inspected")) }
}
