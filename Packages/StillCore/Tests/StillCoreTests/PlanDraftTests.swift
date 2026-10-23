private struct LocalPlanFixture: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement { MetadataSupplement(allocatedBytes: 3, locality: .local, cloud: CloudMetadata(membership: false)) }
}
import Foundation
import Testing
import StillCore
private func downloadsFixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillPlan-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
@Test func samePathInOverlappingViewsSharesOneLiveSelection() async throws {
    let root = try downloadsFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1, 2, 3]).write(to: root.appendingPathComponent("document.pdf"))
    let scan = try await FolderScanner(supplement: LocalPlanFixture()).scan(root)
    let item = try #require(scan.observations.first)
    var draft = PlanDraft()
    #expect(draft.selectedCount == 0)
    try draft.select(item, in: scan, downloadsRoot: root)
    try draft.select(item, in: scan, downloadsRoot: root)
    #expect(draft.selectedCount == 1)
}
@Test func hardlinkAliasesKeepExactPathsButStorageBytesCountOnce() async throws {
    let root = try downloadsFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first.pdf"), alias = root.appendingPathComponent("alias.pdf")
    try Data([1, 2, 3]).write(to: first)
    try FileManager.default.linkItem(at: first, to: alias)
    let scan = try await FolderScanner(supplement: LocalPlanFixture()).scan(root)
    let items = scan.observations.filter { $0.kind == .file }
    var draft = PlanDraft()
    for item in items { try draft.select(item, in: scan, downloadsRoot: root) }
    #expect(draft.selectedCount == 2)
    #expect(Set(draft.selected.map { $0.url.lastPathComponent }) == ["first.pdf", "alias.pdf"])
    #expect(draft.logicalBytes == 3)
    let removed = try #require(draft.selected.first { $0.url.lastPathComponent == "alias.pdf" })
    draft.remove(removed.id)
    #expect(draft.selected.map { $0.url.lastPathComponent } == ["first.pdf"])
}
@Test func lookalikeRootAndProtectedEntriesRemainBrowseOnly() async throws {
    let actual = try downloadsFixture(), lookalike = try downloadsFixture()
    defer { try? FileManager.default.removeItem(at: actual); try? FileManager.default.removeItem(at: lookalike) }
    try Data([1]).write(to: lookalike.appendingPathComponent("ordinary.zip"))
    let alien = try await FolderScanner(supplement: LocalPlanFixture()).scan(lookalike)
    var draft = PlanDraft()
    let wrong = try #require(alien.observations.first)
    #expect(throws: PlanSelectionError.self) { try draft.select(wrong, in: alien, downloadsRoot: actual) }
    try Data([1]).write(to: actual.appendingPathComponent("protected.sqlite"))
    let scan = try await FolderScanner(supplement: LocalPlanFixture()).scan(actual)
    let protected = try #require(scan.observations.first)
    #expect(throws: PlanSelectionError.self) { try draft.select(protected, in: scan, downloadsRoot: actual) }
    #expect(draft.selectedCount == 0)
}
@Test func searchFilteringAndFreshSessionDoNotApplyOrRestoreSelection() async throws {
    let root = try downloadsFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("visible.pdf"))
    let scan = try await FolderScanner(supplement: LocalPlanFixture()).scan(root)
    let item = try #require(scan.observations.first)
    var draft = PlanDraft(); try draft.select(item, in: scan, downloadsRoot: root)
    let filtered = scan.observations.filter { $0.url.lastPathComponent.contains("not-found") }
    #expect(filtered.isEmpty && draft.contains(item))
    #expect(PlanDraft().selectedCount == 0)
    draft.clear(); #expect(draft.selectedCount == 0)
}
