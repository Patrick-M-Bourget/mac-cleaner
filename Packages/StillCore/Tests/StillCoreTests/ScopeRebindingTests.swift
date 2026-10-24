import Foundation
import Testing
import StillCore

private struct RebindingMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        MetadataSupplement(allocatedBytes: 3, locality: .local, cloud: CloudMetadata(membership: false))
    }
}

@Test func forgottenParentKeepsOnlyExactUnchangedChoicesSupportedByIncludedChild() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRebind-" + UUID().uuidString)
    let child = root.appendingPathComponent("Media")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = child.appendingPathComponent("chosen.pdf")
    try Data([1, 2, 3]).write(to: file)
    try Data([4]).write(to: root.appendingPathComponent("parent-only.pdf"))
    let scanner = FolderScanner(supplement: RebindingMetadata())
    let parentScan = try await scanner.scan(root)
    var draft = PlanDraft()
    for item in parentScan.observations where item.kind == .file { try draft.select(item, in: parentScan, downloadsRoot: root) }
    let originalIDs = Set(draft.selected.map(\.id))
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: root, draft: &draft)
    refresh.cancel(request)
    let childScan = try await scanner.scan(child)
    let proof = draft.rebindUnchangedSelected(removingScope: root, using: [childScan], exclusionFingerprint: "none")
    refresh.retirePending(after: proof, in: draft)
    #expect(proof.reboundIDs.count == 1)
    #expect(proof.dependentIDs.count == 1)
    for id in proof.dependentIDs { draft.remove(id) }
    #expect(draft.selectedCount == 1)
    #expect(originalIDs.contains(try #require(draft.selected.first).id))
    #expect(draft.selected.first?.scope == childScan.scope)
    #expect(refresh.canReview(draft))
}

@Test func scopeRebindingRejectsChangedBytesAndModificationTimeWithoutSelectingNewPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRebind-" + UUID().uuidString)
    let child = root.appendingPathComponent("Media")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = child.appendingPathComponent("bytes.pdf"), time = child.appendingPathComponent("time.pdf")
    try Data([1]).write(to: bytes); try Data([2]).write(to: time)
    let scanner = FolderScanner(supplement: RebindingMetadata())
    let parent = try await scanner.scan(root)
    var draft = PlanDraft()
    for item in parent.observations where item.kind == .file { try draft.select(item, in: parent, downloadsRoot: root) }
    let originalIDs = Set(draft.selected.map(\.id))
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: root, draft: &draft); refresh.cancel(request)
    try Data([1, 2, 3]).write(to: bytes, options: [])
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)], ofItemAtPath: time.path)
    try Data([8]).write(to: child.appendingPathComponent("new.pdf"))
    let alternative = try await scanner.scan(child)
    let proof = draft.rebindUnchangedSelected(removingScope: root, using: [alternative], exclusionFingerprint: "none")
    refresh.retirePending(after: proof, in: draft)
    #expect(proof.reboundIDs.isEmpty)
    #expect(proof.dependentIDs == originalIDs)
    #expect(Set(draft.selected.map(\.id)) == originalIDs)
    #expect(!refresh.canReview(draft))
}

@Test func scopeRebindingPreservesSelectedHardlinkPathsWithoutSelectingTheirUnselectedAlias() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillRebind-" + UUID().uuidString)
    let child = root.appendingPathComponent("Media")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = child.appendingPathComponent("one.pdf"), second = child.appendingPathComponent("two.pdf")
    try Data([1, 2, 3]).write(to: first)
    try FileManager.default.linkItem(at: first, to: second)
    let scanner = FolderScanner(supplement: RebindingMetadata())
    let parent = try await scanner.scan(root)
    var draft = PlanDraft()
    for item in parent.observations where item.kind == .file { try draft.select(item, in: parent, downloadsRoot: root) }
    let ids = Set(draft.selected.map(\.id))
    try FileManager.default.linkItem(at: first, to: child.appendingPathComponent("unchecked.pdf"))
    var refresh = RefreshChoices()
    let request = refresh.begin(scope: root, draft: &draft); refresh.cancel(request)
    let alternative = try await scanner.scan(child)
    let proof = draft.rebindUnchangedSelected(removingScope: root, using: [alternative], exclusionFingerprint: "none")
    refresh.retirePending(after: proof, in: draft)
    #expect(proof.reboundIDs == ids)
    #expect(proof.dependentIDs.isEmpty)
    #expect(Set(draft.selected.map(\.id)) == ids)
    #expect(draft.logicalBytes == 3)
    #expect(refresh.canReview(draft))
    // A proof cannot later bless a newly pending scope after another state transition.
    let pending = refresh.begin(scope: child, draft: &draft); refresh.cancel(pending)
    refresh.retirePending(after: proof, in: draft)
    #expect(!refresh.canReview(draft))
}
