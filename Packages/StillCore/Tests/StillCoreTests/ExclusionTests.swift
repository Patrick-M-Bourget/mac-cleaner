import Foundation
import Testing
import StillCore

@Test func explicitPathRulesPersistAndDistinguishRenameReplacementVolumeAndOverlaps() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString).resolvingSymlinksInPath()
    let folder = base.appendingPathComponent("Chosen"), file = folder.appendingPathComponent("one.txt")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    try Data([1]).write(to: file)
    let rule = try ExclusionRule.capture(file)
    let parent = try ExclusionRule.capture(folder)
    let store = ExclusionStore(directory: base.appendingPathComponent("State"))
    try await store.add(rule); try await store.add(parent)
    let saved = try await ExclusionStore(directory: base.appendingPathComponent("State")).policy()
    #expect(saved.rules.count == 2)
    #expect(saved.matches(file, volumeID: rule.volumeID))
    #expect(!saved.matches(file, volumeID: "another-volume"))
    let renamed = folder.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: renamed)
    #expect(!ExclusionPolicy(rules: [rule]).matches(renamed, volumeID: rule.volumeID))
    try Data([9]).write(to: file)
    #expect(saved.matches(file, volumeID: rule.volumeID))
    try await store.remove(parent.id)
    #expect(try await store.policy().matches(file, volumeID: rule.volumeID))
    #expect(try await store.policy().matches(renamed, volumeID: rule.volumeID) == false)
    try await store.reset()
    #expect(try await store.policy().rules.isEmpty)
}

private struct ExclusionMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        if url.lastPathComponent == "do-not-read.txt" { throw CocoaError(.fileReadNoPermission) }
        return .init(allocatedBytes: 3, locality: .local, cloud: .init(membership: false))
    }
}
@Test func excludedBoundariesAreNotEnumeratedAndHardlinkAliasesRemainIndependent() async throws {
    let scope = FileManager.default.temporaryDirectory.appendingPathComponent("StillExclusions-" + UUID().uuidString).resolvingSymlinksInPath()
    let hidden = scope.appendingPathComponent("Excluded")
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scope) }
    try Data([9, 9, 9, 9, 9]).write(to: hidden.appendingPathComponent("do-not-read.txt"))
    try Data([1, 2, 3]).write(to: scope.appendingPathComponent("keep.txt"))
    let original = scope.appendingPathComponent("one.txt"), alias = scope.appendingPathComponent("alias.txt")
    try Data([1, 2, 3, 4]).write(to: original); try FileManager.default.linkItem(at: original, to: alias)
    let policy = ExclusionPolicy(rules: [try .capture(hidden), try .capture(original)])
    let result = try await FolderScanner(supplement: ExclusionMetadata()).scan(scope, exclusions: policy)
    #expect(result.isComplete && result.logicalBytes == 7)
    #expect(result.totalLogicalBytes == nil)
    #expect(result.excludedEntryCount == 2)
    #expect(result.exclusionFingerprint == policy.fingerprint)
    #expect(!result.observations.contains { $0.url.lastPathComponent == "Excluded" || $0.url.lastPathComponent == "one.txt" || $0.url.lastPathComponent == "do-not-read.txt" })
    #expect(result.observations.contains { $0.url.lastPathComponent == "alias.txt" })
    let excludedRoot = try await FolderScanner().scan(hidden, exclusions: policy)
    #expect(!excludedRoot.isComplete && excludedRoot.totalLogicalBytes == nil)
}
