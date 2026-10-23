import Foundation
import Testing
import StillCore
@Test func zeroSelectionCannotCreateApproval() {
    let draft = PlanDraft()
    #expect(throws: PlanSelectionError.self) { try draft.review() }
}
private struct ReviewLocalMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement { MetadataSupplement(allocatedBytes: 3, locality: .local, cloud: CloudMetadata(membership: false)) }
}
@Test func bulkMaterializesNestedFilesAndMixedRefinementWithoutSelectingNewDiscoveries() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("first.pdf"))
    try Data([2, 3]).write(to: root.appendingPathComponent("Nested/second.zip"))
    let scanner = FolderScanner(supplement: ReviewLocalMetadata())
    let scan = try await scanner.scan(root)
    let downloads = try DownloadsRoot(url: root)
    var draft = PlanDraft()
    _ = draft.selectAll(in: [scan, scan], downloads: downloads)
    #expect(draft.selectedCount == 2)
    #expect(draft.categoryState(in: [scan], downloads: downloads) == .checked)
    let first = try #require(draft.selected.first)
    draft.remove(first.id)
    #expect(draft.categoryState(in: [scan], downloads: downloads) == .mixed)
    try Data([4]).write(to: root.appendingPathComponent("new.pdf"))
    let updated = try await scanner.scan(root)
    #expect(draft.selectedCount == 1)
    #expect(!draft.selected.contains { $0.url.lastPathComponent == "new.pdf" })
    #expect(draft.categoryState(in: [updated], downloads: downloads) == .mixed)
}
@Test func reviewedBatchIsImmutableAndChangesRequireNewApproval() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<200 { try Data([1]).write(to: root.appendingPathComponent("\(index).pdf")) }
    let scan = try await FolderScanner(supplement: ReviewLocalMetadata()).scan(root)
    var draft = PlanDraft()
    _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
    let review = try draft.review()
    #expect(review.targets.count == 200)
    let approved = try draft.approve(review, at: Date(timeIntervalSince1970: 10))
    draft.remove(try #require(draft.selected.first).id)
    #expect(review.targets.count == 200 && approved.targets.count == 200)
    #expect(throws: PlanSelectionError.self) { try draft.approve(review) }
    #expect(approved.action == "moveToTrash")
    #expect(approved.approvedAt == Date(timeIntervalSince1970: 10))
    let updated = try draft.review()
    draft.invalidateReview()
    #expect(throws: PlanSelectionError.self) { try draft.approve(updated) }
}
private struct OneDeniedMetadata: MetadataSupplementReading {
    func read(_ url: URL) throws -> MetadataSupplement {
        if url.lastPathComponent == "restricted.pdf" { throw CocoaError(.fileReadNoPermission) }
        return MetadataSupplement(allocatedBytes: 3, locality: .local, cloud: CloudMetadata(membership: false))
    }
}
@Test func bulkIncludesVerifiedSiblingWithoutIncludingDeniedMetadataTarget() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["good.pdf", "restricted.pdf"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
    let scan = try await FolderScanner(supplement: OneDeniedMetadata()).scan(root)
    var draft = PlanDraft()
    _ = draft.selectAll(in: [scan], downloads: try DownloadsRoot(url: root))
    #expect(!scan.isComplete)
    #expect(draft.selected.map { $0.url.lastPathComponent } == ["good.pdf"])
}
