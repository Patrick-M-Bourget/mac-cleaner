import Foundation
import Testing
import Darwin
import StillCore

private struct XcodeFixture: XcodeBuildEnvironment {
    let root: URL
    var activity: XcodeOwnerActivity = .running
    func validateInstallation() throws {}
    func standardDerivedDataURL() throws -> URL { root.appendingPathComponent("DerivedData") }
    func ownerObservation() throws -> XcodeOwnerObservation { .init(activity: activity, reason: "Owned builder") }
    func projects(in root: URL) throws -> [XcodeProjectAssociation] {
        [.init(projectURL: self.root.appendingPathComponent("Probe.xcodeproj"), derivedDataURL: root.appendingPathComponent("Probe-hash"), intermediateRootURL: root.appendingPathComponent("Probe-hash/Build/Intermediates.noindex"), metadataURL: root.appendingPathComponent("Probe-hash/info.plist"))]
    }
    func now() -> Date { Date(timeIntervalSince1970: 42) }
}
private func xcodeFixture() throws -> URL {
    let canonical = realpath(FileManager.default.temporaryDirectory.path, nil)!
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical)).appendingPathComponent("StillXcodeCore-" + UUID().uuidString)
    let objects = root.appendingPathComponent("DerivedData/Probe-hash/Build/Intermediates.noindex/Probe.build/Debug/Probe.build/Objects-normal/arm64")
    try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Probe.xcodeproj"), withIntermediateDirectories: true)
    try Data("metadata".utf8).write(to: root.appendingPathComponent("DerivedData/Probe-hash/info.plist"))
    try Data("object".utf8).write(to: objects.appendingPathComponent("main.o"))
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
    #expect(inspection.projects.first?.artifacts.first?.logicalBytes == 6)
    #expect(inspection.owner.activity == .running)
    do { _ = try await module.approve(artifactIDs: Set(inspection.projects.flatMap(\.artifacts).map(\.id))); Issue.record("Running owner approved") } catch {}
}

